--- Preflight CLI: check model availability before generation.
-- Called by MCP (vdsl_run_script) or standalone.
-- Thin CLI entrypoint — orchestration logic lives in vdsl.compilers.comfyui.preflight.
--
-- Inputs:
--   arg[1]          = VDSL script file path to check
--   VDSL_AVAILABLE  = JSON string of available models (env var, set by MCP)
--                     Format: { "checkpoints": [...], "loras": [...], ... }
--
-- Output (stdout): JSON report
--   { "ok": bool, "missing": [...], "required": {...}, "summary": "..." }
--
-- Usage:
--   # Via MCP (vdsl_run_script with env var)
--   VDSL_AVAILABLE='{"checkpoints":["model.safetensors"],...}' lua scripts/preflight.lua script.lua
--
--   # Standalone (extract only, no server check)
--   lua scripts/preflight.lua script.lua

local json      = require("vdsl.util.json")
local preflight = require("vdsl.compilers.comfyui.preflight")

-- ============================================================
-- Argument parsing
-- ============================================================

local script_file = arg[1]
if not script_file then
  io.stderr:write("Usage: lua scripts/preflight.lua <script.lua>\n")
  os.exit(1)
end

-- ============================================================
-- Load and execute the target script to capture render calls
-- ============================================================

local loader, err = loadfile(script_file)
if not loader then
  io.stderr:write(string.format("preflight: cannot load '%s': %s\n", script_file, err))
  os.exit(1)
end

-- Capture vdsl.render calls by monkey-patching
local vdsl = require("vdsl")
local captured_prompts = {}
local original_render = vdsl.render

vdsl.render = function(opts)
  local result = original_render(opts)
  captured_prompts[#captured_prompts + 1] = result.prompt
  return result
end

-- Suppress emit (no output dir needed for preflight)
local emit_mod = require("vdsl.runtime.emit")
emit_mod.set_backend({
  write = function() return false end,
})

-- Execute the script
local ok, exec_err = pcall(loader)

-- Restore
vdsl.render = original_render
emit_mod.set_backend(nil)

if not ok then
  io.stderr:write(string.format("preflight: script error: %s\n", tostring(exec_err)))
  os.exit(1)
end

if #captured_prompts == 0 then
  io.stderr:write("preflight: script did not call vdsl.render()\n")
  os.exit(1)
end

-- ============================================================
-- Extract + check via Application Layer API
-- ============================================================

local merged_required = preflight.extract_all(captured_prompts)

local comfy_url   = os.getenv("VDSL_COMFY_URL")
local comfy_token = os.getenv("VDSL_COMFY_TOKEN")
local available_json = os.getenv("VDSL_AVAILABLE")
local report

if comfy_url then
  -- Connect to ComfyUI and build available catalog
  local Registry = require("vdsl.runtime.registry")
  local opts = {}
  if comfy_token then opts.token = comfy_token end
  local conn_ok, reg = pcall(Registry.connect, comfy_url, opts)
  if not conn_ok then
    io.stderr:write(string.format("preflight: Registry.connect failed: %s\n", tostring(reg)))
    os.exit(1)
  end
  local available = {
    checkpoints = reg.checkpoints or {},
    loras       = reg.loras or {},
    vaes        = reg.vaes or {},
    controlnets = reg.controlnets or {},
    upscalers   = reg.upscalers or {},
  }
  -- node_types from object_info top-level keys
  if reg._object_info then
    local node_types = {}
    for k in pairs(reg._object_info) do
      node_types[#node_types + 1] = k
    end
    available.node_types = node_types
  end
  report = preflight.check(merged_required, available)
elseif available_json then
  -- Legacy: VDSL_AVAILABLE JSON (pre-parsed catalog)
  local parse_ok, available = pcall(json.decode, available_json)
  if not parse_ok then
    io.stderr:write("preflight: failed to parse VDSL_AVAILABLE JSON\n")
    os.exit(1)
  end
  report = preflight.check(merged_required, available)
else
  -- No server info — just output required models
  report = {
    ok       = true,
    missing  = {},
    summary  = "No server connection — showing required models only.\n"
               .. preflight.format_required(merged_required),
  }
end

-- ============================================================
-- Output JSON report
-- ============================================================

local output = {
  ok            = report.ok,
  missing       = report.missing,
  missing_nodes = report.missing_nodes,
  required      = preflight.to_arrays(merged_required),
  summary       = report.summary,
}

io.write(json.encode(output, true) .. "\n")

if not report.ok then
  os.exit(2)  -- Non-zero exit for missing models
end
