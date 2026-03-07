--- test_repository.lua: Tests for ID, DB, and Repository layers
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;tests/?.lua;'..package.path" tests/test_repository.lua

local T = require("harness")

-- ============================================================
-- util/id.lua
-- ============================================================
local id = require("vdsl.util.id")

-- UUID format: 8-4-4-4-12 hex
local u1 = id.uuid()
T.ok("uuid: format", u1:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil)
-- Version 4: 13th char = '4'
T.eq("uuid: version 4", u1:sub(15, 15), "4")
-- Variant 1: 19th char in {8,9,a,b}
local variant_char = u1:sub(20, 20)
T.ok("uuid: variant 1", variant_char == "8" or variant_char == "9" or variant_char == "a" or variant_char == "b")

-- Uniqueness
local u2 = id.uuid()
T.ok("uuid: unique", u1 ~= u2)

-- Short
T.eq("uuid: short length", #id.short(u1), 8)
T.eq("uuid: short value", id.short(u1), u1:sub(1, 8))

-- ============================================================
-- runtime/db.lua — in-memory
-- ============================================================
local DB = require("vdsl.runtime.db")

local db = DB.open(":memory:")
T.ok("db: open", db ~= nil)

-- Schema check: tables exist
local tables = db:query("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
local table_names = {}
for _, row in ipairs(tables) do table_names[#table_names + 1] = row.name end
local names_str = table.concat(table_names, ",")
T.ok("db: workspaces table",  names_str:find("workspaces") ~= nil)
T.ok("db: runs table",        names_str:find("runs") ~= nil)
T.ok("db: generations table", names_str:find("generations") ~= nil)

-- Insert and query
db:exec("INSERT INTO workspaces (id, name, created_at) VALUES (?, ?, ?)",
  "ws-001", "test_workspace", "2026-03-05T00:00:00Z")
local ws = db:query_one("SELECT * FROM workspaces WHERE id = ?", "ws-001")
T.eq("db: insert/query name", ws.name, "test_workspace")

-- query returns empty array for no results
local empty = db:query("SELECT * FROM workspaces WHERE id = ?", "nonexistent")
T.eq("db: empty query", #empty, 0)

-- query_one returns nil for no results
T.eq("db: query_one nil", db:query_one("SELECT * FROM workspaces WHERE id = ?", "nope"), nil)

db:close()

-- ============================================================
-- repository.lua — full CRUD
-- ============================================================
local Repo = require("vdsl.repository")

local repo = Repo.new(":memory:")
T.ok("repo: new", repo ~= nil)

-- Workspace: ensure_workspace creates new
local ws1 = repo:ensure_workspace("gravure_klimt")
T.ok("repo: ws id", ws1.id:match("^%x+%-") ~= nil)
T.eq("repo: ws name", ws1.name, "gravure_klimt")
T.ok("repo: ws created_at", ws1.created_at:match("^%d%d%d%d%-") ~= nil)

-- Workspace: ensure_workspace returns existing
local ws1b = repo:ensure_workspace("gravure_klimt")
T.eq("repo: ws idempotent", ws1b.id, ws1.id)

-- Workspace: different name = different ws
local ws2 = repo:ensure_workspace("puni_slider")
T.ok("repo: ws different", ws2.id ~= ws1.id)

-- list_workspaces
local wss = repo:list_workspaces()
T.eq("repo: list ws count", #wss, 2)

-- Workspace: validation
T.err("repo: ws empty name", function() repo:ensure_workspace("") end)
T.err("repo: ws nil name",   function() repo:ensure_workspace(nil) end)

-- Run: create
local run1 = repo:create_run(ws1.id, "gravure_klimt_p1.lua")
T.ok("repo: run id", run1.id:match("^%x+%-") ~= nil)
T.eq("repo: run workspace_id", run1.workspace_id, ws1.id)
T.eq("repo: run script", run1.script, "gravure_klimt_p1.lua")

local run2 = repo:create_run(ws1.id, "gravure_klimt_p2.lua")

-- find_by_workspace
local runs = repo:find_by_workspace(ws1.id)
T.eq("repo: runs count", #runs, 2)

-- Generation: save
local gen1 = repo:save({
  run_id = run1.id,
  seed   = 42,
  model  = "illustrious_v30.safetensors",
  output = "output/20260305/abc12345/00001.png",
  recipe = '{"world":{"model":"illustrious_v30.safetensors","clip_skip":2}}',
})
T.ok("repo: gen id", gen1.id:match("^%x+%-") ~= nil)
T.eq("repo: gen seed", gen1.seed, 42)

local gen2 = repo:save({
  run_id = run1.id,
  seed   = 43,
  model  = "illustrious_v30.safetensors",
  output = "output/20260305/abc12345/00002.png",
  recipe = '{"world":{"model":"illustrious_v30.safetensors","clip_skip":2}}',
})

local gen3 = repo:save({
  run_id = run2.id,
  seed   = 100,
  model  = "wai_v16.safetensors",
  output = "output/20260305/def67890/00001.png",
  recipe = '{"world":{"model":"wai_v16.safetensors","clip_skip":1}}',
})

-- save: validation
T.err("repo: save no run_id", function() repo:save({ seed = 1 }) end)

-- find
local found = repo:find(gen1.id)
T.eq("repo: find id", found.id, gen1.id)
T.eq("repo: find seed", found.seed, 42)
T.eq("repo: find model", found.model, "illustrious_v30.safetensors")

-- find: miss
T.eq("repo: find miss", repo:find("nonexistent"), nil)

-- find_by_run
local run1_gens = repo:find_by_run(run1.id)
T.eq("repo: find_by_run count", #run1_gens, 2)

-- query: by model
local q_model = repo:query({ model = "wai_v16.safetensors" })
T.eq("repo: query model count", #q_model, 1)
T.eq("repo: query model id", q_model[1].id, gen3.id)

-- query: by workspace
local q_ws = repo:query({ workspace = "gravure_klimt" })
T.eq("repo: query workspace count", #q_ws, 3)

-- query: by script
local q_script = repo:query({ script = "gravure_klimt_p2.lua" })
T.eq("repo: query script count", #q_script, 1)

-- query: limit
local q_limit = repo:query({}, { limit = 2 })
T.eq("repo: query limit", #q_limit, 2)

-- search: Lua-side JSON path
local q_json = repo:search("world.clip_skip", 2)
T.eq("repo: search json count", #q_json, 2)

-- stats: by model
local s_model = repo:stats("model")
T.ok("repo: stats model", #s_model >= 2)

-- stats: by workspace
local s_ws = repo:stats("workspace")
T.eq("repo: stats workspace count", #s_ws, 1)  -- all in gravure_klimt
T.eq("repo: stats workspace name", s_ws[1]["group"], "gravure_klimt")

-- stats: invalid group_by
T.err("repo: stats invalid", function() repo:stats("invalid") end)

-- ============================================================
-- Meta: mutable key-value per generation
-- ============================================================

-- get_meta: empty by default
local m0 = repo:get_meta(gen1.id)
T.eq("meta: empty default", next(m0), nil)

-- set_meta: simple key
repo:set_meta(gen1.id, "rating", 8.5)
local m1 = repo:get_meta(gen1.id)
T.eq("meta: rating", m1.rating, 8.5)

-- set_meta: dot-path (nested)
repo:set_meta(gen1.id, "sns.twitter.post_id", "1234567890")
repo:set_meta(gen1.id, "sns.twitter.likes", 42)
local m2 = repo:get_meta(gen1.id)
T.eq("meta: nested post_id", m2.sns.twitter.post_id, "1234567890")
T.eq("meta: nested likes", m2.sns.twitter.likes, 42)
T.eq("meta: rating preserved", m2.rating, 8.5)  -- merge, not overwrite

-- set_meta: overwrite existing key
repo:set_meta(gen1.id, "rating", 9.0)
local m3 = repo:get_meta(gen1.id)
T.eq("meta: overwrite", m3.rating, 9.0)

-- replace_meta: full replace
repo:replace_meta(gen1.id, { tags = { "gravure", "klimt" } })
local m4 = repo:get_meta(gen1.id)
T.ok("meta: replaced tags", m4.tags ~= nil)
T.eq("meta: tag count", #m4.tags, 2)
T.eq("meta: no old rating", m4.rating, nil)

-- replace_meta: validation
T.err("meta: replace non-table", function() repo:replace_meta(gen1.id, "bad") end)

-- get_meta: nonexistent gen → empty
local m_miss = repo:get_meta("nonexistent-id")
T.eq("meta: miss empty", next(m_miss), nil)

repo:close()

-- ============================================================
-- reindex: PNG scan → DB rebuild
-- ============================================================
local png_mod = require("vdsl.util.png")
local json_mod = require("vdsl.util.json")

-- Create a temp directory with a test PNG containing vdsl v2 chunk
local tmp_dir = os.tmpname() .. "_reindex_test"
os.execute("mkdir -p " .. tmp_dir)

-- Create valid 1x1 PNG via python3 PIL, then inject vdsl chunk
local function make_test_png(filepath, vdsl_data)
  os.execute(string.format(
    "python3 -c \"from PIL import Image; Image.new('RGB',(1,1),(255,255,255)).save('%s')\"",
    filepath))
  png_mod.inject_text(filepath, { vdsl = json_mod.encode(vdsl_data) })
end

local test_gen_id = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
local test_run_id = "11111111-2222-4333-8444-555555555555"
make_test_png(tmp_dir .. "/test_001.png", {
  _v = 2,
  gen_id = test_gen_id,
  run_id = test_run_id,
  script = "klimt_gravure_p1.lua",
  ts = "2026-03-05T12:00:00Z",
  world = { model = "illustrious_v30.safetensors", clip_skip = 2 },
  seed = 42,
})

-- Also create a PNG without vdsl chunk (should be skipped)
os.execute(string.format(
  "python3 -c \"from PIL import Image; Image.new('RGB',(1,1),(0,0,0)).save('%s')\"",
  tmp_dir .. "/no_vdsl.png"))

-- Reindex into fresh repo
local repo2 = Repo.new(":memory:")
local ri = repo2:reindex(tmp_dir)
T.eq("reindex: scanned", ri.scanned, 2)
T.eq("reindex: indexed", ri.indexed, 1)
T.eq("reindex: skipped", ri.skipped, 1)
T.eq("reindex: errors",  ri.errors, 0)

-- Verify record was created
local found2 = repo2:find(test_gen_id)
T.ok("reindex: found gen", found2 ~= nil)
T.eq("reindex: seed", found2.seed, 42)
T.eq("reindex: model", found2.model, "illustrious_v30.safetensors")

-- Run again → idempotent (no double insert)
local ri2 = repo2:reindex(tmp_dir)
T.eq("reindex: idempotent indexed", ri2.indexed, 0)
T.eq("reindex: idempotent skipped", ri2.skipped, 2)  -- both skipped now

repo2:close()

-- Cleanup
os.execute("rm -r " .. tmp_dir)

-- ============================================================
-- Summary
-- ============================================================
T.summary()
