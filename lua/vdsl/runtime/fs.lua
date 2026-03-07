--- FS: filesystem abstraction layer.
-- Backend-agnostic like Transport. Default: os.execute/io.open.
-- Custom backends injected via set_backend() (e.g. mlua/Rust, mock).
--
-- Backend interface (table with functions):
--   mkdir(path)                         create directory (recursive)
--   cp(src, dst)                        copy file
--   read(path) -> string|nil            read file content (nil if missing)
--   write(path, content)                write file
--   exists(path) -> boolean             file/dir exists
--   ls(dir) -> string[]                 list directory entries
--   find(dir, pattern) -> string[]      recursive file search (glob pattern)
--   sleep(seconds)                      sleep

local shell = require("vdsl.util.shell")
local shell_quote = shell.quote

local M = {}

local _backend = nil

--- Set a custom FS backend.
-- @param backend table or nil to reset to default
function M.set_backend(backend)
  if backend ~= nil and type(backend) ~= "table" then
    error("fs.set_backend: backend must be a table", 2)
  end
  _backend = backend
end

-- ============================================================
-- Default backend (os.execute / io.open)
-- ============================================================

local default = {}

function default.mkdir(path)
  os.execute("mkdir -p " .. shell_quote(path))
end

function default.cp(src, dst)
  os.execute("cp " .. shell_quote(src) .. " " .. shell_quote(dst))
end

function default.read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content
end

function default.read_binary(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content
end

function default.write(path, content)
  local f, err = io.open(path, "w")
  if not f then
    error("fs.write: cannot open '" .. path .. "': " .. (err or "unknown"), 3)
  end
  f:write(content)
  f:close()
end

function default.write_binary(path, content)
  local f, err = io.open(path, "wb")
  if not f then
    error("fs.write_binary: cannot open '" .. path .. "': " .. (err or "unknown"), 3)
  end
  f:write(content)
  f:close()
end

function default.exists(path)
  local f = io.open(path, "r")
  if f then
    f:close()
    return true
  end
  return false
end

function default.ls(dir)
  local handle = io.popen("ls -1 " .. shell_quote(dir) .. " 2>/dev/null")
  if not handle then return {} end
  local entries = {}
  for line in handle:lines() do
    entries[#entries + 1] = line
  end
  handle:close()
  return entries
end

function default.find(dir, pattern)
  local handle = io.popen("find " .. shell_quote(dir) .. " -name " .. shell_quote(pattern) .. " -type f 2>/dev/null")
  if not handle then return {} end
  local files = {}
  for line in handle:lines() do
    files[#files + 1] = line
  end
  handle:close()
  return files
end

function default.sleep(seconds)
  local ok, socket = pcall(require, "socket")
  if ok and socket and socket.sleep then
    socket.sleep(seconds)
    return
  end
  os.execute("sleep " .. string.format("%.3f", seconds))
end

-- ============================================================
-- Public API (dispatch to active backend)
-- ============================================================

local function backend()
  return _backend or default
end

function M.mkdir(path)
  return backend().mkdir(path)
end

function M.cp(src, dst)
  return backend().cp(src, dst)
end

function M.read(path)
  return backend().read(path)
end

function M.read_binary(path)
  local b = backend()
  if b.read_binary then return b.read_binary(path) end
  return b.read(path)
end

function M.write(path, content)
  return backend().write(path, content)
end

function M.write_binary(path, content)
  local b = backend()
  if b.write_binary then return b.write_binary(path, content) end
  return b.write(path, content)
end

function M.exists(path)
  return backend().exists(path)
end

function M.ls(dir)
  return backend().ls(dir)
end

function M.find(dir, pattern)
  return backend().find(dir, pattern)
end

function M.sleep(seconds)
  return backend().sleep(seconds)
end

return M
