--- Emit: workflow output abstraction layer.
-- Backend-agnostic like FS/Transport. Default: write to VDSL_OUT_DIR.
-- Custom backends injected via set_backend() (e.g. mlua/Rust, runner).
--
-- Backend interface (table with functions):
--   write(name, json_str) -> boolean       write workflow JSON
--   write_recipe(name, recipe_json)        write recipe sidecar (optional)
--
-- When no backend is set, the default backend writes to VDSL_OUT_DIR.
-- When VDSL_OUT_DIR is not set, emit is a silent no-op (standalone mode).

local M = {}

local _backend = nil

--- Set a custom emit backend.
-- @param backend table or nil to reset to default
function M.set_backend(backend)
  if backend ~= nil and type(backend) ~= "table" then
    error("emit.set_backend: backend must be a table", 2)
  end
  _backend = backend
end

-- ============================================================
-- Default backend (VDSL_OUT_DIR file write)
-- ============================================================

local default = {}

local function get_fs()
  return require("vdsl.runtime.fs")
end

function default.write(name, json_str)
  local out_dir = os.getenv("VDSL_OUT_DIR")
  if not out_dir then return false end
  local path = out_dir .. "/" .. name .. ".json"
  local ok, err = pcall(get_fs().write, path, json_str)
  if not ok then
    io.stderr:write(string.format("emit.write: cannot write '%s': %s\n", path, tostring(err)))
    return false
  end
  return true
end

function default.write_recipe(name, recipe_json)
  local out_dir = os.getenv("VDSL_OUT_DIR")
  if not out_dir then return end
  local rpath = out_dir .. "/_recipe_" .. name .. ".json"
  pcall(get_fs().write, rpath, recipe_json)
end

-- ============================================================
-- Public API (dispatch to active backend)
-- ============================================================

local function backend()
  return _backend or default
end

--- Write a compiled workflow.
-- @param name string  output name stem (e.g. "01_gothic_lolita")
-- @param json_str string  compiled workflow JSON
-- @return boolean  true if written
function M.write(name, json_str)
  return backend().write(name, json_str)
end

--- Write a recipe sidecar.
-- @param name string  output name stem (matches the workflow name)
-- @param recipe_json string  serialized recipe JSON
function M.write_recipe(name, recipe_json)
  local b = backend()
  if b.write_recipe then
    b.write_recipe(name, recipe_json)
  end
end

return M
