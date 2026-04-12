--- test_sync_3loc_e2e.lua: 3拠点同期 E2E テスト
-- Storeが Local/Pod/Cloud の3拠点同期を実現できているか検証。
-- Dir走査方式: ファイル配置→force()→状態検証
--
-- 2点間ペア (A: Local↔Cloud, B: Local↔Pod, C: Pod↔Cloud) + D: 3点統合。
--
-- 検証原則: Store の status()/get() だけで判定しない。
--   - Cloud (B2): rclone cat/size でファイル内容を直接確認
--   - Pod: vdsl_exec ls/md5sum でファイル存在を直接確認
--   - Local: io.open でファイル読み取り
--
-- Requires:
--   - Store injected (mlua backend)
--   - B2 credentials (VDSL_B2_KEY_ID, VDSL_B2_KEY, VDSL_B2_BUCKET)
--   - rclone installed locally
--   - Pod起動中 (Phase B, C, D)
--
-- Run (MCP):
--   vdsl_run_script(script_file="tests/test_sync_3loc_e2e.lua")

local ok_h, T = pcall(require, "tests.harness")
if not ok_h then T = require("harness") end
local sync_rt = require("vdsl.runtime.store")
local fs      = require("vdsl.runtime.fs")

print("=== 3-Location Sync E2E Tests (Dir走査方式) ===\n")

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

-- Inject Rust bridge if available (must happen before check_real_backend)
if _sync_bridge then
  sync_rt.set_backend(_sync_bridge)
end

-- Check Store backend (not MOCK)
local function check_real_backend()
  local st = sync_rt.status()
  if st.locations and next(st.locations) ~= nil then
    return true
  end
  return false
end

if not check_real_backend() then
  print("SKIP: Store not injected (MOCK backend)")
  os.exit(0)
end

-- B2 credentials
local b2_key_id = os.getenv("VDSL_B2_KEY_ID")
local b2_key    = os.getenv("VDSL_B2_KEY")
local b2_bucket = os.getenv("VDSL_B2_BUCKET")

if not (b2_key_id and b2_key and b2_bucket) then
  print("SKIP: B2 credentials not set")
  os.exit(0)
end

local b2_remote = string.format(":b2,account=%s,key=%s:%s", b2_key_id, b2_key, b2_bucket)
local b2_root   = "vdsl/output"

print("Prerequisites OK: Store(REAL) + B2 credentials\n")

-- ============================================================
-- Helpers
-- ============================================================

local test_id  = os.time()
local test_rel = ".vdsl/3loc_e2e_" .. test_id
local test_dir = abspath(test_rel)
fs.mkdir(test_dir)

local b2_cleanup = {}

local _seq = 0
local function unique()
  _seq = _seq + 1
  return string.format("%d_%d", test_id, _seq)
end

--- B2: check file content via rclone cat (Sync以外の検証)
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

--- B2: check file exists and size (Sync以外の検証)
local function b2_size(relative_path)
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

--- B2: delete file
local function b2_delete(relative_path)
  local cmd = string.format(
    'rclone deletefile "%s/%s/%s" 2>/dev/null',
    b2_remote, b2_root, relative_path)
  os.execute(cmd)
end

--- Local: read file content (Sync以外の検証)
local function local_read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local c = f:read("*a")
  f:close()
  return c
end

-- ============================================================
-- Phase A: Local ↔ Cloud (2点間)
-- ============================================================

print("--- Phase A: Local ↔ Cloud ---")

local a_name = "3loc_a_" .. unique() .. ".txt"
local a_content = "Phase_A_content_" .. unique()
local a_rel = test_rel .. "/" .. a_name
local a_path = test_dir .. "/" .. a_name
fs.write(a_path, a_content)

-- A-01: ファイル配置 → force() → entry検証
do
  local fr = sync_rt.force()
  T.ok("A-01: force returns table", type(fr) == "table")

  local entry = sync_rt.get(a_path)
  T.ok("A-01: get returns entry", entry ~= nil)

  local has_cloud = entry and entry.locations and entry.locations["cloud"] ~= nil
  T.ok("A-01: locations has 'cloud'", has_cloud)

  local has_local = entry and entry.locations and entry.locations["local"] ~= nil
  T.ok("A-01: locations has 'local'", has_local)
  if has_local then
    T.eq("A-01: local=present", entry.locations["local"], "present")
  end
end

-- A-02: rclone cat でB2上ファイル内容を直接確認 (Sync以外の検証)
do
  local remote_content = b2_cat(a_rel)
  T.eq("A-02: B2 content matches (rclone cat)", remote_content, a_content)
  table.insert(b2_cleanup, a_rel)
end

-- A-03: Store status でcloud=present確認
do
  local entry = sync_rt.get(a_path)
  T.ok("A-03: entry exists", entry ~= nil)
  if entry and entry.locations then
    T.eq("A-03: local=present", entry.locations["local"], "present")
    T.eq("A-03: cloud=present", entry.locations["cloud"], "present")
  end
end

-- ============================================================
-- Phase B: Local ↔ Pod (2点間)
-- Storeが"pod"をremoteとして認識しているか検証。
-- ============================================================

print("\n--- Phase B: Local ↔ Pod ---")

local b_name = "3loc_b_" .. unique() .. ".txt"
local b_content = "Phase_B_content_" .. unique()
local b_rel = test_rel .. "/" .. b_name
local b_path = test_dir .. "/" .. b_name
fs.write(b_path, b_content)

-- B-01: force() → entry.locations に "pod" が存在するか
do
  sync_rt.force()

  local entry = sync_rt.get(b_path)
  T.ok("B-01: get returns entry", entry ~= nil)

  local has_pod = entry and entry.locations and entry.locations["pod"] ~= nil
  T.ok("B-01: locations has 'pod'", has_pod)

  if has_pod then
    io.stderr:write("B-01: pod=" .. tostring(entry.locations["pod"]) .. "\n")
  else
    io.stderr:write("B-01: INFO: 'pod' not in locations. Registered remotes: ")
    if entry and entry.locations then
      for k, v in pairs(entry.locations) do
        io.stderr:write(k .. "=" .. tostring(v) .. " ")
      end
    end
    io.stderr:write("\n")
  end
end

-- B-02: Pod上でファイルが存在するか (Sync以外の検証)
do
  local entry = sync_rt.get(b_path)
  local pod_state = entry and entry.locations and entry.locations["pod"]
  if pod_state == "present" then
    -- Storeはpresentと言っているが、実際にPod上にファイルがあるかは
    -- vdsl_exec("ls ...") で確認が必要。ここでは検証手段がないため記録のみ。
    io.stderr:write("B-02: WARN: Store says pod=present but cannot verify via exec\n")
    T.ok("B-02: pod=present (Store claims, unverified)", true)
  else
    T.ok("B-02: pod=present after force", false)
    io.stderr:write("B-02: INFO: pod state = " .. tostring(pod_state) .. " (not 'present')\n")
  end
end

-- ============================================================
-- Phase C: Pod ↔ Cloud (2点間)
-- ============================================================

print("\n--- Phase C: Pod ↔ Cloud ---")

-- C-01: Store status() で "pod" locationが存在するか
do
  local st = sync_rt.status()
  T.ok("C-01: status returns table", type(st) == "table")

  local has_pod_loc = st.locations and st.locations["pod"] ~= nil
  T.ok("C-01: status.locations has 'pod'", has_pod_loc)

  if has_pod_loc then
    io.stderr:write("C-01: pod location counts: present=" ..
      tostring(st.locations["pod"].present) .. " pending=" ..
      tostring(st.locations["pod"].pending) .. "\n")
  else
    io.stderr:write("C-01: INFO: 'pod' not in status.locations. Available: ")
    if st.locations then
      for k, _ in pairs(st.locations) do io.stderr:write(k .. " ") end
    end
    io.stderr:write("\n")
  end
end

-- C-02: pending("pod") が entries を返すか
do
  local ok_call, pending = pcall(sync_rt.pending, "pod")
  if ok_call and type(pending) == "table" then
    T.ok("C-02: pending('pod') returns table", true)
    io.stderr:write("C-02: pending('pod') count = " .. tostring(#pending) .. "\n")
  else
    T.ok("C-02: pending('pod') succeeds", false)
    io.stderr:write("C-02: INFO: pending('pod') error: " .. tostring(pending) .. "\n")
  end
end

-- ============================================================
-- Phase D: 3点統合
-- force() → 3拠点すべてpresent
-- ============================================================

print("\n--- Phase D: 3-Location Integration ---")

local d_name = "3loc_d_" .. unique() .. ".txt"
local d_content = "Phase_D_content_" .. unique()
local d_rel = test_rel .. "/" .. d_name
local d_path = test_dir .. "/" .. d_name
fs.write(d_path, d_content)

-- D-01: force() → locations に local, cloud, pod すべて存在するか
do
  local fr = sync_rt.force()
  io.stderr:write("D-01: force(): pushed=" .. tostring(fr.pushed) ..
    " failed=" .. tostring(fr.failed) .. "\n")

  local entry = sync_rt.get(d_path)
  T.ok("D-01: entry exists", entry ~= nil)

  local has_local = entry and entry.locations and entry.locations["local"] ~= nil
  local has_cloud = entry and entry.locations and entry.locations["cloud"] ~= nil
  local has_pod   = entry and entry.locations and entry.locations["pod"] ~= nil

  T.ok("D-01: locations has 'local'", has_local)
  T.ok("D-01: locations has 'cloud'", has_cloud)
  T.ok("D-01: locations has 'pod'", has_pod)

  io.stderr:write("D-01: locations = {")
  if entry and entry.locations then
    for k, v in pairs(entry.locations) do
      io.stderr:write(" " .. k .. "=" .. tostring(v))
    end
  end
  io.stderr:write(" }\n")
end

-- D-02: 3拠点present確認
do
  local entry = sync_rt.get(d_path)
  local local_ok = entry and entry.locations and entry.locations["local"] == "present"
  local cloud_ok = entry and entry.locations and entry.locations["cloud"] == "present"
  local pod_ok   = entry and entry.locations and entry.locations["pod"] == "present"

  T.ok("D-02: local=present", local_ok)
  T.ok("D-02: cloud=present", cloud_ok)
  T.ok("D-02: pod=present", pod_ok)
end

-- D-03: Sync以外の手段で3拠点を直接確認
do
  -- Local: ファイル読み取り
  local local_content = local_read(d_path)
  T.eq("D-03: local file content matches (io.open)", local_content, d_content)

  -- Cloud: rclone cat
  local cloud_content = b2_cat(d_rel)
  T.eq("D-03: cloud file content matches (rclone cat)", cloud_content, d_content)
  table.insert(b2_cleanup, d_rel)

  -- Pod: ここでは検証手段なし。Store外の確認にはvdsl_exec必要。
  local entry = sync_rt.get(d_path)
  local pod_state = entry and entry.locations and entry.locations["pod"]
  if pod_state == "present" then
    io.stderr:write("D-03: WARN: pod=present per Store, but no exec verification possible here\n")
    T.ok("D-03: pod file verified via exec (NOT Store)", false)
  else
    T.ok("D-03: pod file verified via exec", false)
    io.stderr:write("D-03: pod state = " .. tostring(pod_state) .. "\n")
  end
end

-- ============================================================
-- Cleanup
-- ============================================================

print("\n--- Cleanup ---")
do
  pcall(function()
    local files = fs.ls(test_dir)
    if files then
      for _, f in ipairs(files) do
        os.remove(test_dir .. "/" .. f)
      end
    end
    os.remove(test_dir)
  end)

  for _, rel in ipairs(b2_cleanup) do
    b2_delete(rel)
  end
  print(string.format("  Cleaned %d B2 files", #b2_cleanup))
end

-- ============================================================
-- Summary
-- ============================================================

T.summary()
