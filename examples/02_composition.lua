--- 02_composition.lua: Entity composition and immutable derivation
-- Demonstrates: Trait, Subject, Catalog, with(), replace(), quality(), style()
-- No server required.
--
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;'..package.path" examples/02_composition.lua

local vdsl = require("vdsl")
local C = vdsl.catalogs

local w = vdsl.world { clip_skip = 2 }

-- ============================================================
-- Trait composition: atomic prompt fragments
-- ============================================================

local walking  = vdsl.trait("walking pose, full body")
local sitting  = vdsl.trait("sitting, relaxed pose")
local detailed = vdsl.trait("detailed face, detailed eyes", 1.3)

-- Traits compose with + operator
local neg = C.quality.neg_default + C.quality.neg_anatomy + C.quality.neg_face

-- ============================================================
-- Subject: identity built from Traits
-- ============================================================

local girl = vdsl.subject("1girl, solo")
  :with(vdsl.trait("silver hair, long hair, blue eyes"))
  :with(detailed)
  :with(walking)
  :quality("high")

-- Immutable derivation: original is unchanged
local girl_sitting = girl:replace(walking, sitting)

print("=== Subject Composition ===")
print("  walking: " .. girl:resolve())
print("  sitting: " .. girl_sitting:resolve())

-- ============================================================
-- Catalog integration: pre-defined Trait dictionaries
-- ============================================================

local scenes = {
  { name = "gothic",    traits = C.style.anime + C.lighting.chiaroscuro + C.camera.bust_shot },
  { name = "golden",    traits = C.style.cinematic + C.lighting.golden_hour + C.camera.medium_shot },
  { name = "cyberpunk", traits = C.style.digital_painting + C.lighting.neon + C.camera.full_body },
  { name = "portrait",  traits = C.style.oil + C.lighting.rembrandt + C.camera.closeup },
}

print(string.format("\n=== Catalog Scenes: %d variations ===", #scenes))

for _, scene in ipairs(scenes) do
  local subject = girl:with(scene.traits)
  local cast = vdsl.cast { subject = subject, negative = neg }

  local result = vdsl.render {
    world = w,
    cast  = { cast },
    seed  = 42,
    steps = 20,
    size  = { 832, 1216 },
  }
  vdsl.emit("scene_" .. scene.name, result)
  print(string.format("  %-10s %2d nodes  prompt: %s...",
    scene.name, result.graph:size(), subject:resolve():sub(1, 60)))
end

-- ============================================================
-- Multi-cast: separate character and atmosphere
-- ============================================================

local atmosphere = vdsl.cast {
  subject = C.environment.setting.enchanted_forest
    + C.environment.weather.mist
    + C.environment.time.moonlight,
}

local result = vdsl.render {
  world = w,
  cast  = {
    vdsl.cast { subject = girl_sitting:with(C.camera.full_body), negative = neg },
    atmosphere,
  },
  seed  = 42,
  steps = 25,
  size  = { 1216, 832 },
}
vdsl.emit("multi_cast", result)

print(string.format("\n=== Multi-Cast: %d nodes (character + atmosphere as separate casts) ===",
  result.graph:size()))
