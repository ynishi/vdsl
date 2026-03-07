--- 06_training.lua: LoRA training workflow — dataset + config generation
-- Demonstrates: Pipeline for dataset, training.dataset, training.method("kohya")
-- No server required (compile-only).
--
-- Workflow:
--   1. Define character identity + trigger word
--   2. Generate diverse dataset images via Pipeline (24 shots)
--   3. Emit dataset manifest (kohya layout with captions)
--   4. Generate Kohya training config (TOML)
--
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;'..package.path" examples/06_training.lua

local vdsl     = require("vdsl")
local pipeline = require("vdsl.pipeline")
local training = require("vdsl.training")
local C = vdsl.catalogs

-- ============================================================
-- Character definition
-- ============================================================

local TRIGGER = "mychar01"

local identity = vdsl.trait("android, silver hair, short hair, blue eyes, slim")

local outfits = {
  vdsl.trait("black cyber armor, red accents, mechanical joints"),
  vdsl.trait("formal dress, geometric patterns, chrome accents"),
  vdsl.trait("long coat, scarf, casual clothes"),
}

local neg = C.quality.neg_default + C.quality.neg_anatomy + C.quality.neg_face

-- ============================================================
-- Diversity pools (for dataset coverage)
-- ============================================================

local cameras = {
  { trait = C.camera.bust_shot,   tag = "bust shot" },
  { trait = C.camera.medium_shot, tag = "medium shot" },
  { trait = C.camera.cowboy_shot, tag = "cowboy shot" },
  { trait = C.camera.full_body,   tag = "full body" },
}

local angles = {
  { trait = C.camera.eye_level,   tag = nil },
  { trait = C.camera.low_angle,   tag = "low angle" },
  { trait = C.camera.from_side,   tag = "from side" },
  { trait = C.camera.dutch_angle, tag = "dutch angle" },
  { trait = C.camera.from_behind, tag = "from behind" },
}

local lightings = {
  { trait = C.lighting.neon,        tag = "neon lighting" },
  { trait = C.lighting.rim_light,   tag = "rim light" },
  { trait = C.lighting.soft_studio, tag = "soft studio light" },
  { trait = C.lighting.golden_hour, tag = "golden hour" },
  { trait = C.lighting.chiaroscuro, tag = "chiaroscuro" },
  { trait = C.lighting.overcast,    tag = "overcast" },
  { trait = C.lighting.volumetric,  tag = "volumetric lighting" },
}

local environments = {
  { trait = C.environment.setting.cyberpunk_city, tag = "cyberpunk city" },
  { trait = C.environment.setting.ruins,          tag = "ruins" },
  { trait = C.environment.setting.rooftop,        tag = "rooftop" },
  { trait = C.environment.setting.cathedral,      tag = "cathedral" },
  { trait = C.environment.setting.city_street,    tag = "city street" },
  { trait = nil,                                   tag = nil },
}

local expressions = {
  { trait = C.figure.expression.expressionless, tag = nil },
  { trait = C.figure.expression.gentle_smile,   tag = "gentle smile" },
  { trait = C.figure.expression.serious,        tag = "serious" },
  { trait = C.figure.expression.determined,     tag = "determined" },
  { trait = C.figure.expression.confident,      tag = "confident" },
}

-- ============================================================
-- Build 24 variations with prime-offset cycling (decorrelation)
-- ============================================================

local function pick(pool, i)
  return pool[((i - 1) % #pool) + 1]
end

local dataset_variations = {}
for i = 1, 24 do
  local cam   = pick(cameras,      i)
  local angle = pick(angles,       i * 3 + 1)
  local light = pick(lightings,    i * 11 + 2)
  local env   = pick(environments, i * 13 + 3)
  local expr  = pick(expressions,  i * 3 + 5)
  local outfit_idx = ((i - 1) % #outfits) + 1

  -- Caption: trigger-first, skip nil tags
  local caption_parts = { TRIGGER, "1girl" }
  if expr.tag then caption_parts[#caption_parts + 1] = expr.tag end
  caption_parts[#caption_parts + 1] = cam.tag
  if angle.tag then caption_parts[#caption_parts + 1] = angle.tag end
  caption_parts[#caption_parts + 1] = light.tag
  if env.tag then caption_parts[#caption_parts + 1] = env.tag end

  dataset_variations[#dataset_variations + 1] = {
    key        = string.format("%02d", i),
    cam        = cam,
    angle      = angle,
    light      = light,
    env        = env,
    expr       = expr,
    outfit_idx = outfit_idx,
    caption    = table.concat(caption_parts, ", "),
  }
end

-- ============================================================
-- Pipeline: dataset image generation
-- ============================================================

local w = vdsl.world { clip_skip = 2 }

local pipe = pipeline.new("training_dataset", {
  save_dir  = "training_dataset",
  seed_base = 7000,
  size      = { 1024, 1024 },
})

pipe:pass("gen", function(v, ctx)
  local subject = vdsl.subject("1girl, solo")
    :with(identity)
    :with(outfits[v.outfit_idx])
    :quality("high"):style("cinematic")

  if v.expr.trait then subject = subject:with(v.expr.trait) end

  local scene = v.cam.trait + v.angle.trait + v.light.trait
  if v.env.trait then scene = scene + v.env.trait end

  return {
    world = w,
    cast  = { vdsl.cast { subject = subject:with(scene), negative = neg } },
    seed  = ctx.seed,
    post  = vdsl.post("facedetail", { detector = "face", denoise = 0.4 }),
  }
end)

pipe:compile(dataset_variations)

-- ============================================================
-- Dataset manifest
-- ============================================================

local ds = training.dataset {
  name       = TRIGGER,
  layout     = "kohya",
  source_dir = "training_dataset",
  trigger    = TRIGGER,
  repeats    = 10,
  pairs      = dataset_variations,
}
ds:emit()

-- ============================================================
-- Kohya training config
-- ============================================================

local kohya = training.method("kohya")

local toml = kohya.config {
  checkpoint  = w.model,
  data_dir    = "/workspace/datasets/" .. TRIGGER,
  rank        = 8,
  alpha       = 4,
  steps       = 300,
  lr          = 0.0003,
  scheduler   = "cosine",
  resolution  = 1024,
}

print("\n=== Kohya Training Config ===")
print(toml)

local ds_path = kohya.dataset_path {
  data_dir = "/workspace/datasets",
  trigger  = TRIGGER,
  repeats  = 10,
}
print("Dataset path: " .. ds_path)

local cmd = kohya.command {
  config_path = "/workspace/datasets/" .. TRIGGER .. "/training_config.toml",
}
print("Train command: " .. cmd)

-- ============================================================
-- Coverage report
-- ============================================================

print("\n=== Dataset Coverage ===")
local cam_used, angle_used, light_used = {}, {}, {}
for _, v in ipairs(dataset_variations) do
  cam_used[v.cam.tag] = true
  if v.angle.tag then angle_used[v.angle.tag] = true end
  light_used[v.light.tag] = true
end

local function count_keys(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
print(string.format("  cameras:    %d/%d", count_keys(cam_used), #cameras))
print(string.format("  angles:     %d/%d", count_keys(angle_used), #angles - 1))  -- eye_level has no tag
print(string.format("  lightings:  %d/%d", count_keys(light_used), #lightings))
print(string.format("  outfits:    %d/%d", #outfits, #outfits))
print(string.format("  total:      %d images", #dataset_variations))
