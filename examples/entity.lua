--- entity.lua: Entity composition example (V2)
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;'..package.path" examples/entity.lua

local vdsl = require("vdsl")

-- Reusable traits
local walking  = vdsl.trait("walking pose, full body")
local sitting  = vdsl.trait("sitting, relaxed pose")
local detailed = vdsl.trait("detailed face, detailed eyes", 1.3)

-- Reusable negative
local ugly = vdsl.trait("blurry, ugly, deformed")
  + vdsl.trait("nsfw, watermark", 1.5)

-- Subject: compose traits into identity
local cat = vdsl.subject("cat")
  :with(walking)
  :with(detailed)
  :quality("high")
  :style("anime")

-- Derive a variant (immutable)
local lazy_cat = cat:replace(walking, sitting)

-- World
local w = vdsl.world {
  model     = "sd_xl_base_1.0.safetensors",
  clip_skip = 2,
}

-- Cast with entity composition
local hero = vdsl.cast {
  subject  = cat,
  negative = ugly,
  lora     = {
    vdsl.lora("add_detail.safetensors", vdsl.weight.heavy),
    vdsl.lora("anime_style.safetensors", vdsl.weight.medium),
  },
}

-- Derive: swap subject
local hero_v2 = hero:with { subject = lazy_cat }

print("=== Walking cat ===")
print("Prompt: " .. cat:resolve())
print()

print("=== Lazy cat ===")
print("Prompt: " .. lazy_cat:resolve())
print()

print("=== Negative ===")
print("Negative: " .. ugly:resolve())
print()

-- Full JSON output
local result = vdsl.render {
  world = w,
  cast  = { hero },
  seed  = 42,
  steps = 30,
  cfg   = 7.5,
  size  = { 1024, 1024 },
}

print("=== ComfyUI JSON (" .. result.graph:size() .. " nodes) ===")
print(result.json)
