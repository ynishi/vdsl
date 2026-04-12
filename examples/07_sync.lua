--- 07_sync.lua: Sync store demo via runtime/store API
-- Demonstrates: notify, status, get, pending, force (Rust bridge interface).
-- No server required. Default backend: notify (local save) + MOCK stubs.
--
-- Architecture:
--   runtime/store.lua — backend abstraction (same API as Rust bridge #12)
--   vdsl/store.lua    — domain logic (state machine, SQLite)
--
-- In production (MCP/mlua), Rust Store is injected via set_backend().
-- Here we use the default backend: notify() is real, others are MOCK.
--
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;'..package.path" examples/07_sync.lua

local fs          = require("vdsl.runtime.fs")
local sync_rt     = require("vdsl.runtime.store")

-- ============================================================
-- Setup: create temp files to simulate generated images
-- ============================================================

local tmp_dir = "/tmp/vdsl_sync_demo"
fs.mkdir(tmp_dir)

local sample_files = {
  { name = "warrior_001.png", type = "image" },
  { name = "warrior_002.png", type = "image" },
  { name = "recipe_001.json", type = "recipe" },
}

for _, f in ipairs(sample_files) do
  local path = tmp_dir .. "/" .. f.name
  if not fs.exists(path) then
    fs.write(path, string.rep("x", 64))
  end
end

-- ============================================================
-- 1. notify: register local files (real implementation)
-- ============================================================

print("=== Sync Store Demo ===\n")
print("1. notify (local file registration):")

for _, f in ipairs(sample_files) do
  local path = tmp_dir .. "/" .. f.name
  local result = sync_rt.notify(path, f.type)
  print(string.format("   %s: duplicate=%s",
    f.name, tostring(result.is_duplicate)))
end

-- Re-notify same file (idempotent)
local dup_result = sync_rt.notify(tmp_dir .. "/warrior_001.png", "image")
print(string.format("   warrior_001.png (re-notify): duplicate=%s",
  tostring(dup_result.is_duplicate)))

-- ============================================================
-- 2. MOCK methods: status, get, pending, force
--    These log WARN to stderr and return empty results.
-- ============================================================

print("\n2. MOCK methods (WARN expected on stderr):")

local status = sync_rt.status()
print(string.format("   status: total_entries=%d", status.total_entries))

local entry = sync_rt.get(tmp_dir .. "/warrior_001.png")
print(string.format("   get: %s", entry and "found" or "nil (mock)"))

local pending = sync_rt.pending("pod")
print(string.format("   pending: %d entries", #pending))

local force_result = sync_rt.force("pod")
print(string.format("   force: pushed=%d, failed=%d",
  force_result.pushed, force_result.failed))

local gen_entries = sync_rt.register_generation("gen-001", tmp_dir .. "/warrior_001.png")
print(string.format("   register_generation: %d entries", #gen_entries))

print("\n=== Sync store demo complete ===")
print("Note: status/get/pending/force/register_generation are MOCK.")
print("Full implementation requires Rust bridge (MCP/mlua backend).")
