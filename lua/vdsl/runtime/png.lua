--- PNG: tEXt metadata abstraction layer.
-- Backend-agnostic like FS and Transport. Default: util/png.lua (Pure Lua).
-- Custom backends injected via set_backend() (e.g. mlua/Rust pngmeta).
--
-- Backend interface (table with functions):
--   read_text(path) -> table|nil, string|nil
--       Read all tEXt chunks. Returns { keyword = text, ... } or nil + error.
--   inject_text(path, chunks) -> boolean, string|nil
--       Write tEXt chunks (inserted before IEND, overwrites same key). In-place.
--   inject_text_to(src, dst, chunks) -> boolean, string|nil
--       Copy src → dst, then inject. Non-destructive.
--
-- Higher-level APIs (read_comfy) are implemented in this module directly,
-- delegating to read_text for the low-level work.

local M = {}

local _backend = nil

--- Set a custom PNG backend.
-- @param backend table or nil to reset to default
function M.set_backend(backend)
  if backend ~= nil and type(backend) ~= "table" then
    error("png.set_backend: backend must be a table", 2)
  end
  _backend = backend
end

-- ============================================================
-- Default backend (lazy-load util/png.lua)
-- ============================================================

local _default = nil

local function default()
  if not _default then
    _default = require("vdsl.util.png")
  end
  return _default
end

local function backend()
  return _backend or default()
end

-- ============================================================
-- Public API
-- ============================================================

--- Read all tEXt chunks from a PNG file.
-- @param filepath string
-- @return table|nil { keyword = text, ... }
-- @return string|nil error message
function M.read_text(filepath)
  return backend().read_text(filepath)
end

--- Inject tEXt chunks into an existing PNG (in-place).
-- @param filepath string
-- @param text_chunks table { keyword = text, ... }
-- @return boolean success
-- @return string|nil error message
function M.inject_text(filepath, text_chunks)
  return backend().inject_text(filepath, text_chunks)
end

--- Copy src PNG to dst, then inject tEXt chunks.
-- @param src_path string
-- @param dst_path string
-- @param text_chunks table { keyword = text, ... }
-- @return boolean success
-- @return string|nil error message
function M.inject_text_to(src_path, dst_path, text_chunks)
  return backend().inject_text_to(src_path, dst_path, text_chunks)
end

--- Extract and JSON-decode ComfyUI metadata from a PNG file.
-- @param filepath string
-- @param json_mod table|nil JSON module (default: vdsl.util.json)
-- @return table|nil { prompt, workflow }
-- @return string|nil error message
function M.read_comfy(filepath, json_mod)
  local chunks, err = M.read_text(filepath)
  if not chunks then
    return nil, err
  end

  json_mod = json_mod or require("vdsl.util.json")

  local result = {}
  if chunks["prompt"] then
    local ok, decoded = pcall(json_mod.decode, chunks["prompt"])
    if ok then result.prompt = decoded end
  end
  if chunks["workflow"] then
    local ok, decoded = pcall(json_mod.decode, chunks["workflow"])
    if ok then result.workflow = decoded end
  end
  return result
end

-- ============================================================
-- CRC32 / internal helpers (exposed for testing, delegated)
-- ============================================================

--- Expose CRC32 from default backend for testing.
-- @return function crc32(data) -> integer
function M._crc32(...)
  return default()._crc32(...)
end

return M
