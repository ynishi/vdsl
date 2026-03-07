--- test_sync.lua: Sync engine unit tests (in-memory DB, mock backend)
-- Tests Domain layer (vdsl.sync) with injected mock Runtime backend.
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;tests/?.lua;'..package.path" tests/test_sync.lua

local DB          = require("vdsl.runtime.db")
local Sync        = require("vdsl.sync")
local SyncBackend = require("vdsl.runtime.sync")
local T           = require("harness")

-- ============================================================
-- Mock backend (injected into Runtime layer)
-- ============================================================

local mock_log = {}
local mock_fail_next = false

local mock_backend = {
  push = function(src, dest_loc, dest_path, opts)
    mock_log[#mock_log + 1] = { op = "push", src = src, dest_loc = dest_loc, dest_path = dest_path }
    if mock_fail_next then
      mock_fail_next = false
      return false, "mock transfer error"
    end
    return true
  end,
  pull = function(src_loc, src_path, dest_path, opts)
    mock_log[#mock_log + 1] = { op = "pull", src_loc = src_loc, src_path = src_path, dest_path = dest_path }
    if mock_fail_next then
      mock_fail_next = false
      return false, "mock transfer error"
    end
    return true
  end,
  list = function(loc, path, opts)
    return {}
  end,
  exists = function(loc, path, opts)
    return true
  end,
  hash = function(filepath)
    -- Mock hash: use util/png if file is a valid PNG, else return nil
    local png = require("vdsl.runtime.png")
    return png.image_hash(filepath)
  end,
}

-- Install mock backend into Runtime layer
SyncBackend.set_backend(mock_backend)

-- ============================================================
-- PNG test helper
-- ============================================================

local function uint32_be(n)
  return string.char(
    math.floor(n / 0x1000000) % 256,
    math.floor(n / 0x10000) % 256,
    math.floor(n / 0x100) % 256,
    n % 256)
end

--- Build a minimal PNG with given IDAT data and optional tEXt chunks.
local function build_test_png(idat_data, text_chunks)
  local parts = {}
  parts[#parts + 1] = "\137PNG\r\n\26\n"
  -- IHDR (1x1 RGB)
  local ihdr = string.char(0,0,0,1, 0,0,0,1, 8, 2, 0,0,0)
  parts[#parts + 1] = uint32_be(#ihdr) .. "IHDR" .. ihdr .. "\0\0\0\0"
  -- tEXt
  if text_chunks then
    for kw, txt in pairs(text_chunks) do
      local d = kw .. "\0" .. txt
      parts[#parts + 1] = uint32_be(#d) .. "tEXt" .. d .. "\0\0\0\0"
    end
  end
  -- IDAT
  idat_data = idat_data or ""
  parts[#parts + 1] = uint32_be(#idat_data) .. "IDAT" .. idat_data .. "\0\0\0\0"
  -- IEND
  parts[#parts + 1] = uint32_be(0) .. "IEND" .. "\0\0\0\0"
  return table.concat(parts)
end

local function write_tmp_png(idat_data, text_chunks)
  local path = os.tmpname() .. ".png"
  local f = io.open(path, "wb")
  f:write(build_test_png(idat_data, text_chunks))
  f:close()
  return path
end

-- ============================================================
-- Helpers
-- ============================================================

--- Create a fresh Sync engine with in-memory DB and mock backend.
-- Domain layer receives the Runtime backend module (which has mock installed).
local function fresh_sync()
  mock_log = {}
  local db = DB.open(":memory:")
  return Sync.new(db, SyncBackend, { pod_id = "pod_test123" }), db
end

-- ============================================================
-- Tests: Backend IF (hash via Runtime layer)
-- ============================================================

do
  local png = require("vdsl.runtime.png")

  -- Same pixel data, different metadata -> same hash
  local p1 = write_tmp_png("PIXEL_DATA_AAA", { vdsl = '{"gen_id":"g1"}' })
  local p2 = write_tmp_png("PIXEL_DATA_AAA", { vdsl = '{"gen_id":"g2","extra":"field"}' })
  local h1 = SyncBackend.hash(p1)
  local h2 = SyncBackend.hash(p2)
  T.ok("backend.hash: returns string", type(h1) == "string")
  T.eq("backend.hash: same pixels = same hash", h1, h2)

  -- Different pixel data -> different hash
  local p3 = write_tmp_png("PIXEL_DATA_BBB", { vdsl = '{"gen_id":"g1"}' })
  local h3 = SyncBackend.hash(p3)
  T.ok("backend.hash: diff pixels = diff hash", h1 ~= h3)

  os.remove(p1)
  os.remove(p2)
  os.remove(p3)
end

-- ============================================================
-- Tests: png.identity (util layer, not backend)
-- ============================================================

do
  local png = require("vdsl.runtime.png")
  local p = write_tmp_png("IDENTITY_TEST", { vdsl = '{"gen_id":"gen-id-xyz"}' })
  local info, err = png.identity(p)
  T.ok("identity: returns table", info ~= nil)
  T.ok("identity: has image_hash", info.image_hash ~= nil)
  T.eq("identity: extracts gen_id", info.gen_id, "gen-id-xyz")
  T.ok("identity: has file_size", info.file_size ~= nil and info.file_size > 0)
  os.remove(p)
end

-- ============================================================
-- Tests: sync_state table creation
-- ============================================================

do
  local sync, db = fresh_sync()
  local rows = db:query("SELECT name FROM sqlite_master WHERE type='table' AND name='sync_state'")
  T.eq("sync_state table exists", #rows, 1)
  db:close()
end

-- ============================================================
-- Tests: register
-- ============================================================

do
  local sync, db = fresh_sync()

  local row = sync:register("/output/test_001.png", Sync.TYPE_IMAGE, {
    file_size = 12345,
    loc_local = Sync.PRESENT,
    loc_pod   = Sync.PENDING,
    loc_cloud = Sync.PENDING,
  })
  T.ok("register returns row", row ~= nil)
  T.eq("register file_path", row.file_path, "/output/test_001.png")
  T.eq("register file_type", row.file_type, "image")
  T.eq("register loc_local", row.loc_local, "present")
  T.eq("register loc_pod", row.loc_pod, "pending")
  T.eq("register loc_cloud", row.loc_cloud, "pending")
  T.ok("register id is set", row.id ~= nil and row.id ~= "")
  T.ok("register updated_at is set", row.updated_at ~= nil)

  -- Idempotent: re-register same path updates instead of duplicating
  local row2 = sync:register("/output/test_001.png", Sync.TYPE_IMAGE, {
    file_size = 99999,
  })
  T.eq("re-register returns same id", row2.id, row.id)

  -- Verify only 1 row in DB
  local count = db:query("SELECT count(*) as n FROM sync_state")
  T.eq("no duplicates", count[1].n, 1)

  db:close()
end

-- ============================================================
-- Tests: get / set_state
-- ============================================================

do
  local sync, db = fresh_sync()

  sync:register("/output/img.png", Sync.TYPE_IMAGE)

  local state = sync:get("/output/img.png")
  T.ok("get returns state", state ~= nil)
  T.eq("get file_type", state.file_type, "image")

  sync:set_state("/output/img.png", "cloud", Sync.PRESENT)
  local updated = sync:get("/output/img.png")
  T.eq("set_state cloud -> present", updated.loc_cloud, "present")

  sync:set_state("/output/img.png", "pod", Sync.SYNCING)
  local updated2 = sync:get("/output/img.png")
  T.eq("set_state pod -> syncing", updated2.loc_pod, "syncing")

  -- Invalid location should error
  T.err("set_state invalid loc", function()
    sync:set_state("/output/img.png", "mars", Sync.PRESENT)
  end)

  db:close()
end

-- ============================================================
-- Tests: set_error
-- ============================================================

do
  local sync, db = fresh_sync()

  sync:register("/output/err.png", Sync.TYPE_IMAGE)
  sync:set_error("/output/err.png", "connection refused")
  local state = sync:get("/output/err.png")
  T.eq("set_error stores message", state.error, "connection refused")

  sync:set_error("/output/err.png", nil)
  local cleared = sync:get("/output/err.png")
  T.eq("set_error nil clears", cleared.error, nil)

  db:close()
end

-- ============================================================
-- Tests: pending
-- ============================================================

do
  local sync, db = fresh_sync()

  sync:register("/a.png", Sync.TYPE_IMAGE, { loc_local = "present", loc_cloud = "pending" })
  sync:register("/b.png", Sync.TYPE_IMAGE, { loc_local = "present", loc_cloud = "present" })
  sync:register("/c.png", Sync.TYPE_IMAGE, { loc_local = "present", loc_cloud = "unknown" })

  local pend = sync:pending("cloud")
  T.eq("pending cloud count", #pend, 2)  -- a (pending) + c (unknown)

  local pend_local = sync:pending("local")
  -- All default to present for local (set in register)
  T.eq("pending local count", #pend_local, 0)

  db:close()
end

-- ============================================================
-- Tests: push_file (success) — verifies Domain -> Runtime dispatch
-- ============================================================

do
  local sync, db = fresh_sync()
  mock_log = {}

  sync:register("/output/push_test.png", Sync.TYPE_IMAGE, {
    loc_local = Sync.PRESENT,
    loc_cloud = Sync.PENDING,
  })

  local ok, err = sync:push_file("/output/push_test.png", "cloud", "images/push_test.png")
  T.ok("push_file success", ok)
  T.eq("push_file no error", err, nil)

  -- Verify backend was called (Domain dispatched to Runtime)
  T.eq("push_file backend called", #mock_log, 1)
  T.eq("push_file op", mock_log[1].op, "push")
  T.eq("push_file dest_loc", mock_log[1].dest_loc, "cloud")

  -- Verify state updated (Domain state machine)
  local state = sync:get("/output/push_test.png")
  T.eq("push_file cloud -> present", state.loc_cloud, "present")
  T.ok("push_file synced_at set", state.synced_at ~= nil)

  db:close()
end

-- ============================================================
-- Tests: push_file (failure) — state rollback
-- ============================================================

do
  local sync, db = fresh_sync()
  mock_log = {}
  mock_fail_next = true

  sync:register("/output/fail_test.png", Sync.TYPE_IMAGE, {
    loc_local = Sync.PRESENT,
    loc_cloud = Sync.PENDING,
  })

  local ok, err = sync:push_file("/output/fail_test.png", "cloud", "images/fail_test.png")
  T.ok("push_file failure returns false", not ok)
  T.eq("push_file failure error msg", err, "mock transfer error")

  -- State should revert to pending, error recorded
  local state = sync:get("/output/fail_test.png")
  T.eq("push_file failure -> pending", state.loc_cloud, "pending")
  T.eq("push_file failure error stored", state.error, "mock transfer error")

  db:close()
end

-- ============================================================
-- Tests: pull_file (auto-register)
-- ============================================================

do
  local sync, db = fresh_sync()
  mock_log = {}

  local ok, err = sync:pull_file("cloud", "images/remote.png", "/output/remote.png", {
    file_type = Sync.TYPE_IMAGE,
  })
  T.ok("pull_file success", ok)

  -- Should be auto-registered (Domain logic)
  local state = sync:get("/output/remote.png")
  T.ok("pull_file auto-registered", state ~= nil)
  T.eq("pull_file loc_local present", state.loc_local, "present")
  T.eq("pull_file loc_cloud present", state.loc_cloud, "present")

  db:close()
end

-- ============================================================
-- Tests: summary
-- ============================================================

do
  local sync, db = fresh_sync()

  sync:register("/a.png", Sync.TYPE_IMAGE, { loc_local = "present", loc_cloud = "pending", loc_pod = "unknown" })
  sync:register("/b.png", Sync.TYPE_IMAGE, { loc_local = "present", loc_cloud = "present", loc_pod = "present" })
  sync:register("/c.png", Sync.TYPE_RECIPE, { loc_local = "present", loc_cloud = "pending", loc_pod = "absent" })

  local s = sync:summary()
  T.eq("summary local present", s["local"].present, 3)
  T.eq("summary cloud pending", s.cloud.pending, 2)
  T.eq("summary cloud present", s.cloud.present, 1)
  T.eq("summary pod unknown", s.pod.unknown, 1)
  T.eq("summary pod present", s.pod.present, 1)
  T.eq("summary pod absent", s.pod.absent, 1)

  db:close()
end

-- ============================================================
-- Tests: list with filter
-- ============================================================

do
  local sync, db = fresh_sync()

  sync:register("/a.png", Sync.TYPE_IMAGE)
  sync:register("/b.json", Sync.TYPE_RECIPE)
  sync:register("/c.png", Sync.TYPE_IMAGE)

  local all = sync:list()
  T.eq("list all", #all, 3)

  local images = sync:list({ file_type = Sync.TYPE_IMAGE })
  T.eq("list images only", #images, 2)

  local limited = sync:list({ limit = 1 })
  T.eq("list with limit", #limited, 1)

  db:close()
end

-- ============================================================
-- Tests: register_generation
-- ============================================================

do
  local sync, db = fresh_sync()

  -- Create real temp PNG files for register_generation
  local png_path = write_tmp_png("GEN_PIXEL_DATA", { vdsl = '{"gen_id":"gen-xyz-001"}' })
  local recipe_path = os.tmpname() .. ".json"
  local rf = io.open(recipe_path, "w")
  rf:write('{"world":{"model":"test"}}')
  rf:close()

  -- Create a generation record first (FK constraint)
  db:exec("INSERT INTO workspaces (id, name, created_at) VALUES (?, ?, ?)",
    "ws-1", "test-ws", "2026-01-01T00:00:00Z")
  db:exec("INSERT INTO runs (id, workspace_id, script, created_at) VALUES (?, ?, ?, ?)",
    "run-1", "ws-1", "test.lua", "2026-01-01T00:00:00Z")
  db:exec("INSERT INTO generations (id, run_id, seed, model, output, created_at) VALUES (?, ?, ?, ?, ?, ?)",
    "gen-xyz-001", "run-1", 42, "model.safetensors", png_path, "2026-01-01T00:00:00Z")

  local rows = sync:register_generation({
    id          = "gen-xyz-001",
    output      = png_path,
    recipe_path = recipe_path,
  })
  T.eq("register_generation creates 2 rows", #rows, 2)
  T.eq("register_generation image type", rows[1].file_type, "image")
  T.eq("register_generation recipe type", rows[2].file_type, "recipe")
  T.eq("register_generation image gen_id", rows[1].gen_id, "gen-xyz-001")
  T.ok("register_generation image has hash", rows[1].file_hash ~= nil)

  os.remove(png_path)
  os.remove(recipe_path)

  db:close()
end

-- ============================================================
-- Tests: image_hash duplicate detection (Domain logic)
-- ============================================================

do
  local sync, db = fresh_sync()

  -- Register with explicit hash (simulating same image at two paths)
  local row1 = sync:register("/output/img_a.png", Sync.TYPE_IMAGE, {
    file_hash = "deadbeef12345678",
    loc_local = Sync.PRESENT,
    loc_cloud = Sync.PENDING,
  })
  T.ok("hash dup: first register ok", row1 ~= nil)
  T.eq("hash dup: first not duplicate", row1.is_duplicate, nil)

  -- Same hash, different path -> duplicate
  local row2 = sync:register("/output/img_b.png", Sync.TYPE_IMAGE, {
    file_hash = "deadbeef12345678",
    loc_local = Sync.PRESENT,
  })
  T.ok("hash dup: detected", row2.is_duplicate == true)
  T.eq("hash dup: duplicate_of", row2.duplicate_of, "/output/img_a.png")

  -- Different hash, different path -> not duplicate
  local row3 = sync:register("/output/img_c.png", Sync.TYPE_IMAGE, {
    file_hash = "cafebabe87654321",
    loc_local = Sync.PRESENT,
  })
  T.eq("hash dup: different hash not dup", row3.is_duplicate, nil)

  -- Only 2 rows in DB (row2 was duplicate, no insert)
  local count = db:query("SELECT count(*) as n FROM sync_state")
  T.eq("hash dup: 2 rows in db", count[1].n, 2)

  db:close()
end

-- ============================================================
-- Tests: metadata-only update doesn't invalidate sync
-- ============================================================

do
  local sync, db = fresh_sync()

  -- Register with hash, mark cloud as present (already synced)
  sync:register("/output/synced.png", Sync.TYPE_IMAGE, {
    file_hash = "aabb000000000001",
    loc_local = Sync.PRESENT,
    loc_cloud = Sync.PRESENT,
  })
  sync:set_state("/output/synced.png", "cloud", Sync.PRESENT)

  -- Re-register same hash (metadata update only) -> cloud stays present
  sync:register("/output/synced.png", Sync.TYPE_IMAGE, {
    file_hash = "aabb000000000001",  -- same hash
    file_size = 99999,
  })
  local state = sync:get("/output/synced.png")
  T.eq("meta update: cloud stays present", state.loc_cloud, "present")

  -- Re-register with DIFFERENT hash (pixel data changed) -> cloud becomes pending
  sync:register("/output/synced.png", Sync.TYPE_IMAGE, {
    file_hash = "ccdd000000000002",  -- different hash
    file_size = 88888,
  })
  local state2 = sync:get("/output/synced.png")
  T.eq("pixel change: cloud becomes pending", state2.loc_cloud, "pending")
  T.eq("pixel change: pod becomes pending", state2.loc_pod, "pending")

  db:close()
end

-- ============================================================
-- Tests: Sync.new validation
-- ============================================================

do
  T.err("Sync.new without db errors", function()
    Sync.new(nil, SyncBackend)
  end)

  T.err("Sync.new without backend errors", function()
    local db = DB.open(":memory:")
    Sync.new(db, nil)
  end)
end

-- ============================================================
-- Tests: Runtime set_backend validation
-- ============================================================

do
  T.err("set_backend non-table errors", function()
    SyncBackend.set_backend("not a table")
  end)

  -- Restore mock
  SyncBackend.set_backend(mock_backend)
end

-- ============================================================
-- Tests: Domain/Runtime boundary — backend is injected, not hardcoded
-- ============================================================

do
  -- Verify Domain Sync uses injected backend, not global state
  local call_log = {}
  local custom_backend = {
    push = function(src, dest_loc, dest_path, opts)
      call_log[#call_log + 1] = "custom_push"
      return true
    end,
    pull = function(...) return true end,
    list = function(...) return {} end,
    exists = function(...) return true end,
    hash = function(...) return nil end,
  }

  -- Create a Sync with custom backend module wrapper
  local custom_rt = {}
  setmetatable(custom_rt, { __index = custom_backend })
  custom_rt.set_backend = function() end  -- no-op for test

  local db = DB.open(":memory:")
  local sync = Sync.new(db, custom_rt, {})
  sync:register("/test/boundary.png", Sync.TYPE_IMAGE, {
    loc_local = Sync.PRESENT,
    loc_cloud = Sync.PENDING,
  })
  sync:push_file("/test/boundary.png", "cloud", "remote/boundary.png")
  T.eq("boundary: custom backend called", #call_log, 1)
  T.eq("boundary: correct function", call_log[1], "custom_push")
  db:close()
end

-- ============================================================

T.summary()
