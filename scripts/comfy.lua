--- comfy.lua: Shared helper for examples that connect to ComfyUI.
--
-- Handles .env loading, workspace directory creation, post-processing
-- presets, LoRA discovery, and error reporting.
-- All examples that call the ComfyUI API should use this helper.
--
-- .env keys:
--   token   ComfyUI auth token (required)
--   url     ComfyUI URL (required)
--
-- Usage:
--   local comfy = require("comfy")
--
-- Discovery:
--   comfy.checkpoints()              → list available checkpoints
--   comfy.loras()                    → list available LoRAs
--   comfy.controlnets()              → list available ControlNets
--   comfy.vaes() / comfy.upscalers() → list VAEs / Upscalers
--   comfy.lora(query)                → fuzzy-match → { name, weight }
--   comfy.controlnet(query, image)   → Stage-ready entry
--   comfy.info()                     → print all categories to stdout
--   comfy.info("loras")              → print single category only

local vdsl = require("vdsl")

local M = {}

local shell_quote = require("vdsl.util.shell").quote

-- ============================================================
-- Environment
-- ============================================================

--- Load key=value file (trim, skip comments/empty lines).
-- @param path string file path
-- @param required boolean if true, error when file not found
-- @return table key-value pairs
local function load_kv(path, required)
  local f = io.open(path)
  if not f then
    if required then error("No " .. path .. " found", 2) end
    return {}
  end
  local kv = {}
  for line in f:lines() do
    line = line:match("^%s*(.-)%s*$")
    if line ~= "" and not line:match("^#") then
      local k, v = line:match("^([%w_]+)=(.+)$")
      if k then kv[k] = v end
    end
  end
  f:close()
  return kv
end

--- Cached .env values. Available immediately after dofile().
M.env = load_kv(".env", true)
if not M.env.token then error(".env: token= is required") end

--- Create a save directory under workspace/ and return its path.
-- @param name string subdirectory name (optional: derived from script filename)
-- @return string path
function M.save_dir(name)
  if not name then
    local script = arg and arg[0]
    if not script then
      error("save_dir(): no name given and arg[0] not available", 2)
    end
    name = script:match("([^/\\]+)$"):gsub("%.lua$", "")
  end
  local dir = "workspace/" .. name
  os.execute("mkdir -p " .. shell_quote(dir))
  return dir
end

-- ============================================================
-- Post-processing presets
-- ============================================================

--- Ready-made post pipelines for common use cases.
-- Combine with + operator: comfy.post.face + comfy.post.upscale
M.post = {
  -- Face detail only (denoise=0.4, conservative)
  face = vdsl.post("facedetail", { detector = "face", denoise = 0.4 }),

  -- Face detail (stronger, for wide shots with small faces)
  face_strong = vdsl.post("facedetail", {
    detector = "face", denoise = 0.6, bbox_threshold = 0.3, drop_size = 5,
  }),

  -- Hand detail only
  hand = vdsl.post("facedetail", { detector = "hand", denoise = 0.4 }),

  -- Face + hand chain
  face_hand = vdsl.post("facedetail", { detector = "face", denoise = 0.4 })
            + vdsl.post("facedetail", { detector = "hand", denoise = 0.4 }),

  -- Face HD (higher guide resolution + tighter crop for eye detail)
  face_hd = vdsl.post("facedetail", {
    detector = "face", denoise = 0.4, guide = 768, bbox_crop_factor = 2.5,
  }),

  -- Face detail + 4x upscale
  face_upscale = vdsl.post("facedetail", { detector = "face", denoise = 0.4 })
               + vdsl.post("upscale"),

  -- Person detail (full body, clothing, armor — segm model)
  person = vdsl.post("facedetail", { detector = "person", denoise = 0.35 }),

  -- Person + face chain (broad body → targeted face)
  face_person = vdsl.post("facedetail", { detector = "person", denoise = 0.35 })
              + vdsl.post("facedetail", { detector = "face", denoise = 0.4 }),

  -- Full chain: person → hand → face (broadest → most targeted)
  full = vdsl.post("facedetail", { detector = "person", denoise = 0.35 })
       + vdsl.post("facedetail", { detector = "hand", denoise = 0.4 })
       + vdsl.post("facedetail", { detector = "face", denoise = 0.4 }),
}

-- ============================================================
-- Registry (cached connection to ComfyUI server)
-- ============================================================

local _registry = nil

--- Resolve the ComfyUI URL.
-- @return string url
local function resolve_url()
  return M.env.url
end

--- Get or create the cached Registry.
-- Connects once on first call, reuses for all subsequent operations.
-- Uses runtime url (from setup) or .env url (direct connection).
-- @return Registry
local function get_registry()
  if not _registry then
    local url = resolve_url()
    if not url then
      error("No ComfyUI URL available. Set url= in .env", 2)
    end
    _registry = vdsl.connect(url, { token = M.env.token })
  end
  return _registry
end

-- ============================================================
-- Model / LoRA discovery
-- ============================================================

--- List available checkpoint files on the ComfyUI server.
-- @return table array of checkpoint filenames
function M.checkpoints()
  return get_registry().checkpoints
end

--- List available VAE files on the ComfyUI server.
-- @return table array of VAE filenames
function M.vaes()
  return get_registry().vaes
end

--- List available upscaler models on the ComfyUI server.
-- @return table array of upscaler filenames
function M.upscalers()
  return get_registry().upscalers
end

--- List available LoRA files on the ComfyUI server.
-- @return table array of LoRA filenames
function M.loras()
  return get_registry().loras
end

--- Fuzzy-match a LoRA name against the server inventory.
-- @param query string partial name to match
-- @param weight number|Weight|nil weight (default 1.0)
-- @return table { name, weight } compatible with vdsl.cast({ lora = {...} })
function M.lora(query, weight)
  return get_registry():lora(query, weight)
end

-- ============================================================
-- ControlNet discovery
-- ============================================================

--- List available ControlNet models on the ComfyUI server.
-- @return table array of ControlNet filenames
function M.controlnets()
  return get_registry().controlnets
end

--- Build a Stage-ready ControlNet entry with fuzzy-match and auto-upload.
-- @param query string partial model name to match (e.g. "canny", "union")
-- @param image string local filepath or server-side filename
-- @param opts table|nil { strength, preprocessor, start_percent, end_percent }
-- @return table Stage.controlnet entry
function M.controlnet(query, image, opts)
  opts = opts or {}
  local reg = get_registry()
  local model_name = reg:controlnet(query)
  local server_image = reg:resolve_image(image)
  return {
    type          = model_name,
    image         = server_image,
    strength      = opts.strength or 1.0,
    preprocessor  = opts.preprocessor,
    start_percent = opts.start_percent,
    end_percent   = opts.end_percent,
  }
end

-- ============================================================
-- Info (server resource listing)
-- ============================================================

local INFO_CATEGORIES = {
  { key = "checkpoints",  fn = function() return M.checkpoints() end },
  { key = "loras",        fn = function() return M.loras() end },
  { key = "controlnets",  fn = function() return M.controlnets() end },
  { key = "vaes",         fn = function() return M.vaes() end },
  { key = "upscalers",    fn = function() return M.upscalers() end },
}

--- Print server resources to stdout.
-- @param filter string|nil category name (nil = all categories)
function M.info(filter)
  local function print_list(label, items)
    table.sort(items)
    print(string.format("\n=== %s (%d) ===", label, #items))
    for i, name in ipairs(items) do
      print(string.format("  %3d. %s", i, name))
    end
  end

  if filter then
    for _, cat in ipairs(INFO_CATEGORIES) do
      if cat.key == filter then
        print_list(cat.key, cat.fn())
        return
      end
    end
    error("Unknown category: " .. filter .. ". Available: checkpoints, loras, controlnets, vaes, upscalers", 2)
  else
    for _, cat in ipairs(INFO_CATEGORIES) do
      print_list(cat.key, cat.fn())
    end
  end
end

return M
