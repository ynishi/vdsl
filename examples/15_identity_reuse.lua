--- 15_identity_reuse.lua: reusable identity, variations, and persistence
-- WITHOUT a dedicated Anchor entity.
--
-- The old `vdsl.anchor{}` registry was removed (see docs/entity-architecture.md).
-- Everything it did decomposes into three primitives the framework already has:
--   1. Identity   = a Subject (base text + Trait chain)
--   2. Variation  = Subject:with(...) overlay (immutable; base never mutates)
--   3. Persistence/versioning = entity:serialize() -> Data -> store -> load
--      The framework never touches storage; the application owns the backend
--      (file / SQLite / B2 / ...) and the version history.
--
-- Domain-neutral example: a vintage clockwork mechanism rendered through three
-- variations of one identity, then serialized to JSON and loaded back.
--
-- Run (compile only, no server): lua -e "package.path='lua/?.lua;lua/?/init.lua;'..package.path" examples/15_identity_reuse.lua

local vdsl   = require("vdsl")
local Entity = require("vdsl.entity")
local json   = require("vdsl.util.json")
local C      = vdsl.catalogs

-- ============================================================
-- 1. Identity = a Subject (no special type needed)
-- ============================================================
local identity = vdsl.subject("vintage clockwork brass mechanism, antique mechanical timepiece")
  :with(vdsl.trait("polished brass gears, intricate engravings", 1.0))
  :with(vdsl.trait("warm sepia tones, soft ambient light",        0.9))

-- ============================================================
-- 2. Variations = Subject:with overlays (just a plain table)
-- ============================================================
local variations = {
  wide_view    = { vdsl.trait("wide angle, full body of mechanism") },
  close_up     = { vdsl.trait("close-up of central balance wheel") },
  detail_macro = { vdsl.trait("extreme macro detail, single gear tooth visible", 1.2) },
}

--- Project the identity through a named variation -> a new Subject.
-- This is exactly what the old Anchor:render(name) did, in 4 lines of userland.
local function render_variation(name)
  local sub = identity
  for _, t in ipairs(variations[name] or {}) do
    sub = sub:with(t)   -- immutable: identity itself is never mutated
  end
  return sub
end

-- ============================================================
-- 3. Persistence = serialize -> Data -> load  (the "versioning" boundary)
-- ============================================================
-- entity:serialize() yields a plain, _type-tagged table that round-trips
-- losslessly through JSON. Where you store the string is YOUR choice — a file
-- here, but a DB row or an object-store key works identically.
local wire = json.encode(identity:serialize(), false)

local path = (os.getenv("VDSL_OUT_DIR") or "/tmp") .. "/identity_clock.json"
local wf = io.open(path, "w"); if wf then wf:write(wire); wf:close() end

-- ... later, in another process / session, load it back:
local rf = io.open(path, "r")
local loaded = rf and rf:read("*a") or wire
if rf then rf:close() end
local restored = Entity.deserialize("subject", json.decode(loaded))

assert(restored:resolve() == identity:resolve(), "identity must round-trip losslessly")

-- A "version history" is just a list of these snapshots, owned by the app:
--   versions = { v1 = wire_v1, v2 = wire_v2, ... }; current = "v2"
-- "train" = produce a new snapshot (e.g. with a freshly trained LoRA) and append.
-- "revert" = load an older snapshot. None of this belongs in the framework.

-- ============================================================
-- 4. Render each variation through the (restored) identity
-- ============================================================
local w   = vdsl.world { model = os.getenv("VDSL_MODEL") or "waiIllustrious_v16.safetensors", clip_skip = 2 }
local neg = C.quality.neg_default + C.quality.neg_anatomy

print("=== Identity Reuse Showcase ===")
print(string.format("  identity : %s", identity:resolve():sub(1, 60)))

for _, name in ipairs({ "wide_view", "close_up", "detail_macro" }) do
  local subject = render_variation(name)
  local cast    = vdsl.cast { subject = subject, negative = neg }
  local result  = vdsl.render {
    world = w, cast = { cast }, seed = 42, steps = 25, size = { 1024, 1024 },
  }
  vdsl.emit("identity_clock_" .. name, result)
  print(string.format("  %-13s %d nodes  prompt: %s...",
    name, result.graph:size(), subject:resolve():sub(1, 50)))
end

-- ============================================================
-- 5. Look reuse = Shot template (clone + with)
-- ============================================================
-- Reusing a whole *look* (the full recipe incl. Stage/ControlNet) is a Shot,
-- not a Subject. clone()/with() derive variants while keeping the look fixed.
local base_shot = vdsl.shot {
  world = w,
  cast  = { vdsl.cast { subject = render_variation("close_up"), negative = neg } },
  seed  = 42, steps = 25, size = { 1024, 1024 },
}
local reroll = base_shot:with { seed = 99 }   -- same look, new seed
print(string.format("\n  base_shot seed=%s -> reroll seed=%s (look preserved)",
  tostring(base_shot.seed), tostring(reroll.seed)))
print(string.format("  identity persisted to: %s", path))
