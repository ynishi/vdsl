--- test_sync_e2e.lua: Sync E2E tests (Phase 3).
-- Tests Store integration via mlua bridge.
-- Dir走査方式: ファイル配置→sync()→poll()→状態検証
--
-- API (non-blocking):
--   store.sync()            → task_id (string)
--   store.sync_route(s,d)   → task_id (string)
--   store.poll(task_id)     → { status, result? } | nil
--   store.status()          → SyncSummary
--   store.get(path)         → FileView | nil
--   store.pending(dest)     → Transfer[]
--
-- Run (MCP):
--   vdsl_run_script(script_file="tests/test_sync_e2e.lua")

-- harness resolution: works in both lua5.4 CLI and mlua backend.
local ok_h, T = pcall(require, "tests.harness")
if not ok_h then ok_h, T = pcall(require, "harness") end
if not ok_h or type(T) ~= "table" then
  for dir in package.path:gmatch("([^;]+)/lua/%?%.lua") do
    local path = dir .. "/tests/harness.lua"
    local f = io.open(path, "r")
    if f then
      f:close()
      T = dofile(path)
      break
    end
  end
  if not T then error("cannot load tests/harness.lua") end
end
local store = require("vdsl.runtime.store")
local fs    = require("vdsl.runtime.fs")

print("=== Sync E2E Tests (Phase 3: Non-blocking API) ===")

-- ============================================================
-- Prerequisites
-- ============================================================

local function get_cwd()
  -- mlua backend injects working_dir into package.path; extract it.
  local wd = package.path:match("^([^;]+)/lua/%?%.lua")
  if wd then return wd end
  -- Fallback: io.popen (lua5.4 CLI only; disabled in mlua sandbox)
  local ok, h = pcall(io.popen, "pwd")
  if ok and h then
    local cwd = h:read("*a"):gsub("%s+$", "")
    h:close()
    return cwd
  end
  return nil
end

local CWD = get_cwd()
if not CWD then
  print("SKIP: cannot determine working directory")
  os.exit(0)
end

local function abspath(rel)
  if rel:sub(1, 1) == "/" then return rel end
  return CWD .. "/" .. rel
end

-- Inject Rust bridge if available (must happen before detect_backend)
if _store_bridge then
  store.set_backend(_store_bridge)
end

-- Backend detection: REAL backend has location keys in status()
local function detect_backend()
  local st = store.status()
  if st.locations and next(st.locations) ~= nil then
    return "REAL"
  end
  return "MOCK"
end

local BACKEND = detect_backend()
print(string.format("Backend: %s\n", BACKEND))

-- ============================================================
-- Poll helper: sync + wait for completion
-- ============================================================

local POLL_INTERVAL = 0.5  -- seconds
local POLL_TIMEOUT  = 120  -- seconds

--- Run sync() and poll until completed/failed.
-- @return table SyncResult { scanned, scan_errors, transferred, failed, errors }
local function sync_and_wait()
  local task_id = store.sync()
  if type(task_id) ~= "string" then
    error("sync() did not return task_id string, got: " .. type(task_id))
  end
  local deadline = os.time() + POLL_TIMEOUT
  while os.time() < deadline do
    local ts = store.poll(task_id)
    if ts then
      if ts.status == "completed" then
        return ts.result or {}
      elseif ts.status == "failed" then
        error("sync task failed: " .. tostring(ts.error or "unknown"))
      end
    end
    -- Yield to async runtime so tokio::spawn'd sync task can progress.
    -- fs.sleep() is a create_async_function that yields the coroutine,
    -- allowing the current_thread runtime to poll background tasks.
    fs.sleep(POLL_INTERVAL)
  end
  error("sync task timed out after " .. POLL_TIMEOUT .. "s")
end

--- Run sync_route() and poll until completed/failed.
-- @return table SyncResult
local function sync_route_and_wait(src, dest)
  local task_id = store.sync_route(src, dest)
  if type(task_id) ~= "string" then
    error("sync_route() did not return task_id string, got: " .. type(task_id))
  end
  local deadline = os.time() + POLL_TIMEOUT
  while os.time() < deadline do
    local ts = store.poll(task_id)
    if ts then
      if ts.status == "completed" then
        return ts.result or {}
      elseif ts.status == "failed" then
        error("sync_route task failed: " .. tostring(ts.error or "unknown"))
      end
    end
    fs.sleep(POLL_INTERVAL)
  end
  error("sync_route task timed out after " .. POLL_TIMEOUT .. "s")
end

-- ============================================================
-- Test directory (inside sync_root)
-- ============================================================

local test_id  = os.time()
local test_rel = "output/test_sync_e2e_" .. test_id
local test_dir = abspath(test_rel)
fs.mkdir(test_dir)

local _seq = 0
local function unique()
  _seq = _seq + 1
  return string.format("%d_%d", test_id, _seq)
end

local function write_test_file(name, content)
  local path = test_dir .. "/" .. name
  fs.write(path, content or ("content_" .. unique()))
  return path
end

local function cleanup()
  pcall(function()
    local files = fs.ls(test_dir)
    if files then
      for _, f in ipairs(files) do
        os.remove(test_dir .. "/" .. f)
      end
    end
    os.remove(test_dir)
  end)
end

-- ============================================================
-- Group 1: API Shape (MOCK and REAL)
-- ============================================================

print("--- Group 1: API Shape ---")

do
  local r = store.status()
  T.ok("status: returns table", type(r) == "table")
  T.ok("status: has total_entries (number)", type(r.total_entries) == "number")
  T.ok("status: has total_errors (number)", type(r.total_errors) == "number")
  T.ok("status: has locations (table)", type(r.locations) == "table")
end

do
  local r = store.sync()
  T.ok("sync: returns string (task_id)", type(r) == "string")
  T.ok("sync: task_id is non-empty", r ~= "")
end

do
  local r = store.get(abspath(".vdsl/nonexistent_path"))
  T.ok("get: unregistered path returns nil", r == nil)
end

do
  local r = store.pending("cloud")
  T.ok("pending: returns table", type(r) == "table")
end

do
  local ok_call, r = pcall(store.sync_route, "local", "cloud")
  if ok_call then
    T.ok("sync_route: returns string (task_id)", type(r) == "string")
  else
    T.ok("sync_route: callable", false)
    io.stderr:write("sync_route error: " .. tostring(r) .. "\n")
  end
end

do
  local ok_call, r = pcall(store.poll, "nonexistent-task-id")
  T.ok("poll: callable with unknown id", ok_call)
  -- poll with unknown id should return nil
  T.ok("poll: returns nil for unknown task_id", r == nil)
end

-- ============================================================
-- Group 2: DI (set_backend)
-- ============================================================

print("\n--- Group 2: DI ---")

do
  local called = false
  local custom = {
    status = function() return { total_entries = 42, total_errors = 0, locations = {} } end,
    sync = function() called = true; return "custom-task-id" end,
    sync_route = function() return "custom-route-task-id" end,
    poll = function() return { status = "completed", result = { scanned = 0, transferred = 0, failed = 0, errors = {} } } end,
    get = function() return nil end,
    pending = function() return {} end,
  }
  store.set_backend(custom)

  store.sync()
  T.ok("DI: custom sync called", called)

  local st = store.status()
  T.eq("DI: custom status.total_entries", st.total_entries, 42)

  -- Reset to default
  store.set_backend(nil)
  local st2 = store.status()
  T.eq("DI: reset to default, total_entries=0", st2.total_entries, 0)

  -- Invalid backend types
  local ok1 = pcall(store.set_backend, "not_a_table")
  T.ok("DI: string backend rejected", not ok1)

  local ok2 = pcall(store.set_backend, 123)
  T.ok("DI: number backend rejected", not ok2)
end

-- ============================================================
-- Group 3: vdsl facade
-- ============================================================

print("\n--- Group 3: Facade ---")

do
  local vdsl = require("vdsl")

  T.ok("facade: vdsl.store is table", type(vdsl.store) == "table")

  local st = vdsl.store.status()
  T.ok("facade: status returns table", type(st) == "table")
  T.ok("facade: status.total_entries is number", type(st.total_entries) == "number")

  -- set_store_backend via facade
  local flag = false
  vdsl.set_store_backend({
    status = function() return { total_entries = 99, total_errors = 0, locations = {} } end,
    sync = function() flag = true; return "facade-task-id" end,
    sync_route = function() return "facade-route-task-id" end,
    poll = function() return { status = "completed", result = {} } end,
    get = function() return nil end,
    pending = function() return {} end,
  })
  vdsl.store.sync()
  T.ok("facade: set_store_backend injects custom", flag)

  vdsl.set_store_backend(nil) -- restore
end

-- ============================================================
-- Group 4: Store Integration (REAL backend only)
-- S-01 ~ S-10 (Dir走査方式, non-blocking)
-- ============================================================

print("\n--- Group 4: Store Integration ---")

-- Restore Store backend after DI tests reset it to MOCK.
-- _store_bridge is the global table injected by mlua_runtime.rs.
if _store_bridge then
  store.set_backend(_store_bridge)
end

if BACKEND == "REAL" then

  -- S-01: sync → status
  -- sync_rootにファイル配置→sync()→poll()→status()
  do
    local name = "s01_" .. unique() .. ".txt"
    local content = "S01_content_" .. unique()
    local path = write_test_file(name, content)

    local result = sync_and_wait()
    T.ok("S-01: sync result is table", type(result) == "table")

    local st = store.status()
    T.ok("S-01: total_entries >= 1", st.total_entries >= 1)

    local has_local = st.locations and st.locations["local"] ~= nil
    T.ok("S-01: locations has 'local'", has_local)
    if has_local then
      T.ok("S-01: local.present >= 1", st.locations["local"].present >= 1)
    end

    _G._s01 = { path = path, name = name }
  end

  -- S-02: sync → get
  -- sync()後にget(path) → entry返却、file_hash非nil
  do
    local entry = store.get(_G._s01.path)
    T.ok("S-02: get returns entry", entry ~= nil)
    if entry then
      T.ok("S-02: entry has file_hash", entry.file_hash ~= nil)
    end
  end

  -- S-03: sync 同一ファイル変更
  -- ファイル内容変更→sync() → hash変更検出
  do
    local name = "s03_" .. unique() .. ".txt"
    local path = write_test_file(name, "original_" .. unique())

    sync_and_wait()
    local entry1 = store.get(path)
    T.ok("S-03: first sync creates entry", entry1 ~= nil)
    local hash1 = entry1 and entry1.file_hash

    -- Modify content
    fs.write(path, "modified_" .. unique())
    sync_and_wait()
    local entry2 = store.get(path)
    T.ok("S-03: entry exists after modify", entry2 ~= nil)
    local hash2 = entry2 and entry2.file_hash

    T.ok("S-03: hash changed after modification", hash1 ~= hash2)
  end

  -- S-04: sync 同一内容別パス → 同一hash検出
  -- is_duplicate is a transient PutResult field (not persisted in TrackedFile).
  -- Duplicate detection is verified by comparing file_hash values instead.
  do
    local dup_content = "identical_dup_test_" .. unique()
    local p1 = write_test_file("s04_orig_" .. unique() .. ".txt", dup_content)
    local p2 = write_test_file("s04_copy_" .. unique() .. ".txt", dup_content)

    sync_and_wait()

    local e1 = store.get(p1)
    local e2 = store.get(p2)
    T.ok("S-04: original entry exists", e1 ~= nil)
    T.ok("S-04: copy entry exists", e2 ~= nil)

    if e1 and e2 then
      T.ok("S-04: both have file_hash", e1.file_hash ~= nil and e2.file_hash ~= nil)
      T.eq("S-04: same content produces same hash", e1.file_hash, e2.file_hash)
    end
  end

  -- S-05: sync → pending確認
  -- sync()後 pending(cloud) → pending=0（全転送された）
  do
    local name = "s05_" .. unique() .. ".txt"
    write_test_file(name, "pending_test_" .. unique())

    sync_and_wait()

    local pending = store.pending("cloud")
    T.ok("S-05: pending returns table", type(pending) == "table")
    T.eq("S-05: pending=0 after sync (all transferred)", #pending, 0)
  end

  -- S-06: sync_route失敗時
  -- 存在しないルートへsync_route → エラー返却
  do
    local ok_call, result = pcall(sync_route_and_wait, "local", "nonexistent")
    if not ok_call then
      -- Error raised is acceptable for invalid route
      T.ok("S-06: error raised for unknown dest", true)
      io.stderr:write("S-06: error: " .. tostring(result) .. "\n")
    else
      T.ok("S-06: returns table", type(result) == "table")
      T.eq("S-06: transferred=0 for unknown dest", result.transferred or 0, 0)
    end
  end

  -- S-07: sync_route明示指定
  -- sync_route("local", "cloud") → 指定ルートのみ転送
  do
    local name = "s07_" .. unique() .. ".txt"
    write_test_file(name, "sync_route_test_" .. unique())

    -- First, let sync() detect the file via Dir走査
    sync_and_wait()

    -- Explicit route
    local result = sync_route_and_wait("local", "cloud")
    T.ok("S-07: sync_route result is table", type(result) == "table")
    T.ok("S-07: has transferred field", type(result.transferred) == "number")
  end

  -- S-08: status各フィールド検証
  do
    local st = store.status()
    T.ok("S-08: total_entries is number", type(st.total_entries) == "number")
    T.ok("S-08: total_errors is number", type(st.total_errors) == "number")
    T.ok("S-08: locations is table", type(st.locations) == "table")

    -- Verify location structure (all 5 fields)
    for loc_name, counts in pairs(st.locations) do
      T.ok("S-08: '" .. loc_name .. "' is table", type(counts) == "table")
      T.ok("S-08: " .. loc_name .. ".present is number",
        type(counts.present) == "number")
      T.ok("S-08: " .. loc_name .. ".pending is number",
        type(counts.pending) == "number")
      T.ok("S-08: " .. loc_name .. ".failed is number",
        type(counts.failed) == "number")
      T.ok("S-08: " .. loc_name .. ".absent is number",
        type(counts.absent) == "number")
    end
  end

  -- S-09: sync 同一内容再実行 → hash不変
  do
    local name = "s09_" .. unique() .. ".txt"
    local path = write_test_file(name, "s09_immutable_" .. unique())

    sync_and_wait()  -- 1回目: 検出+登録
    local e1 = store.get(path)
    T.ok("S-09: entry exists after first sync", e1 ~= nil)
    local hash1 = e1 and e1.file_hash

    sync_and_wait()  -- 2回目: 変更なし
    local e2 = store.get(path)
    T.ok("S-09: entry exists after second sync", e2 ~= nil)
    local hash2 = e2 and e2.file_hash

    T.eq("S-09: hash unchanged on re-sync", hash1, hash2)
  end

  -- S-10: SyncResult分離検証
  -- poll().result の全フィールドが正しい型であること
  do
    local name = "s10_" .. unique() .. ".txt"
    write_test_file(name, "s10_content_" .. unique())

    local result = sync_and_wait()
    T.ok("S-10: scanned is number", type(result.scanned) == "number")
    -- scan_errors is omitted from JSON when empty (serde skip_serializing_if)
    T.ok("S-10: scan_errors is table or nil", result.scan_errors == nil or type(result.scan_errors) == "table")
    T.ok("S-10: transferred is number", type(result.transferred) == "number")
    T.ok("S-10: failed is number", type(result.failed) == "number")
    T.ok("S-10: errors is table", type(result.errors) == "table")
    T.ok("S-10: scanned >= 1", result.scanned >= 1)
  end

else
  print("  (skipped: MOCK backend, Store not injected)")
  print("  To run: vdsl_run_script(script_file='tests/test_sync_e2e.lua')")
end

-- ============================================================
-- Cleanup
-- ============================================================

cleanup()

-- ============================================================
-- Summary
-- ============================================================

T.summary()
