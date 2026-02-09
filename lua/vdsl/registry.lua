--- Registry: ComfyUI server resource discovery.
-- Uses Transport for HTTP and Matcher for fuzzy matching.
-- Single responsibility: resource catalog + lookup.

local json      = require("vdsl.json")
local transport = require("vdsl.transport")
local matcher   = require("vdsl.matcher")

local Registry = {}
Registry.__index = Registry

-- Node type -> input field -> resource category
local RESOURCE_MAP = {
  { node = "CheckpointLoaderSimple", field = "ckpt_name",       key = "checkpoints" },
  { node = "VAELoader",             field = "vae_name",         key = "vaes" },
  { node = "LoraLoader",            field = "lora_name",        key = "loras" },
  { node = "ControlNetLoader",      field = "control_net_name", key = "controlnets" },
  { node = "UpscaleModelLoader",    field = "model_name",       key = "upscalers" },
}

--- Extract COMBO options from a node's input definition.
local function extract_combo(info, node_type, field_name)
  local node = info[node_type]
  if not node then return {} end
  local input = node.input
  if not input then return {} end
  local required = input.required
  if not required then return {} end
  local field = required[field_name]
  if not field or type(field) ~= "table" then return {} end
  local options = field[1]
  if type(options) ~= "table" then return {} end
  return options
end

local function extract_all_resources(info)
  local resources = {}
  for _, mapping in ipairs(RESOURCE_MAP) do
    resources[mapping.key] = extract_combo(info, mapping.node, mapping.field)
  end
  return resources
end

--- Populate resource fields from extracted data.
local function populate(self, info)
  local resources = extract_all_resources(info)
  self.checkpoints = resources.checkpoints
  self.vaes        = resources.vaes
  self.loras       = resources.loras
  self.controlnets = resources.controlnets
  self.upscalers   = resources.upscalers
end

--- Connect to a ComfyUI server and discover resources.
-- @param url string server URL
-- @param opts table|nil { token = "Bearer ...", headers = { ... } }
-- @return Registry
function Registry.connect(url, opts)
  if type(url) ~= "string" then
    error("Registry.connect: url must be a string", 2)
  end
  if not url:match("^https?://") then
    error("Registry.connect: url must start with http:// or https://", 2)
  end

  url = url:gsub("/+$", "")
  opts = opts or {}

  -- Build headers from opts
  local headers = opts.headers
  if opts.token then
    headers = headers or {}
    headers["Authorization"] = "Bearer " .. opts.token
  end

  local body = transport.get(url .. "/object_info", headers)
  local info = json.decode(body)

  local self = setmetatable({}, Registry)
  self._url = url
  self._headers = headers
  self._object_info = info
  populate(self, info)
  return self
end

--- Create a Registry from pre-parsed object_info data.
-- @param info table parsed /object_info response
-- @param url string|nil optional server URL for queue()
-- @param headers table|nil optional HTTP headers
-- @return Registry
function Registry.from_object_info(info, url, headers)
  local self = setmetatable({}, Registry)
  self._url = url
  self._headers = headers
  self._object_info = info
  populate(self, info)
  return self
end

--- Fuzzy-match a checkpoint name.
function Registry:checkpoint(query)
  return matcher.find(query, self.checkpoints, "checkpoint")
end

--- Fuzzy-match a VAE name.
function Registry:vae(query)
  return matcher.find(query, self.vaes, "vae")
end

--- Fuzzy-match a LoRA name and return a Cast-compatible table.
function Registry:lora(query, weight)
  local name = matcher.find(query, self.loras, "lora")
  return { name = name, weight = weight or 1.0 }
end

--- Fuzzy-match a ControlNet model name.
function Registry:controlnet(query)
  return matcher.find(query, self.controlnets, "controlnet")
end

--- Fuzzy-match an upscaler model name.
function Registry:upscaler(query)
  return matcher.find(query, self.upscalers, "upscaler")
end

--- Queue a render result to the ComfyUI server.
function Registry:queue(render_result)
  if not self._url then
    error("cannot queue without server URL (use connect())", 2)
  end
  if not render_result or not render_result.prompt then
    error("queue requires a render result (from render())", 2)
  end
  return transport.post_json(self._url .. "/prompt", {
    prompt = render_result.prompt,
  }, self._headers)
end

-- ============================================================
-- Execution pipeline: queue → poll → download → embed
-- ============================================================

local function sleep(seconds)
  seconds = tonumber(seconds)
  if not seconds or seconds < 0 then
    error("sleep: seconds must be a non-negative number", 2)
  end
  local ok, socket = pcall(require, "socket")
  if ok and socket and socket.sleep then
    socket.sleep(seconds)
    return
  end
  os.execute("sleep " .. string.format("%.3f", seconds))
end

--- Extract basename from a path or filename (strip directory components).
local function safe_filename(name)
  if type(name) ~= "string" or name == "" then
    error("invalid filename", 2)
  end
  -- Strip directory separators to prevent path traversal
  local base = name:match("([^/\\]+)$")
  if not base or base == "" or base == "." or base == ".." then
    error("unsafe filename: " .. name, 2)
  end
  return base
end

--- URL-encode a string for query parameters.
local function url_encode(str)
  return tostring(str):gsub("([^%w%-%.%_%~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
end

--- Poll /history for completion of a queued prompt.
-- @param prompt_id string
-- @param opts table|nil { timeout = 300, interval = 1 }
-- @return table history entry for this prompt
function Registry:poll(prompt_id, opts)
  if not self._url then
    error("cannot poll without server URL (use connect())", 2)
  end
  if type(prompt_id) ~= "string" or prompt_id == "" then
    error("poll: prompt_id is required", 2)
  end

  opts = opts or {}
  local timeout  = opts.timeout or 300
  local interval = opts.interval or 1

  local elapsed = 0
  while elapsed < timeout do
    local ok, body = pcall(transport.get, self._url .. "/history/" .. prompt_id, self._headers)
    if ok and body then
      local history = json.decode(body)
      if history[prompt_id] then
        local entry = history[prompt_id]
        if entry.status and entry.status.completed then
          -- Check for execution error
          if entry.status.status_str == "error" then
            local msg = "ComfyUI execution error"
            if entry.status.messages then
              for _, m in ipairs(entry.status.messages) do
                if m[1] == "execution_error" and m[2] and m[2].message then
                  msg = msg .. ": " .. m[2].message
                end
              end
            end
            error(msg, 2)
          end
          return entry
        end
      end
    end

    sleep(interval)
    elapsed = elapsed + interval
  end

  error("poll timeout after " .. timeout .. "s for prompt " .. prompt_id, 2)
end

--- Download a generated image from ComfyUI /view endpoint.
-- @param image_info table { filename, subfolder, type }
-- @param filepath string local path to save
-- @return boolean success
function Registry:download_image(image_info, filepath)
  if not self._url then
    error("cannot download without server URL (use connect())", 2)
  end
  if not image_info or not image_info.filename then
    error("download_image: image_info with filename is required", 2)
  end

  local params = string.format("filename=%s&subfolder=%s&type=%s",
    url_encode(image_info.filename),
    url_encode(image_info.subfolder or ""),
    url_encode(image_info.type or "output"))

  return transport.download(self._url .. "/view?" .. params, filepath, self._headers)
end

--- Full pipeline: compile → queue → poll → download → embed.
-- @param render_opts table same as vdsl.render()
-- @param run_opts table|nil { save, save_dir, timeout, interval, embed }
-- @return table { prompt_id, images, files, render }
function Registry:run(render_opts, run_opts)
  if not self._url then
    error("cannot run without server URL (use connect())", 2)
  end

  run_opts = run_opts or {}

  local compiler_mod = require("vdsl.compiler")
  local recipe_mod   = require("vdsl.recipe")
  local png_mod      = require("vdsl.png")
  local json_enc     = require("vdsl.json")

  -- 1. Compile
  local result = compiler_mod.compile(render_opts)

  -- 2. Queue
  local resp = self:queue(result)
  local prompt_id = resp.prompt_id
  if not prompt_id then
    error("queue failed: no prompt_id in response", 2)
  end

  -- 3. Poll
  local history = self:poll(prompt_id, {
    timeout  = run_opts.timeout or 300,
    interval = run_opts.interval or 1,
  })

  -- 4. Collect output images
  local images = {}
  if history.outputs then
    for _, output in pairs(history.outputs) do
      if output.images then
        for _, img in ipairs(output.images) do
          images[#images + 1] = img
        end
      end
    end
  end

  if #images == 0 then
    error("no images in output for prompt " .. prompt_id, 2)
  end

  -- 5. Download + 6. Embed
  local save_path = run_opts.save
  local save_dir  = run_opts.save_dir
  local do_embed  = run_opts.embed ~= false
  local saved_files = {}

  -- Pre-compute recipe/prompt JSON once (shared across all images)
  local recipe_json, prompt_json
  if do_embed then
    recipe_json = recipe_mod.serialize(render_opts)
    prompt_json = json_enc.encode(result.prompt)
  end

  if save_path then
    -- Single file: download first image
    self:download_image(images[1], save_path)
    saved_files[1] = save_path
    if do_embed then
      png_mod.inject_text(save_path, { vdsl = recipe_json, prompt = prompt_json })
    end
  elseif save_dir then
    -- Multiple files: download all images
    for i, img in ipairs(images) do
      local path = save_dir .. "/" .. safe_filename(img.filename)
      self:download_image(img, path)
      saved_files[i] = path
      if do_embed then
        png_mod.inject_text(path, { vdsl = recipe_json, prompt = prompt_json })
      end
    end
  end

  return {
    prompt_id = prompt_id,
    images    = images,
    files     = saved_files,
    render    = result,
  }
end

return Registry
