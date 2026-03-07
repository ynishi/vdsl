--- runner.lua: Local runner for vdsl scripts (MCP vdsl_run equivalent).
--
-- Executes a vdsl script that uses vdsl.render() + vdsl.emit(),
-- collects the emitted JSON workflows, and sends them to ComfyUI.
--
-- Usage:
--   lua -e "package.path='lua/?.lua;lua/?/init.lua;scripts/?.lua;'..package.path" scripts/runner.lua examples/foo.lua
--
-- Requires .env with:
--   url=https://...    ComfyUI endpoint
--   token=...          Auth token

local json = require("vdsl.util.json")
local vdsl = require("vdsl")
local id_mod = require("vdsl.util.id")
local fs     = require("vdsl.runtime.fs")

local shell_quote = require("vdsl.util.shell").quote

-- ============================================================
-- .env loader (same logic as comfy.lua, independent copy)
-- ============================================================

local function load_kv(path)
  local content = fs.read(path)
  if not content then return {} end
  local kv = {}
  for line in content:gmatch("[^\n]+") do
    line = line:match("^%s*(.-)%s*$")
    if line ~= "" and not line:match("^#") then
      local k, v = line:match("^([%w_]+)=(.+)$")
      if k then kv[k] = v end
    end
  end
  return kv
end

-- ============================================================
-- Temp directory
-- ============================================================

local function make_tmpdir()
  local handle = io.popen("mktemp -d 2>/dev/null || mktemp -d -t vdsl")
  if not handle then error("runner: cannot create tmpdir") end
  local dir = handle:read("*l")
  handle:close()
  if not dir or dir == "" then error("runner: mktemp returned empty") end
  return dir
end

-- ============================================================
-- Collect JSON files from directory
-- ============================================================

local function collect_jsons(dir)
  local entries = fs.ls(dir)
  local files = {}
  for _, name in ipairs(entries) do
    if name:match("%.json$") then
      files[#files + 1] = dir .. "/" .. name
    end
  end
  table.sort(files)
  return files
end

-- ============================================================
-- Main
-- ============================================================

local script = arg[1]
if not script then
  io.stderr:write("Usage: lua scripts/runner.lua <script.lua>\n")
  os.exit(1)
end

-- Verify script exists
if not fs.exists(script) then
  io.stderr:write("runner: file not found: " .. script .. "\n")
  os.exit(1)
end

-- Load env
local env = load_kv(".env")
local runtime = load_kv(".env.runtime")

local url = runtime.url or env.url
local token = env.token

if not url then
  io.stderr:write("runner: no ComfyUI URL. Set url= in .env or run comfy.setup() first.\n")
  os.exit(1)
end
if not token then
  io.stderr:write("runner: no token. Set token= in .env.\n")
  os.exit(1)
end

-- Prepare output directory
local tmpdir = make_tmpdir()

-- Repository: workspace + run setup
local script_name = script:match("([^/\\]+)$"):gsub("%.lua$", "")
-- Derive workspace name from script prefix (e.g. "gravure_klimt_p1" → "gravure_klimt")
local ws_name = script_name:match("^([^_]+_[^_]+)") or script_name
local ws = vdsl.repo:ensure_workspace(ws_name)
local run = vdsl.repo:create_run(ws.id, script_name .. ".lua")

-- Inject runner emit backend via DI.
-- Captures workflow JSON to tmpdir + render opts metadata for post-processing.
local emit_mod = require("vdsl.runtime.emit")
local _emitted_meta = {}  -- { [name] = { save_dir, output, render_opts, recipe } }

-- Capture render opts per emit call.
local original_render = vdsl.render
local _last_render_opts = nil
vdsl.render = function(opts)
  _last_render_opts = opts
  return original_render(opts)
end

emit_mod.set_backend({
  write = function(name, json_str)
    local path = tmpdir .. "/" .. name .. ".json"
    local write_ok, write_err = pcall(fs.write, path, json_str)
    if not write_ok then
      io.stderr:write(string.format("runner.emit: cannot write '%s': %s\n", path, tostring(write_err)))
      return false
    end

    -- Capture metadata from the render opts that produced this result
    local meta = {
      save_dir = _last_render_opts and _last_render_opts.save_dir,
      output   = _last_render_opts and _last_render_opts.output,
      render_opts = _last_render_opts,
    }
    if _last_render_opts then
      local ser_ok, recipe = pcall(require("vdsl.runtime.serializer").serialize, _last_render_opts)
      if ser_ok then meta.recipe = recipe end
    end
    _emitted_meta[name] = meta

    return true
  end,

  write_recipe = function(name, recipe_json)
    local path = tmpdir .. "/_recipe_" .. name .. ".json"
    pcall(fs.write, path, recipe_json)
  end,
})

-- Execute script
io.write(string.format("runner: executing %s\n", script))
local ok, err = pcall(dofile, script)
if not ok then
  io.stderr:write("runner: script error: " .. tostring(err) .. "\n")
  os.execute("rm -r " .. shell_quote(tmpdir))
  os.exit(1)
end

-- Restore defaults
emit_mod.set_backend(nil)
vdsl.render = original_render

-- Collect emitted workflows
local workflow_files = collect_jsons(tmpdir)
if #workflow_files == 0 then
  io.stderr:write("runner: no workflows emitted. Does the script call vdsl.emit()?\n")
  os.execute("rm -r " .. shell_quote(tmpdir))
  os.exit(1)
end

io.write(string.format("runner: %d workflow(s) to queue\n", #workflow_files))

-- Connect to ComfyUI via Registry
local registry = vdsl.connect(url, { token = token })

-- Fallback save directory (when render opts have no save_dir)
local fallback_save_dir = "workspace/" .. script_name

-- Queue each workflow, poll, download
local success_count = 0

for i, wf_path in ipairs(workflow_files) do
  local wf_json = fs.read(wf_path)
  if not wf_json then
    io.stderr:write(string.format("runner: cannot read %s\n", wf_path))
    goto continue
  end

  local prompt = json.decode(wf_json)
  local wf_name = wf_path:match("([^/]+)%.json$") or ("workflow_" .. i)

  -- Queue via Registry
  io.write(string.format("  [%d/%d] %s — queueing...", i, #workflow_files, wf_name))
  local queue_ok, resp = pcall(registry.queue, registry, { prompt = prompt })
  if not queue_ok then
    io.write(" FAILED\n")
    io.stderr:write("    " .. tostring(resp) .. "\n")
    goto continue
  end

  local prompt_id = resp.prompt_id
  if not prompt_id then
    io.write(" FAILED (no prompt_id)\n")
    goto continue
  end
  io.write(string.format(" queued (%s)\n", prompt_id:sub(1, 8)))

  -- Poll via Registry
  local poll_ok, history_entry = pcall(registry.poll, registry, prompt_id, { timeout = 300 })
  if not poll_ok then
    io.stderr:write(string.format("    %s\n", tostring(history_entry)))
    goto continue
  end

  -- Collect output images
  local images = {}
  if history_entry.outputs then
    for _, output in pairs(history_entry.outputs) do
      if output.images then
        for _, img in ipairs(output.images) do
          images[#images + 1] = img
        end
      end
    end
  end

  -- Resolve save path from render opts metadata
  local meta = _emitted_meta[wf_name] or {}
  local dl_dir = meta.save_dir or fallback_save_dir
  fs.mkdir(dl_dir)

  -- Extract model for DB record
  local model_name = nil
  if meta.render_opts and meta.render_opts.world then
    model_name = meta.render_opts.world.model
  end

  -- Download via Registry
  for j, img in ipairs(images) do
    -- Resolve save path
    local save_path
    if meta.output then
      if #images == 1 then
        save_path = meta.output .. ".png"
      else
        save_path = meta.output .. "_" .. j .. ".png"
      end
      local parent = save_path:match("^(.+)/[^/]+$")
      if parent then fs.mkdir(parent) end
    else
      save_path = dl_dir .. "/" .. img.filename
    end

    local dl_ok, dl_err = pcall(registry.download_image, registry, img, save_path)
    if dl_ok then
      io.write(string.format("    saved: %s\n", save_path))

      -- Persist to repository
      local gen_id = id_mod.uuid()
      local seed_val = meta.render_opts and meta.render_opts.seed or nil
      local save_ok, save_err = pcall(function()
        vdsl.repo:save({
          id      = gen_id,
          run_id  = run.id,
          seed    = seed_val,
          model   = model_name,
          output  = save_path,
          recipe  = meta.recipe,
        })
      end)
      if save_ok then
        io.write(string.format("    db: %s\n", gen_id:sub(1, 8)))
      else
        io.stderr:write(string.format("    db save failed: %s\n", tostring(save_err)))
      end
    else
      io.stderr:write(string.format("    download failed: %s\n", tostring(dl_err)))
    end
  end

  success_count = success_count + 1
  ::continue::
end

-- ============================================================
-- Post-download: Dataset organization
-- ============================================================
-- If the script emitted dataset manifests via training.dataset:emit(),
-- apply them now that PNGs are downloaded.

local ds_ok, ds_mod = pcall(require, "vdsl.training.dataset")
if ds_ok then
  local emitted = ds_mod.get_emitted()
  if #emitted > 0 then
    io.write(string.format("\nrunner: %d dataset manifest(s) to apply\n", #emitted))
    for _, manifest in ipairs(emitted) do
      local apply_ok, apply_err = pcall(ds_mod.apply, manifest)
      if not apply_ok then
        io.stderr:write(string.format("  dataset apply failed: %s\n", tostring(apply_err)))
      end
    end
    ds_mod.clear_emitted()
  end
end

-- Cleanup
os.execute("rm -r " .. shell_quote(tmpdir))

io.write(string.format("\nrunner: %d/%d completed. workspace=%s run=%s\n",
  success_count, #workflow_files, ws_name, run.id:sub(1, 8)))
