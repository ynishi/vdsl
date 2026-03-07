--- Sync: 3-location file synchronization engine.
-- Backend-agnostic like FS, Transport, DB. Default: shell (rsync/rclone/scp).
-- Custom backends injected via set_backend() (e.g. mlua/Rust).
--
-- Locations:
--   local  — Local filesystem (macOS dev machine)
--   pod    — RunPod pod (ComfyUI server)
--   cloud  — Cloud storage (Backblaze B2 via rclone)
--
-- Sync state tracked in SQLite sync_state table.
-- loc_* columns: "present" | "pending" | "syncing" | "unknown" | "absent"
--
-- Backend interface (table with functions):
--   push(src_path, dest_loc, dest_path, opts) -> boolean, string|nil
--   pull(src_loc, src_path, dest_path, opts)  -> boolean, string|nil
--   list(loc, path, opts) -> { { path, size, mtime }, ... }
--   hash(loc, path, opts) -> string|nil
--   exists(loc, path, opts) -> boolean
--
-- opts always includes:
--   pod_id   — RunPod pod ID (for pod operations)
--   ssh_key  — SSH key path
--   bucket   — B2 bucket name (for cloud operations)

local DB  = require("vdsl.runtime.db")
local fs  = require("vdsl.runtime.fs")
local id  = require("vdsl.util.id")

local Sync = {}
Sync.__index = Sync

local _backend = nil

-- ============================================================
-- File type constants
-- ============================================================

Sync.TYPE_IMAGE   = "image"
Sync.TYPE_RECIPE  = "recipe"
Sync.TYPE_ASSET   = "asset"
Sync.TYPE_DB      = "db"

-- ============================================================
-- Location state constants
-- ============================================================

Sync.PRESENT  = "present"
Sync.PENDING  = "pending"
Sync.SYNCING  = "syncing"
Sync.UNKNOWN  = "unknown"
Sync.ABSENT   = "absent"

-- ============================================================
-- Backend injection
-- ============================================================

--- Set a custom sync backend.
-- @param backend table or nil to reset to default
function Sync.set_backend(backend)
  if backend ~= nil and type(backend) ~= "table" then
    error("sync.set_backend: backend must be a table", 2)
  end
  _backend = backend
end

-- ============================================================
-- Default backend (shell: rsync/rclone/scp)
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

--- List files at a remote location.
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

-- ---- Pod operations (scp/ssh) ----

function default._push_pod(src, dest, opts)
  local ssh_key = opts.ssh_key or "~/.ssh/id_ed25519_runpod"
  local pod_id = opts.pod_id
  if not pod_id then return false, "pod_id required" end
  -- Use runpod-cli exec for scp
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
  -- Ensure local dir exists
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
    -- rclone lsf --format 'ps' outputs: path;size
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
    -- Get size via io
    local f = io.open(fpath, "rb")
    if f then
      local size = f:seek("end")
      f:close()
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
-- Sync instance (wraps DB + backend)
-- ============================================================

--- Create a new Sync engine.
-- @param db DB  opened DB instance (shared with Repository)
-- @param opts table|nil  { pod_id, ssh_key, bucket }
-- @return Sync
function Sync.new(db, opts)
  if not db then
    error("Sync.new: db is required", 2)
  end
  opts = opts or {}
  local self = setmetatable({}, Sync)
  self.db      = db
  self.pod_id  = opts.pod_id
  self.ssh_key = opts.ssh_key
  self.bucket  = opts.bucket
  return self
end

--- Build opts table for backend calls.
-- @return table
function Sync:_opts()
  return {
    pod_id  = self.pod_id,
    ssh_key = self.ssh_key,
    bucket  = self.bucket,
  }
end

--- ISO 8601 timestamp.
local function now()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

-- ============================================================
-- State management (sync_state CRUD)
-- ============================================================

--- Register a file in sync_state (idempotent by file_path).
-- For PNG images, auto-computes image_hash (IHDR+IDAT only) for identity.
-- If file_hash matches an existing entry at a different path, returns
-- the existing entry with is_duplicate=true (same image, metadata may differ).
-- @param file_path string
-- @param file_type string  TYPE_IMAGE | TYPE_RECIPE | TYPE_ASSET | TYPE_DB
-- @param opts table|nil  { gen_id, file_size, file_hash, loc_local, loc_pod, loc_cloud }
-- @return table sync_state row (with .is_duplicate if duplicate detected)
function Sync:register(file_path, file_type, opts)
  opts = opts or {}

  -- Auto-compute image_hash for PNG files if not provided
  local file_hash = opts.file_hash
  if not file_hash and file_type == Sync.TYPE_IMAGE and file_path:match("%.png$") then
    local png = require("vdsl.util.png")
    if fs.exists(file_path) then
      file_hash = png.image_hash(file_path)
    end
  end

  -- Check by path first (existing entry for same path)
  local existing = self.db:query_one(
    "SELECT * FROM sync_state WHERE file_path = ?", file_path)
  if existing then
    local ts = now()
    -- If image_hash changed, the pixel data changed → mark remotes as pending
    local hash_changed = file_hash and existing.file_hash and file_hash ~= existing.file_hash
    if hash_changed then
      self.db:exec(
        "UPDATE sync_state SET file_type = ?, file_size = ?, file_hash = ?, gen_id = ?, loc_pod = 'pending', loc_cloud = 'pending', updated_at = ? WHERE id = ?",
        file_type, opts.file_size, file_hash, opts.gen_id, ts, existing.id)
    else
      -- Metadata-only update (or no change): don't invalidate remote sync
      self.db:exec(
        "UPDATE sync_state SET file_type = ?, file_size = ?, file_hash = ?, gen_id = ?, updated_at = ? WHERE id = ?",
        file_type, opts.file_size, file_hash, opts.gen_id, ts, existing.id)
    end
    existing.file_type = file_type
    existing.file_hash = file_hash
    existing.updated_at = ts
    return existing
  end

  -- Check by image_hash (same image at different path)
  if file_hash then
    local dup = self.db:query_one(
      "SELECT * FROM sync_state WHERE file_hash = ? AND file_path != ?",
      file_hash, file_path)
    if dup then
      dup.is_duplicate = true
      dup.duplicate_of = dup.file_path
      return dup
    end
  end

  local row = {
    id        = id.uuid(),
    file_path = file_path,
    file_type = file_type,
    file_hash = file_hash,
    file_size = opts.file_size,
    gen_id    = opts.gen_id,
    loc_local = opts.loc_local or Sync.PRESENT,
    loc_pod   = opts.loc_pod or Sync.UNKNOWN,
    loc_cloud = opts.loc_cloud or Sync.UNKNOWN,
    updated_at = now(),
  }
  self.db:exec(
    "INSERT INTO sync_state (id, file_path, file_type, file_hash, file_size, gen_id, loc_local, loc_pod, loc_cloud, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    row.id, row.file_path, row.file_type, row.file_hash, row.file_size,
    row.gen_id, row.loc_local, row.loc_pod, row.loc_cloud, row.updated_at)
  return row
end

--- Update location state for a file.
-- @param file_path string
-- @param loc string  "local", "pod", or "cloud"
-- @param state string  PRESENT | PENDING | SYNCING | UNKNOWN | ABSENT
function Sync:set_state(file_path, loc, state)
  local col = "loc_" .. loc
  -- Validate column name to prevent injection
  if col ~= "loc_local" and col ~= "loc_pod" and col ~= "loc_cloud" then
    error("sync:set_state: invalid location: " .. tostring(loc), 2)
  end
  self.db:exec(
    "UPDATE sync_state SET " .. col .. " = ?, updated_at = ? WHERE file_path = ?",
    state, now(), file_path)
end

--- Set sync error for a file.
-- @param file_path string
-- @param err string|nil  error message (nil to clear)
function Sync:set_error(file_path, err)
  self.db:exec(
    "UPDATE sync_state SET error = ?, updated_at = ? WHERE file_path = ?",
    err, now(), file_path)
end

--- Get sync state for a file.
-- @param file_path string
-- @return table|nil
function Sync:get(file_path)
  return self.db:query_one("SELECT * FROM sync_state WHERE file_path = ?", file_path)
end

--- List files pending sync to a location.
-- @param dest_loc string  "local", "pod", or "cloud"
-- @return table[]
function Sync:pending(dest_loc)
  local col = "loc_" .. dest_loc
  if col ~= "loc_local" and col ~= "loc_pod" and col ~= "loc_cloud" then
    error("sync:pending: invalid location: " .. tostring(dest_loc), 2)
  end
  return self.db:query(
    "SELECT * FROM sync_state WHERE " .. col .. " IN ('pending', 'unknown') ORDER BY updated_at")
end

--- List all tracked files.
-- @param opts table|nil  { file_type, limit }
-- @return table[]
function Sync:list(opts)
  opts = opts or {}
  local where, params = {}, {}
  if opts.file_type then
    where[#where + 1] = "file_type = ?"
    params[#params + 1] = opts.file_type
  end
  local sql = "SELECT * FROM sync_state"
  if #where > 0 then
    sql = sql .. " WHERE " .. table.concat(where, " AND ")
  end
  sql = sql .. " ORDER BY updated_at DESC"
  if opts.limit then
    sql = sql .. " LIMIT " .. tonumber(opts.limit)
  end
  if #params == 0 then
    return self.db:query(sql)
  end
  return self.db:query(sql, table.unpack(params))
end

--- Summary: count by state per location.
-- @return table { local = { present = N, pending = N, ... }, pod = ..., cloud = ... }
function Sync:summary()
  local result = { ["local"] = {}, pod = {}, cloud = {} }
  for _, loc in ipairs({"local", "pod", "cloud"}) do
    local col = "loc_" .. loc
    local rows = self.db:query(
      "SELECT " .. col .. " as state, count(*) as count FROM sync_state GROUP BY " .. col)
    for _, row in ipairs(rows) do
      result[loc][row.state] = row.count
    end
  end
  return result
end

-- ============================================================
-- Sync operations (push / pull)
-- ============================================================

--- Push a single file from local to a destination.
-- Updates sync_state before/after transfer.
-- @param file_path string  local file path
-- @param dest_loc string  "pod" or "cloud"
-- @param dest_path string  destination path on remote
-- @return boolean success, string|nil error
function Sync:push_file(file_path, dest_loc, dest_path)
  local state = self:get(file_path)
  if not state then
    return false, "file not registered in sync_state: " .. file_path
  end

  self:set_state(file_path, dest_loc, Sync.SYNCING)
  self:set_error(file_path, nil)

  local ok, err = backend().push(file_path, dest_loc, dest_path, self:_opts())
  if ok then
    self:set_state(file_path, dest_loc, Sync.PRESENT)
    self.db:exec(
      "UPDATE sync_state SET synced_at = ? WHERE file_path = ?",
      now(), file_path)
    return true
  else
    self:set_state(file_path, dest_loc, Sync.PENDING)
    self:set_error(file_path, err)
    return false, err
  end
end

--- Pull a single file from a source to local.
-- @param src_loc string  "pod" or "cloud"
-- @param src_path string  source path on remote
-- @param dest_path string  local destination path
-- @param reg_opts table|nil  { file_type, gen_id } for auto-registration
-- @return boolean success, string|nil error
function Sync:pull_file(src_loc, src_path, dest_path, reg_opts)
  reg_opts = reg_opts or {}

  local ok, err = backend().pull(src_loc, src_path, dest_path, self:_opts())
  if not ok then return false, err end

  -- Auto-register if not tracked
  local state = self:get(dest_path)
  if not state then
    local ftype = reg_opts.file_type or Sync.TYPE_ASSET
    self:register(dest_path, ftype, {
      gen_id    = reg_opts.gen_id,
      loc_local = Sync.PRESENT,
    })
  else
    self:set_state(dest_path, "local", Sync.PRESENT)
  end
  self:set_state(dest_path, src_loc, Sync.PRESENT)

  return true
end

--- Push all pending files to a destination.
-- @param dest_loc string  "pod" or "cloud"
-- @param path_mapper function(file_path) -> dest_path
-- @return table { pushed, failed, errors }
function Sync:push_pending(dest_loc, path_mapper)
  local files = self:pending(dest_loc)
  local stats = { pushed = 0, failed = 0, errors = {} }
  for _, row in ipairs(files) do
    -- Skip if file doesn't exist locally
    if not fs.exists(row.file_path) then
      self:set_state(row.file_path, "local", Sync.ABSENT)
      stats.failed = stats.failed + 1
      goto continue
    end
    local dest_path = path_mapper(row.file_path, row)
    local ok, err = self:push_file(row.file_path, dest_loc, dest_path)
    if ok then
      stats.pushed = stats.pushed + 1
    else
      stats.failed = stats.failed + 1
      stats.errors[#stats.errors + 1] = { path = row.file_path, error = err }
    end
    ::continue::
  end
  return stats
end

--- Scan a local directory and register new files.
-- Files already tracked are updated; new files are registered as pending.
-- @param dir string  directory to scan
-- @param file_type string  TYPE_IMAGE | TYPE_RECIPE | TYPE_ASSET
-- @param opts table|nil  { pattern = "*.png", dest_pod, dest_cloud }
-- @return table { scanned, registered, updated }
function Sync:scan(dir, file_type, opts)
  opts = opts or {}
  local pattern = opts.pattern or "*"
  local files = fs.find(dir, pattern)
  local stats = { scanned = #files, registered = 0, updated = 0 }
  for _, fpath in ipairs(files) do
    local existing = self:get(fpath)
    local fsize
    local f = io.open(fpath, "rb")
    if f then
      fsize = f:seek("end")
      f:close()
    end
    if existing then
      -- Check if file changed (size differs)
      if fsize and existing.file_size ~= fsize then
        self.db:exec(
          "UPDATE sync_state SET file_size = ?, loc_pod = 'pending', loc_cloud = 'pending', updated_at = ? WHERE id = ?",
          fsize, now(), existing.id)
        stats.updated = stats.updated + 1
      end
    else
      self:register(fpath, file_type, {
        file_size = fsize,
        loc_local = Sync.PRESENT,
        loc_pod   = Sync.PENDING,
        loc_cloud = Sync.PENDING,
      })
      stats.registered = stats.registered + 1
    end
  end
  return stats
end

-- ============================================================
-- Convenience: register generation result
-- ============================================================

--- Register a generation's output files for sync.
-- Call after vdsl.run() completes (auto-hook).
-- @param gen table  { id, output, recipe_path }
-- @return table  array of registered sync_state rows
function Sync:register_generation(gen)
  local rows = {}
  if gen.output and fs.exists(gen.output) then
    local fsize
    local f = io.open(gen.output, "rb")
    if f then fsize = f:seek("end"); f:close() end
    rows[#rows + 1] = self:register(gen.output, Sync.TYPE_IMAGE, {
      gen_id    = gen.id,
      file_size = fsize,
      loc_local = Sync.PRESENT,
      loc_pod   = Sync.PENDING,
      loc_cloud = Sync.PENDING,
    })
  end
  if gen.recipe_path and fs.exists(gen.recipe_path) then
    rows[#rows + 1] = self:register(gen.recipe_path, Sync.TYPE_RECIPE, {
      gen_id    = gen.id,
      loc_local = Sync.PRESENT,
      loc_pod   = Sync.PENDING,
      loc_cloud = Sync.PENDING,
    })
  end
  return rows
end

return Sync
