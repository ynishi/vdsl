--- test_sync_smoke.lua: Minimal sync bridge smoke test.
-- Tests each step independently to isolate failure point.
-- Run: vdsl_run_script(script_file="tests/test_sync_smoke.lua")

print("STEP 1: require vdsl.runtime.store")
local ok1, store = pcall(require, "vdsl.runtime.store")
if not ok1 then
  print("FAIL: require error: " .. tostring(store))
  os.exit(1)
end
print("  OK")

print("STEP 2: check _store_bridge global")
if _store_bridge then
  print("  OK: _store_bridge is " .. type(_store_bridge))
  store.set_backend(_store_bridge)
else
  print("  SKIP: _store_bridge is nil (MOCK mode)")
end

print("STEP 3: store.status()")
local ok3, st = pcall(store.status)
if not ok3 then
  print("FAIL: status() error: " .. tostring(st))
  os.exit(1)
end
print("  OK: total_entries=" .. tostring(st.total_entries))

print("STEP 4: store.sync()")
local ok4, task_id = pcall(store.sync)
if not ok4 then
  print("FAIL: sync() error: " .. tostring(task_id))
  os.exit(1)
end
print("  OK: task_id=" .. tostring(task_id))

print("STEP 5: store.get (nonexistent)")
local ok5, entry = pcall(store.get, "/tmp/nonexistent_path_12345")
if not ok5 then
  print("FAIL: get() error: " .. tostring(entry))
  os.exit(1)
end
print("  OK: entry=" .. tostring(entry))

print("STEP 6: store.pending('cloud')")
local ok6, pend = pcall(store.pending, "cloud")
if not ok6 then
  print("FAIL: pending() error: " .. tostring(pend))
  os.exit(1)
end
print("  OK: count=" .. tostring(#pend))

print("\nALL STEPS PASSED")
