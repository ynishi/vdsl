--- Repository: VDSL generation record persistence.
-- 3-layer model: Workspace > Run > Generation.
-- Backend: SQLite via runtime/db.lua.

local DB = require("vdsl.runtime.db")
local id = require("vdsl.util.id")
local fs = require("vdsl.runtime.fs")

local Repo = {}
Repo.__index = Repo

--- Create a new Repository instance.
-- @param db_path string|nil  default ".vdsl/generations.db"
-- @return Repo
function Repo.new(db_path)
  return setmetatable({ db = DB.open(db_path) }, Repo)
end

--- ISO 8601 timestamp (UTC-like, local clock).
-- @return string
local function now()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

-- ============================================================
-- Workspace
-- ============================================================

--- Get or create a workspace by name.
-- @param name string
-- @return table { id, name, created_at }
function Repo:ensure_workspace(name)
  if type(name) ~= "string" or name == "" then
    error("Repo:ensure_workspace: name must be a non-empty string", 2)
  end
  local existing = self.db:query_one(
    "SELECT id, name, created_at FROM workspaces WHERE name = ?", name)
  if existing then return existing end
  local ws = { id = id.uuid(), name = name, created_at = now() }
  self.db:exec(
    "INSERT INTO workspaces (id, name, created_at) VALUES (?, ?, ?)",
    ws.id, ws.name, ws.created_at)
  return ws
end

--- List all workspaces.
-- @return table[]
function Repo:list_workspaces()
  return self.db:query("SELECT * FROM workspaces ORDER BY created_at DESC")
end

-- ============================================================
-- Run
-- ============================================================

--- Create a new run within a workspace.
-- @param workspace_id string
-- @param script string|nil  script filename
-- @return table { id, workspace_id, script, created_at }
function Repo:create_run(workspace_id, script)
  local run = {
    id = id.uuid(),
    workspace_id = workspace_id,
    script = script,
    created_at = now(),
  }
  self.db:exec(
    "INSERT INTO runs (id, workspace_id, script, created_at) VALUES (?, ?, ?, ?)",
    run.id, run.workspace_id, run.script, run.created_at)
  return run
end

--- Find runs by workspace.
-- @param workspace_id string
-- @param opts table|nil { limit, offset }
-- @return table[]
function Repo:find_by_workspace(workspace_id, opts)
  opts = opts or {}
  local limit = opts.limit or 50
  return self.db:query(
    "SELECT * FROM runs WHERE workspace_id = ? ORDER BY created_at DESC LIMIT ?",
    workspace_id, limit)
end

-- ============================================================
-- Generation
-- ============================================================

--- Save a generation record.
-- @param gen table { run_id, seed, model, output, recipe }
-- @return table gen with id and created_at populated
function Repo:save(gen)
  if not gen.run_id then
    error("Repo:save: run_id is required", 2)
  end
  gen.id = gen.id or id.uuid()
  gen.created_at = gen.created_at or now()
  self.db:exec(
    "INSERT INTO generations (id, run_id, seed, model, output, created_at, recipe) VALUES (?, ?, ?, ?, ?, ?, ?)",
    gen.id, gen.run_id, gen.seed, gen.model, gen.output, gen.created_at, gen.recipe)
  return gen
end

--- Find a generation by ID.
-- @param gen_id string
-- @return table|nil
function Repo:find(gen_id)
  return self.db:query_one("SELECT * FROM generations WHERE id = ?", gen_id)
end

--- Find generations by run.
-- @param run_id string
-- @return table[]
function Repo:find_by_run(run_id)
  return self.db:query(
    "SELECT * FROM generations WHERE run_id = ? ORDER BY created_at", run_id)
end

--- Filtered query across generations.
-- @param filter table { model, script, workspace, date_from, date_to }
-- @param opts table|nil { limit, offset, sort }
-- @return table[]
function Repo:query(filter, opts)
  filter = filter or {}
  opts = opts or {}
  local where, params = {}, {}
  if filter.model then
    where[#where + 1] = "g.model = ?"
    params[#params + 1] = filter.model
  end
  if filter.script then
    where[#where + 1] = "r.script = ?"
    params[#params + 1] = filter.script
  end
  if filter.workspace then
    where[#where + 1] = "w.name = ?"
    params[#params + 1] = filter.workspace
  end
  if filter.date_from then
    where[#where + 1] = "g.created_at >= ?"
    params[#params + 1] = filter.date_from
  end
  if filter.date_to then
    where[#where + 1] = "g.created_at <= ?"
    params[#params + 1] = filter.date_to
  end

  local sql = "SELECT g.*, r.script, r.workspace_id, w.name as workspace_name"
    .. " FROM generations g"
    .. " JOIN runs r ON g.run_id = r.id"
    .. " JOIN workspaces w ON r.workspace_id = w.id"
  if #where > 0 then
    sql = sql .. " WHERE " .. table.concat(where, " AND ")
  end
  local sort = opts.sort or "g.created_at DESC"
  sql = sql .. " ORDER BY " .. sort
  local limit = opts.limit or 50
  sql = sql .. " LIMIT " .. limit
  if opts.offset then
    sql = sql .. " OFFSET " .. opts.offset
  end
  return self.db:query(sql, table.unpack(params))
end

--- Search inside recipe JSON (Lua-side parsing).
-- Path format: dot-separated keys, e.g. "world.clip_skip".
-- @param dot_path string  e.g. "world.clip_skip"
-- @param value any  value to match
-- @param opts table|nil  { limit }
-- @return table[]
function Repo:search(dot_path, value, opts)
  local json = require("vdsl.util.json")
  local limit = (opts and opts.limit) or 50
  local rows = self.db:query(
    "SELECT * FROM generations WHERE recipe IS NOT NULL ORDER BY created_at DESC")
  local results = {}
  for _, row in ipairs(rows) do
    local ok, recipe = pcall(json.decode, row.recipe)
    if ok and type(recipe) == "table" then
      -- Walk dot path
      local node = recipe
      for key in dot_path:gmatch("[^%.]+") do
        if type(node) ~= "table" then node = nil; break end
        node = node[key] or node[tonumber(key)]
      end
      if node == value then
        results[#results + 1] = row
        if #results >= limit then break end
      end
    end
  end
  return results
end

--- Statistics grouped by a field.
-- @param group_by string  "model" | "script" | "workspace" | "date"
-- @return table[] { group, count }
function Repo:stats(group_by)
  if group_by == "model" then
    return self.db:query(
      "SELECT model as 'group', count(*) as count FROM generations GROUP BY model ORDER BY count DESC")
  elseif group_by == "script" then
    return self.db:query(
      "SELECT r.script as 'group', count(*) as count FROM generations g"
      .. " JOIN runs r ON g.run_id = r.id GROUP BY r.script ORDER BY count DESC")
  elseif group_by == "workspace" then
    return self.db:query(
      "SELECT w.name as 'group', count(*) as count FROM generations g"
      .. " JOIN runs r ON g.run_id = r.id"
      .. " JOIN workspaces w ON r.workspace_id = w.id"
      .. " GROUP BY w.name ORDER BY count DESC")
  elseif group_by == "date" then
    return self.db:query(
      "SELECT substr(created_at,1,10) as 'group', count(*) as count"
      .. " FROM generations GROUP BY substr(created_at,1,10) ORDER BY 'group' DESC")
  else
    error("Repo:stats: unsupported group_by: " .. tostring(group_by), 2)
  end
end

-- ============================================================
-- Meta (mutable key-value store per generation)
-- ============================================================

local json -- lazy-loaded

--- Get meta for a generation as a Lua table.
-- @param gen_id string
-- @return table meta (empty table if none)
function Repo:get_meta(gen_id)
  json = json or require("vdsl.util.json")
  local row = self.db:query_one("SELECT meta FROM generations WHERE id = ?", gen_id)
  if not row or not row.meta then return {} end
  local ok, data = pcall(json.decode, row.meta)
  if ok and type(data) == "table" then return data end
  return {}
end

--- Set a single meta key (merge into existing meta).
-- @param gen_id string
-- @param key string  dot-path supported (e.g. "sns.twitter.post_id")
-- @param value any   JSON-serializable value
function Repo:set_meta(gen_id, key, value)
  json = json or require("vdsl.util.json")
  local meta = self:get_meta(gen_id)
  -- Support dot-path: "sns.twitter.post_id" → nested table
  local keys = {}
  for k in key:gmatch("[^%.]+") do keys[#keys + 1] = k end
  local node = meta
  for i = 1, #keys - 1 do
    if type(node[keys[i]]) ~= "table" then
      node[keys[i]] = {}
    end
    node = node[keys[i]]
  end
  node[keys[#keys]] = value
  self.db:exec("UPDATE generations SET meta = ? WHERE id = ?",
    json.encode(meta), gen_id)
end

--- Replace entire meta for a generation.
-- @param gen_id string
-- @param meta table
function Repo:replace_meta(gen_id, meta)
  json = json or require("vdsl.util.json")
  if type(meta) ~= "table" then
    error("Repo:replace_meta: meta must be a table", 2)
  end
  self.db:exec("UPDATE generations SET meta = ? WHERE id = ?",
    json.encode(meta), gen_id)
end

--- Sync meta from DB → PNG vdsl_meta chunk.
-- @param gen_id string
-- @return boolean success
-- @return string|nil error
function Repo:sync_meta_to_png(gen_id)
  json = json or require("vdsl.util.json")
  local png = require("vdsl.runtime.png")
  local row = self.db:query_one("SELECT output, meta FROM generations WHERE id = ?", gen_id)
  if not row then return false, "generation not found" end
  if not row.output then return false, "no output path" end
  if not row.meta then return true end  -- nothing to sync
  return png.inject_text(row.output, { vdsl_meta = row.meta })
end

--- Load meta from PNG vdsl_meta chunk → DB.
-- @param gen_id string
-- @return boolean success
-- @return string|nil error
function Repo:load_meta_from_png(gen_id)
  json = json or require("vdsl.util.json")
  local png = require("vdsl.runtime.png")
  local row = self.db:query_one("SELECT output FROM generations WHERE id = ?", gen_id)
  if not row or not row.output then return false, "generation or output not found" end
  local chunks, err = png.read_text(row.output)
  if not chunks then return false, err end
  if chunks["vdsl_meta"] then
    self.db:exec("UPDATE generations SET meta = ? WHERE id = ?",
      chunks["vdsl_meta"], gen_id)
    return true
  end
  return true  -- no meta chunk, not an error
end

--- Reindex: scan PNG files and rebuild DB records from vdsl tEXt chunks.
-- Only inserts records whose gen_id is not already in the DB.
-- PNGs without vdsl chunks (v2 gen_id) are skipped.
-- @param path string  directory to scan (default "output/")
-- @param opts table|nil  { verbose = bool }
-- @return table { scanned, indexed, skipped, errors }
function Repo:reindex(path, opts)
  path = path or "output/"
  opts = opts or {}
  local png   = require("vdsl.runtime.png")
  local json  = require("vdsl.util.json")
  local verbose = opts.verbose or false

  -- Collect .png files recursively
  local files = fs.find(path, "*.png")

  local stats = { scanned = #files, indexed = 0, skipped = 0, errors = 0 }

  for _, filepath in ipairs(files) do
    local chunks, err = png.read_text(filepath)
    if not chunks or not chunks["vdsl"] then
      stats.skipped = stats.skipped + 1
      goto continue
    end

    local ok, recipe = pcall(json.decode, chunks["vdsl"])
    if not ok or type(recipe) ~= "table" then
      stats.errors = stats.errors + 1
      if verbose then
        io.stderr:write("reindex: bad vdsl chunk in " .. filepath .. "\n")
      end
      goto continue
    end

    -- Require v2 fields
    if not recipe.gen_id then
      stats.skipped = stats.skipped + 1
      goto continue
    end

    -- Skip if already in DB
    local existing = self.db:query_one(
      "SELECT id FROM generations WHERE id = ?", recipe.gen_id)
    if existing then
      stats.skipped = stats.skipped + 1
      goto continue
    end

    -- Ensure workspace + run exist
    local ws_name = recipe.script and recipe.script:match("^([^_]+_[^_]+)") or "unknown"
    local ws = self:ensure_workspace(ws_name)

    local run_id = recipe.run_id or id.uuid()
    -- Check if run exists, create if not
    local existing_run = self.db:query_one("SELECT id FROM runs WHERE id = ?", run_id)
    if not existing_run then
      self.db:exec(
        "INSERT INTO runs (id, workspace_id, script, created_at) VALUES (?, ?, ?, ?)",
        run_id, ws.id, recipe.script, recipe.ts or os.date("!%Y-%m-%dT%H:%M:%SZ"))
    end

    -- Extract model from recipe
    local model = recipe.world and recipe.world.model or nil

    self:save({
      id         = recipe.gen_id,
      run_id     = run_id,
      seed       = recipe.seed,
      model      = model,
      output     = filepath,
      created_at = recipe.ts or os.date("!%Y-%m-%dT%H:%M:%SZ"),
      recipe     = chunks["vdsl"],
    })
    -- Also import vdsl_meta chunk if present
    if chunks["vdsl_meta"] then
      self.db:exec("UPDATE generations SET meta = ? WHERE id = ?",
        chunks["vdsl_meta"], recipe.gen_id)
    end
    stats.indexed = stats.indexed + 1

    if verbose then
      io.stderr:write("reindex: " .. recipe.gen_id:sub(1, 8) .. " ← " .. filepath .. "\n")
    end

    ::continue::
  end

  return stats
end

--- Close the repository.
function Repo:close()
  self.db:close()
end

return Repo
