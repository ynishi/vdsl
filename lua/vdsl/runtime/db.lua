--- SQLite backend for VDSL generation database.
-- Backend-agnostic like FS, Transport, PNG. Default: lsqlite3complete.
-- Custom backends injected via set_backend() (e.g. mlua/Rust rusqlite).
--
-- Backend interface (table with functions):
--   open(path) -> conn
--     conn:exec(sql, packed_params?) -> nil (throws on error)
--     conn:query(sql, packed_params?) -> [{col=val}, ...]
--     conn:close()
--   packed_params = table.pack(...) result with .n field

local fs = require("vdsl.runtime.fs")

local DB = {}
DB.__index = DB

local _backend = nil

--- Set a custom DB backend.
-- @param backend table|nil  { open = function(path) -> conn } or nil to reset
function DB.set_backend(backend)
  if backend ~= nil and type(backend) ~= "table" then
    error("DB.set_backend: backend must be a table", 2)
  end
  _backend = backend
end

local SCHEMA = [[
CREATE TABLE IF NOT EXISTS workspaces (
    id         TEXT PRIMARY KEY,
    name       TEXT NOT NULL,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_workspaces_name ON workspaces(name);

CREATE TABLE IF NOT EXISTS runs (
    id           TEXT PRIMARY KEY,
    workspace_id TEXT NOT NULL REFERENCES workspaces(id),
    script       TEXT,
    created_at   TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_runs_workspace ON runs(workspace_id);
CREATE INDEX IF NOT EXISTS idx_runs_created   ON runs(created_at);

CREATE TABLE IF NOT EXISTS generations (
    id         TEXT PRIMARY KEY,
    run_id     TEXT NOT NULL REFERENCES runs(id),
    seed       INTEGER,
    model      TEXT,
    output     TEXT,
    created_at TEXT NOT NULL,
    recipe     TEXT,
    meta       TEXT
);
CREATE INDEX IF NOT EXISTS idx_gens_run     ON generations(run_id);
CREATE INDEX IF NOT EXISTS idx_gens_created ON generations(created_at);
CREATE INDEX IF NOT EXISTS idx_gens_model   ON generations(model);
]]

-- Migration: add meta column if missing (for existing DBs)
local MIGRATE = [[
ALTER TABLE generations ADD COLUMN meta TEXT;
]]

-- Migration: sync_state table for 3-location sync (Local/Pod/Cloud)
local MIGRATE_SYNC = [[
CREATE TABLE IF NOT EXISTS sync_state (
    id          TEXT PRIMARY KEY,
    file_path   TEXT NOT NULL,
    file_type   TEXT NOT NULL,
    file_hash   TEXT,
    file_size   INTEGER,
    gen_id      TEXT REFERENCES generations(id),
    loc_local   TEXT NOT NULL DEFAULT 'unknown',
    loc_pod     TEXT NOT NULL DEFAULT 'unknown',
    loc_cloud   TEXT NOT NULL DEFAULT 'unknown',
    updated_at  TEXT NOT NULL,
    synced_at   TEXT,
    error       TEXT
);
CREATE INDEX IF NOT EXISTS idx_sync_file_path ON sync_state(file_path);
CREATE INDEX IF NOT EXISTS idx_sync_file_type ON sync_state(file_type);
CREATE INDEX IF NOT EXISTS idx_sync_gen_id    ON sync_state(gen_id);
CREATE INDEX IF NOT EXISTS idx_sync_pending   ON sync_state(loc_local, loc_pod, loc_cloud);
]]

-- ============================================================
-- Default backend (lsqlite3complete)
-- ============================================================

local function make_default_conn(path)
  local sqlite3 = require("lsqlite3complete")
  local raw_db, _, errmsg = sqlite3.open(path)
  if not raw_db then
    error("DB.open: failed to open " .. path .. ": " .. (errmsg or "unknown"), 2)
  end

  local conn = {}

  function conn:exec(sql, packed_params)
    if not packed_params or packed_params.n == 0 then
      local rc = raw_db:exec(sql)
      if rc ~= sqlite3.OK then
        error("exec failed: " .. raw_db:errmsg() .. "\nSQL: " .. sql, 2)
      end
      return
    end
    local stmt = raw_db:prepare(sql)
    if not stmt then
      error("prepare failed: " .. raw_db:errmsg() .. "\nSQL: " .. sql, 2)
    end
    stmt:bind_values(table.unpack(packed_params, 1, packed_params.n))
    local rc = stmt:step()
    stmt:finalize()
    -- SQLITE_DONE=101, SQLITE_ROW=100; anything else is an error
    if rc ~= sqlite3.DONE and rc ~= sqlite3.ROW then
      error("step failed (" .. tostring(rc) .. "): " .. raw_db:errmsg() .. "\nSQL: " .. sql, 2)
    end
  end

  function conn:query(sql, packed_params)
    local stmt = raw_db:prepare(sql)
    if not stmt then
      error("query prepare failed: " .. raw_db:errmsg() .. "\nSQL: " .. sql, 2)
    end
    if packed_params and packed_params.n > 0 then
      stmt:bind_values(table.unpack(packed_params, 1, packed_params.n))
    end
    local rows = {}
    for row in stmt:nrows() do
      rows[#rows + 1] = row
    end
    stmt:finalize()
    return rows
  end

  function conn:close()
    if raw_db then
      raw_db:close()
      raw_db = nil
    end
  end

  return conn
end

--- Open (or create) the database.
-- @param path string|nil  default ".vdsl/generations.db", ":memory:" for tests
-- @return DB
function DB.open(path)
  path = path or ".vdsl/generations.db"
  -- Ensure parent directory exists (skip for :memory:)
  if path ~= ":memory:" then
    local dir = path:match("(.+)/[^/]+$")
    if dir then fs.mkdir(dir) end
  end

  local conn
  if _backend then
    conn = _backend.open(path)
  else
    conn = make_default_conn(path)
  end

  -- PRAGMA settings
  conn:exec("PRAGMA journal_mode=WAL;")
  conn:exec("PRAGMA foreign_keys=ON;")
  -- Schema
  conn:exec(SCHEMA)
  -- Migration (idempotent: ALTER ADD fails if column exists)
  pcall(function() conn:exec(MIGRATE) end)
  -- Migration: sync_state (idempotent via CREATE IF NOT EXISTS)
  conn:exec(MIGRATE_SYNC)

  return setmetatable({ _conn = conn, _path = path }, DB)
end

--- Execute a statement with optional bind parameters.
-- @param sql string
-- @param ... bind values (nil-safe: uses table.pack to preserve trailing nils)
-- @return nil
function DB:exec(sql, ...)
  local n = select('#', ...)
  if n == 0 then
    self._conn:exec(sql)
    return
  end
  self._conn:exec(sql, table.pack(...))
end

--- Query rows. Returns array of { col_name = value, ... } tables.
-- @param sql string
-- @param ... bind values (nil-safe)
-- @return table[]
function DB:query(sql, ...)
  local n = select('#', ...)
  if n == 0 then
    return self._conn:query(sql)
  end
  return self._conn:query(sql, table.pack(...))
end

--- Query single row.
-- @param sql string
-- @param ... bind values
-- @return table|nil
function DB:query_one(sql, ...)
  local rows = self:query(sql, ...)
  return rows[1]
end

--- Close the database.
function DB:close()
  if self._conn then
    self._conn:close()
    self._conn = nil
  end
end

return DB
