--- basic.lua: Minimal vdsl V2 example
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;'..package.path" examples/basic.lua

local vdsl = require("vdsl")

-- 1. World
local w = vdsl.world {
  model     = "sd_xl_base_1.0.safetensors",
  vae       = "sdxl_vae.safetensors",
  clip_skip = 2,
}

-- 2. Cast (V2: always subject-based, strings auto-coerce)
local hero = vdsl.cast {
  subject  = "warrior woman, silver armor, dynamic pose, detailed face",
  negative = "blurry, low quality, deformed, ugly",
  lora = {
    { name = "add_detail.safetensors", weight = 0.7 },
  },
}

-- 3. Stage
local battlefield = vdsl.stage {
  controlnet = {
    { type = "control_v11f1p_sd15_depth.pth", image = "depth_map.png", strength = 0.8 },
  },
}

-- 4. Render
local result = vdsl.render {
  world     = w,
  cast      = { hero },
  stage     = battlefield,
  sampler   = "euler_ancestral",
  scheduler = "normal",
  steps     = 30,
  cfg       = 7.5,
  seed      = 42,
  size      = { 1024, 1024 },
  output    = "warrior_scene.png",
}

print(result.json)
