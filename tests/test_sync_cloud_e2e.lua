--- test_sync_cloud_e2e.lua: Local ↔ Cloud (B2) E2E tests.
-- Validates the full sync lifecycle WITHOUT Pod:
--   ファイル配置 → force() → B2到達 → status遷移
--
-- Dir走査方式: force()がsync_root走査→未登録/変更ファイル検出→全拠点転送
--
-- Requires:
--   - Store injected (mlua backend)
--   - B2 credentials (VDSL_B2_KEY_ID, VDSL_B2_KEY, VDSL_B2_BUCKET)
--   - rclone installed locally
--
-- Run (MCP):
--   vdsl_run_script(script_file="tests/test_sync_cloud_e2e.lua")

local ok_h, T = pcall(require, "tests.harness")
if not ok_h then T = require("harness") end
local sync_rt = require("vdsl.runtime.store")
local fs      = require("vdsl.runtime.fs")

print("=== Local ↔ Cloud (B2) E2E Tests (Dir走査方式) ===\n")

-- ============================================================
-- Prerequisites
-- ============================================================

local function get_cwd()
  local h = io.popen("pwd")
  if not h then return nil end
  local cwd = h:read("*a"):gsub("%s+$", "")
  h:close()
  return cwd
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

-- Check rclone available
local function check_rclone()
  local h = io.popen("which rclone 2>/dev/null")
  if not h then return false end
  local r = h:read("*a"):gsub("%s+$", "")
  h:close()
  return r ~= ""
end

-- Inject Rust bridge if available (must happen before check_real_backend)
if _sync_bridge then
  sync_rt.set_backend(_sync_bridge)
end

-- Check Store backend (not MOCK)
local function check_real_backend()
  local st = sync_rt.status()
  if st.locations and st.locations["cloud"] then
    return true
  end
  return false
end

if not check_rclone() then
  print("SKIP: rclone not installed")
  os.exit(0)
end

if not check_real_backend() then
  print("SKIP: Store not injected (MOCK backend)")
  os.exit(0)
end

print("Prerequisites OK: rclone + Store(REAL)\n")

-- ============================================================
-- B2 helpers (rclone CLI)
-- ============================================================

local b2_key_id = os.getenv("VDSL_B2_KEY_ID")
local b2_key    = os.getenv("VDSL_B2_KEY")
local b2_bucket = os.getenv("VDSL_B2_BUCKET")

if not (b2_key_id and b2_key and b2_bucket) then
  print("SKIP: B2 credentials not set")
  os.exit(0)
end

local b2_remote = string.format(":b2,account=%s,key=%s:%s", b2_key_id, b2_key, b2_bucket)
local b2_root   = "vdsl/output"  -- must match Store remote_root

--- Check if a file exists on B2. Returns size or nil.
local function b2_exists(relative_path)
  local cmd = string.format(
    'rclone size "%s/%s/%s" --json 2>/dev/null',
    b2_remote, b2_root, relative_path)
  local h = io.popen(cmd)
  if not h then return nil end
  local out = h:read("*a")
  h:close()
  local bytes = out:match('"bytes"%s*:%s*(%d+)')
  if bytes then return tonumber(bytes) end
  return nil
end

--- Read file content from B2. Returns string or nil.
local function b2_cat(relative_path)
  local cmd = string.format(
    'rclone cat "%s/%s/%s" 2>/dev/null',
    b2_remote, b2_root, relative_path)
  local h = io.popen(cmd)
  if not h then return nil end
  local out = h:read("*a")
  h:close()
  if out == "" then return nil end
  return out
end

--- Delete a file from B2.
local function b2_delete(relative_path)
  local cmd = string.format(
    'rclone deletefile "%s/%s/%s" 2>/dev/null',
    b2_remote, b2_root, relative_path)
  os.execute(cmd)
end

-- ============================================================
-- Test directory (inside sync_root)
-- ============================================================

local test_id  = os.time()
local test_rel = ".vdsl/cloud_e2e_" .. test_id
local test_dir = abspath(test_rel)
fs.mkdir(test_dir)

-- Track created B2 files for cleanup
local b2_cleanup = {}

local _seq = 0
local function unique()
  _seq = _seq + 1
  return string.format("%d_%d", test_id, _seq)
end

-- ============================================================
-- LC-01: ファイル配置 → force() → entry存在確認
-- ============================================================

print("--- LC-01: file placement + force → entry check ---")
do
  local name = "lc01_" .. unique() .. ".txt"
  local content = "LC-01 content " .. unique()
  local path = test_dir .. "/" .. name
  fs.write(path, content)

  local fr = sync_rt.force()
  T.ok("LC-01: force returns table", type(fr) == "table")

  local entry = sync_rt.get(path)
  T.ok("LC-01: get returns entry", entry ~= nil)
  if entry then
    T.eq("LC-01: file_type is asset", entry.file_type, "asset")
  end

  -- After force(), cloud should be present (pushed during force)
  if entry and entry.locations then
    T.eq("LC-01: local=present", entry.locations["local"], "present")
    -- cloud may be "present" (push succeeded) or "pending" (push failed)
    local cloud_state = entry.locations["cloud"]
    T.ok("LC-01: cloud state exists", cloud_state ~= nil)
    io.stderr:write("LC-01: cloud=" .. tostring(cloud_state) .. "\n")
  else
    T.ok("LC-01: entry has locations", false)
  end

  -- Store for subsequent tests
  _G._lc01 = { path = path, name = name, content = content,
                relative = test_rel .. "/" .. name }
end

-- ============================================================
-- LC-02: B2にファイル到達確認
-- ============================================================

print("\n--- LC-02: B2 file arrival ---")
do
  local size = b2_exists(_G._lc01.relative)
  T.ok("LC-02: file exists on B2", size ~= nil)
  T.ok("LC-02: size > 0", (size or 0) > 0)

  local remote_content = b2_cat(_G._lc01.relative)
  T.eq("LC-02: content matches", remote_content, _G._lc01.content)

  table.insert(b2_cleanup, _G._lc01.relative)
end

-- ============================================================
-- LC-03: status → cloud=present
-- ============================================================

print("\n--- LC-03: status after force ---")
do
  local entry = sync_rt.get(_G._lc01.path)
  T.ok("LC-03: get returns entry", entry ~= nil)
  if entry and entry.locations then
    T.eq("LC-03: local=present", entry.locations["local"], "present")
    T.eq("LC-03: cloud=present", entry.locations["cloud"], "present")
  else
    T.ok("LC-03: entry has locations", false)
  end
end

-- ============================================================
-- LC-04: ファイル変更 → force() → hash変更 + cloud再転送
-- ============================================================

print("\n--- LC-04: modify + force ---")
do
  local new_content = "LC-04 modified " .. unique()
  fs.write(_G._lc01.path, new_content)

  local fr = sync_rt.force()
  T.ok("LC-04: force returns table", type(fr) == "table")

  local entry = sync_rt.get(_G._lc01.path)
  if entry and entry.locations then
    T.eq("LC-04: local=present", entry.locations["local"], "present")
    -- After force with modified file, cloud should be re-pushed
    T.eq("LC-04: cloud=present (re-pushed)", entry.locations["cloud"], "present")
  else
    T.ok("LC-04: entry has locations", false)
  end

  _G._lc04_content = new_content
end

-- ============================================================
-- LC-05: B2 content matches updated version
-- ============================================================

print("\n--- LC-05: B2 content updated ---")
do
  local remote_content = b2_cat(_G._lc01.relative)
  T.eq("LC-05: B2 has updated content", remote_content, _G._lc04_content)
end

-- ============================================================
-- LC-06: 0-byte file
-- ============================================================

print("\n--- LC-06: 0-byte file ---")
do
  local name = "lc06_empty_" .. unique() .. ".txt"
  local rel  = test_rel .. "/" .. name
  local path = test_dir .. "/" .. name
  fs.write(path, "")

  local fr = sync_rt.force()

  -- Check our empty file was pushed (not in errors)
  local failed = false
  if fr.errors then
    for _, e in ipairs(fr.errors) do
      if type(e) == "table" and e.path and e.path:find(rel, 1, true) then
        failed = true
        io.stderr:write("LC-06: empty file failed: " .. tostring(e.error) .. "\n")
      end
    end
  end
  T.ok("LC-06: empty file push not failed", not failed)

  local size = b2_exists(rel)
  T.ok("LC-06: empty file exists on B2", size ~= nil)
  T.eq("LC-06: size is 0", size, 0)

  table.insert(b2_cleanup, rel)
end

-- ============================================================
-- LC-07: 日本語ファイル名
-- ============================================================

print("\n--- LC-07: Japanese filename ---")
do
  local name = "テスト画像_" .. unique() .. ".txt"
  local rel  = test_rel .. "/" .. name
  local path = test_dir .. "/" .. name
  local content = "日本語ファイル名テスト " .. unique()
  fs.write(path, content)

  local fr = sync_rt.force()

  local failed = false
  if fr.errors then
    for _, e in ipairs(fr.errors) do
      if type(e) == "table" and e.path and e.path:find(name, 1, true) then
        failed = true
        io.stderr:write("LC-07: JP file failed: " .. tostring(e.error) .. "\n")
      end
    end
  end
  T.ok("LC-07: JP filename push not failed", not failed)

  local remote_content = b2_cat(rel)
  T.eq("LC-07: B2 content matches (UTF-8 safe)", remote_content, content)

  table.insert(b2_cleanup, rel)
end

-- ============================================================
-- LC-08: force_route to unregistered destination
-- ============================================================

print("\n--- LC-08: force_route to unregistered dest ---")
do
  local ok_call, fr = pcall(sync_rt.force_route, "local", "nonexistent-dest")
  if ok_call then
    T.eq("LC-08: pushed=0 for unknown dest", fr.pushed, 0)
    T.eq("LC-08: failed=0 for unknown dest", fr.failed, 0)
  else
    -- Error is also acceptable
    T.ok("LC-08: error raised for unknown dest", true)
    io.stderr:write("LC-08: error: " .. tostring(fr) .. "\n")
  end
end

-- ============================================================
-- LC-09: force_route(local, cloud) 明示的ルート
-- ============================================================

print("\n--- LC-09: force_route(local, cloud) ---")
do
  local name = "lc09_route_" .. unique() .. ".txt"
  local rel  = test_rel .. "/" .. name
  local path = test_dir .. "/" .. name
  local content = "force_route test " .. unique()
  fs.write(path, content)

  -- First, let force() detect the file
  sync_rt.force()

  -- Then explicit route push
  local fr = sync_rt.force_route("local", "cloud")
  T.ok("LC-09: force_route returns table", type(fr) == "table")
  T.ok("LC-09: has pushed field", type(fr.pushed) == "number")

  -- Verify on B2
  local remote_content = b2_cat(rel)
  T.eq("LC-09: B2 content via force_route", remote_content, content)

  table.insert(b2_cleanup, rel)
end

-- ============================================================
-- LC-10: 未変更ファイル再force → pushed=0 (E-06)
-- ============================================================

print("\n--- LC-10: unchanged file re-force ---")
do
  -- All files already pushed by previous tests.
  -- Re-force should detect no changes → pushed=0
  local fr = sync_rt.force()
  T.eq("LC-10: pushed=0 (no changes)", fr.pushed, 0)
end

-- ============================================================
-- Cleanup: local files + B2 test files
-- ============================================================

print("\n--- Cleanup ---")
do
  -- Local cleanup
  pcall(function()
    local files = fs.ls(test_dir)
    if files then
      for _, f in ipairs(files) do
        os.remove(test_dir .. "/" .. f)
      end
    end
    os.remove(test_dir)
  end)

  -- B2 cleanup
  for _, rel in ipairs(b2_cleanup) do
    b2_delete(rel)
  end
  print(string.format("  Cleaned %d B2 files", #b2_cleanup))
end

-- ============================================================
-- Summary
-- ============================================================

T.summary()
