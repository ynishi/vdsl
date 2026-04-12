--- Runtime Store: distributed file store backend abstraction.
-- Backend-agnostic like FS, Transport, DB, PNG.
-- Rust backend injected via set_backend() from mlua bridge (#12).
--
-- Backend interface (table with functions):
--   status() -> { total_entries, total_errors, locations: { loc: counts } }
--   sync() -> string (task_id)                              -- non-blocking full sync
--   sync_route(src, dest) -> string (task_id)               -- non-blocking single route
--   poll(task_id) -> { status, result? } | nil              -- poll background task
--   get(path) -> entry | nil
--   pending(dest) -> { entry, ... }
--
-- All sync operations are non-blocking: they spawn a background task
-- and return a task_id immediately. Use poll(task_id) to check completion.
--
-- Default backend: all MOCK. Logs warnings to stderr.
-- Full implementation requires Rust bridge (vdsl-sync Store).

local M = {}

local _backend = nil

--- Set a custom store backend.
-- @param backend table or nil to reset to default
function M.set_backend(backend)
  if backend ~= nil and type(backend) ~= "table" then
    error("store.set_backend: backend must be a table", 2)
  end
  _backend = backend
end

-- ============================================================
-- Default backend: MOCK stubs (no Rust bridge)
-- ============================================================

local default = {}

local function warn_mock(method)
  io.stderr:write(string.format(
    "[WARN] runtime/store.%s: MOCK — Rust bridge not available. Use MCP (mlua backend) for full sync.\n",
    method))
end

--- status: MOCK.
function default.status()
  warn_mock("status")
  return { total_entries = 0, total_errors = 0, locations = {} }
end

--- sync: MOCK.
function default.sync()
  warn_mock("sync")
  return "mock-task-id"
end

--- sync_route: MOCK.
function default.sync_route(src, dest)
  warn_mock("sync_route")
  return "mock-task-id"
end

--- poll: MOCK.
function default.poll(task_id)
  warn_mock("poll")
  return nil
end

--- get: MOCK.
function default.get(path)
  warn_mock("get")
  return nil
end

--- pending: MOCK.
function default.pending(dest)
  warn_mock("pending")
  return {}
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

--- Get sync state summary.
-- @return table  { total_entries, total_errors, locations }
function M.status()
  return backend().status()
end

--- Full sync cycle: scan → retry → execute all.
-- Non-blocking: spawns background task and returns immediately.
-- @return string  task_id for polling via store.poll()
function M.sync()
  return backend().sync()
end

--- Single-route sync: reconcile missing + execute.
-- Non-blocking: spawns background task and returns immediately.
-- @param src string  source location ID (e.g. "local")
-- @param dest string  destination location ID (e.g. "cloud")
-- @return string  task_id for polling via store.poll()
function M.sync_route(src, dest)
  return backend().sync_route(src, dest)
end

--- Poll a background task status.
-- @param task_id string  from sync() or sync_route()
-- @return table|nil  { status="pending"|"running"|"completed"|"failed", result=... }
function M.poll(task_id)
  return backend().poll(task_id)
end

--- Get sync entry by path.
-- @param path string
-- @return table|nil  entry
function M.get(path)
  return backend().get(path)
end

--- List files pending sync to a destination.
-- @param dest string  location ID
-- @return table  array of entries
function M.pending(dest)
  return backend().pending(dest)
end

return M
