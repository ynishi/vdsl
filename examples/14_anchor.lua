--- 14_anchor.lua: Anchor entity — identity fixation + variation registry
-- Demonstrates: vdsl.anchor.from, Registry:current/:latest, Anchor:render,
--               vdsl.emit("anchor", reg) JSON serialization,
--               Cast{anchor=A} auto-resolution (assets passthrough).
-- Domain-neutral example: a vintage clockwork mechanism rendered through
-- three variations of the same identity. The same shape works equally for
-- characters, mechanical motifs, fixed backgrounds, or any reusable subject.
--
-- Run (compile only, no server): lua -e "package.path='lua/?.lua;lua/?/init.lua;'..package.path" examples/14_anchor.lua
-- Run (with server):             scripts/runner.lua examples/14_anchor.lua

local vdsl = require("vdsl")
local C = vdsl.catalogs

-- ============================================================
-- Anchor: declared as a plain table, constructed via vdsl.anchor.from
-- ============================================================
-- The registry holds an append-only version chain plus a current-tag
-- pointer. Each version is a self-contained snapshot (base + variations
-- + assets). vdsl.anchor.from is a pure constructor — VDSL never touches
-- persistence (mini-app / B2 / file), the application layer is free to
-- choose any storage backend.

local clock = vdsl.anchor.from {
  name = "vintage_clock",
  current = "v1",
  versions = {
    {
      version = "v1",
      base = {
        base_text = "vintage clockwork brass mechanism, antique mechanical timepiece",
        traits = {
          { text = "polished brass gears, intricate engravings", emphasis = 1.0 },
          { text = "warm sepia tones, soft ambient light",        emphasis = 0.9 },
        },
      },
      variations = {
        wide_view    = { { text = "wide angle, full body of mechanism" } },
        close_up     = { { text = "close-up of central balance wheel" } },
        detail_macro = { { text = "extreme macro detail, single gear tooth visible", emphasis = 1.2 } },
      },
      -- assets.loras / ipadapter_image / i2i_ref can be added here.
      -- They are forwarded automatically when used via Cast{anchor=A}.
      assets = { loras = {} },
    },
  },
}

-- ============================================================
-- Render each variation through the Anchor's identity
-- ============================================================

local w   = vdsl.world {
  model     = "waiIllustrious_v16.safetensors",
  clip_skip = 2,
}
local neg = C.quality.neg_default + C.quality.neg_anatomy

print("=== Anchor Showcase ===")
print(string.format("  identity     : %s",  clock.name))
print(string.format("  current tag  : %s",  tostring(clock.current)))
print(string.format("  versions     : %d",  #clock.versions))

local variations = { "wide_view", "close_up", "detail_macro" }

for _, name in ipairs(variations) do
  -- :current() returns the active Anchor; :render(name) projects the
  -- identity through the named variation overlay and yields a 1-shot
  -- vdsl.Subject (Trait chain composed via Subject:with(...)).
  local subject = clock:current():render(name)

  local cast = vdsl.cast { subject = subject, negative = neg }

  local result = vdsl.render {
    world = w,
    cast  = { cast },
    seed  = 42,
    steps = 25,
    size  = { 1024, 1024 },
  }

  vdsl.emit("anchor_clock_" .. name, result)
  print(string.format("  %-13s %d nodes  prompt: %s...",
    name, result.graph:size(), subject:resolve():sub(1, 60)))
end

-- ============================================================
-- Serialize the Anchor registry itself (JSON-pure roundtrip)
-- ============================================================
-- vdsl.emit dispatches on result type. When passed an anchor_registry it
-- writes a JSON file you can later read back into a Lua table and feed
-- to vdsl.anchor.from(...) — that round-trip is the application-layer
-- agnostic persistence boundary.

vdsl.emit("anchor_clock_registry", clock)

print(string.format("\n  registry JSON emitted: anchor_clock_registry.json"))
print("  (load with: vdsl.anchor.from(json.decode(io.read_file(path))))")
