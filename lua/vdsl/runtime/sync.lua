--- Runtime Sync: file transfer and identity backend.
-- Backend-agnostic like FS, Transport, DB. Default: shell (scp/rclone/ssh).
-- Custom backends injected via set_backend() (e.g. mlua/Rust).
--
-- Locations:
--   local  — Local filesystem (macOS dev machine)
--   pod    — RunPod pod (ComfyUI server)
--   cloud  — Cloud storage (Backblaze B2 via rclone)
--
-- Backend interface (table with functions):
--   push(src_path, dest_loc, dest_path, opts) -> boolean, string|nil
--   pull(src_loc, src_path, dest_path, opts)  -> boolean, string|nil
--   list(loc, path, opts) -> { { path, size }, ... }
--   exists(loc, path, opts) -> boolean
--   hash(filepath) -> string|nil  (content identity hash for local files)
--
-- opts:
--   pod_id   — RunPod pod ID (for pod operations)
--   ssh_key  — SSH key path
--   bucket   — B2 bucket name (for cloud operations)

local fs = require("vdsl.runtime.fs")

local M = {}

local _backend = nil

--- Set a custom sync backend.
-- @param backend table or nil to reset to default
function M.set_backend(backend)
  if backend ~= nil and type(backend) ~= "table" then
    error("sync.set_backend: backend must be a table", 2)
  end
  _backend = backend
end

-- ============================================================
-- Default backend (shell: scp/rclone/ssh)
-- ============================================================

local shell_quote = require("vdsl.util.shell").quote

local default = {}

--- Push a file from local to a remote location.
-- @param src_path string  local file path
-- @param dest_loc string  "pod" or "cloud"
-- @param dest_path string  destination path
-- @param opts table  { pod_id, ssh_key, bucket }
-- @return boolean success, string|nil error
function default.push(src_path, dest_loc, dest_path, opts)
  opts = opts or {}
  if dest_loc == "pod" then
    return default._push_pod(src_path, dest_path, opts)
  elseif dest_loc == "cloud" then
    return default._push_cloud(src_path, dest_path, opts)
  end
  return false, "unknown destination: " .. tostring(dest_loc)
end

--- Pull a file from a remote location to local.
-- @param src_loc string  "pod" or "cloud"
-- @param src_path string  source path on remote
-- @param dest_path string  local destination path
-- @param opts table  { pod_id, ssh_key, bucket }
-- @return boolean success, string|nil error
function default.pull(src_loc, src_path, dest_path, opts)
  opts = opts or {}
  if src_loc == "pod" then
    return default._pull_pod(src_path, dest_path, opts)
  elseif src_loc == "cloud" then
    return default._pull_cloud(src_path, dest_path, opts)
  end
  return false, "unknown source: " .. tostring(src_loc)
end

--- List files at a location.
-- @param loc string  "local", "pod", or "cloud"
-- @param path string  directory path
-- @param opts table
-- @return table  array of { path, size }
function default.list(loc, path, opts)
  opts = opts or {}
  if loc == "local" then
    return default._list_local(path)
  elseif loc == "pod" then
    return default._list_pod(path, opts)
  elseif loc == "cloud" then
    return default._list_cloud(path, opts)
  end
  return {}
end

--- Check if a file exists at a location.
-- @param loc string
-- @param path string
-- @param opts table
-- @return boolean
function default.exists(loc, path, opts)
  opts = opts or {}
  if loc == "local" then
    return fs.exists(path)
  elseif loc == "pod" then
    return default._exists_pod(path, opts)
  elseif loc == "cloud" then
    return default._exists_cloud(path, opts)
  end
  return false
end

--- Compute content identity hash for a local file.
-- Default: delegates to runtime/png.image_hash (DJB2 of IHDR+IDAT).
-- Rust backend can replace this via runtime/png.set_backend().
-- @param filepath string  path to local PNG file
-- @return string|nil  hex hash, nil on error
function default.hash(filepath)
  local png = require("vdsl.runtime.png")
  return png.image_hash(filepath)
end

-- ---- Pod operations (scp/ssh) ----

function default._push_pod(src, dest, opts)
  local ssh_key = opts.ssh_key or "~/.ssh/id_ed25519_runpod"
  local pod_id = opts.pod_id
  if not pod_id then return false, "pod_id required" end
  local cmd = string.format(
    "scp -i %s -o StrictHostKeyChecking=no %s root@%s:%s 2>&1",
    shell_quote(ssh_key), shell_quote(src), shell_quote(pod_id), shell_quote(dest))
  local handle = io.popen(cmd)
  if not handle then return false, "failed to exec scp" end
  local output = handle:read("*a")
  local ok = handle:close()
  if not ok then return false, output end
  return true
end

function default._pull_pod(src, dest, opts)
  local ssh_key = opts.ssh_key or "~/.ssh/id_ed25519_runpod"
  local pod_id = opts.pod_id
  if not pod_id then return false, "pod_id required" end
  local dir = dest:match("(.+)/[^/]+$")
  if dir then fs.mkdir(dir) end
  local cmd = string.format(
    "scp -i %s -o StrictHostKeyChecking=no root@%s:%s %s 2>&1",
    shell_quote(ssh_key), shell_quote(pod_id), shell_quote(src), shell_quote(dest))
  local handle = io.popen(cmd)
  if not handle then return false, "failed to exec scp" end
  local output = handle:read("*a")
  local ok = handle:close()
  if not ok then return false, output end
  return true
end

function default._list_pod(path, opts)
  local ssh_key = opts.ssh_key or "~/.ssh/id_ed25519_runpod"
  local pod_id = opts.pod_id
  if not pod_id then return {} end
  local cmd = string.format(
    "ssh -i %s -o StrictHostKeyChecking=no root@%s 'find %s -type f -printf \"%%p\\t%%s\\n\"' 2>/dev/null",
    shell_quote(ssh_key), shell_quote(pod_id), shell_quote(path))
  local handle = io.popen(cmd)
  if not handle then return {} end
  local entries = {}
  for line in handle:lines() do
    local p, s = line:match("^(.+)\t(%d+)$")
    if p then entries[#entries + 1] = { path = p, size = tonumber(s) } end
  end
  handle:close()
  return entries
end

function default._exists_pod(path, opts)
  local ssh_key = opts.ssh_key or "~/.ssh/id_ed25519_runpod"
  local pod_id = opts.pod_id
  if not pod_id then return false end
  local cmd = string.format(
    "ssh -i %s -o StrictHostKeyChecking=no root@%s 'test -f %s && echo YES' 2>/dev/null",
    shell_quote(ssh_key), shell_quote(pod_id), shell_quote(path))
  local handle = io.popen(cmd)
  if not handle then return false end
  local result = handle:read("*a")
  handle:close()
  return result:match("YES") ~= nil
end

-- ---- Cloud operations (rclone/B2) ----

local function rclone_remote(opts)
  return "b2:" .. (opts.bucket or os.getenv("VDSL_B2_BUCKET") or "vdsl-storage")
end

function default._push_cloud(src, dest, opts)
  local remote = rclone_remote(opts)
  local cmd = string.format(
    "rclone copyto %s %s/%s 2>&1",
    shell_quote(src), remote, shell_quote(dest))
  local handle = io.popen(cmd)
  if not handle then return false, "failed to exec rclone" end
  local output = handle:read("*a")
  local ok = handle:close()
  if not ok then return false, output end
  return true
end

function default._pull_cloud(src, dest, opts)
  local remote = rclone_remote(opts)
  local dir = dest:match("(.+)/[^/]+$")
  if dir then fs.mkdir(dir) end
  local cmd = string.format(
    "rclone copyto %s/%s %s 2>&1",
    remote, shell_quote(src), shell_quote(dest))
  local handle = io.popen(cmd)
  if not handle then return false, "failed to exec rclone" end
  local output = handle:read("*a")
  local ok = handle:close()
  if not ok then return false, output end
  return true
end

function default._list_cloud(path, opts)
  local remote = rclone_remote(opts)
  local target = remote .. "/" .. (path or "")
  local cmd = string.format("rclone lsf --format 'ps' %s 2>/dev/null", shell_quote(target))
  local handle = io.popen(cmd)
  if not handle then return {} end
  local entries = {}
  for line in handle:lines() do
    local p, s = line:match("^(.+);(%d+)$")
    if p then entries[#entries + 1] = { path = p, size = tonumber(s) } end
  end
  handle:close()
  return entries
end

function default._exists_cloud(path, opts)
  local remote = rclone_remote(opts)
  local cmd = string.format(
    "rclone lsf %s/%s 2>/dev/null | head -1",
    remote, shell_quote(path))
  local handle = io.popen(cmd)
  if not handle then return false end
  local result = handle:read("*a")
  handle:close()
  return result ~= nil and result ~= ""
end

-- ---- Local operations ----

function default._list_local(path)
  local files = fs.find(path, "*")
  local entries = {}
  for _, fpath in ipairs(files) do
    local size = fs.file_size(fpath)
    if size then
      entries[#entries + 1] = { path = fpath, size = size }
    end
  end
  return entries
end

-- ============================================================
-- Backend dispatch
-- ============================================================

local function backend()
  return _backend or default
end

-- ============================================================
-- Public API (dispatch to active backend)
-- ============================================================

--- Push a file from local to a remote location.
-- @param src_path string  local file path
-- @param dest_loc string  "pod" or "cloud"
-- @param dest_path string  destination path
-- @param opts table  { pod_id, ssh_key, bucket }
-- @return boolean success, string|nil error
function M.push(src_path, dest_loc, dest_path, opts)
  return backend().push(src_path, dest_loc, dest_path, opts)
end

--- Pull a file from a remote location to local.
-- @param src_loc string  "pod" or "cloud"
-- @param src_path string  source path on remote
-- @param dest_path string  local destination path
-- @param opts table  { pod_id, ssh_key, bucket }
-- @return boolean success, string|nil error
function M.pull(src_loc, src_path, dest_path, opts)
  return backend().pull(src_loc, src_path, dest_path, opts)
end

--- List files at a location.
-- @param loc string  "local", "pod", or "cloud"
-- @param path string  directory path
-- @param opts table
-- @return table  array of { path, size }
function M.list(loc, path, opts)
  return backend().list(loc, path, opts)
end

--- Check if a file exists at a location.
-- @param loc string
-- @param path string
-- @param opts table
-- @return boolean
function M.exists(loc, path, opts)
  return backend().exists(loc, path, opts)
end

--- Compute content identity hash for a local file.
-- @param filepath string  path to local file
-- @return string|nil  hex hash
function M.hash(filepath)
  return backend().hash(filepath)
end

return M
