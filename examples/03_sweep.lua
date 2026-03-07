--- 03_sweep.lua: Parametric sweep — grid search over poses, styles, and LoRA weights
-- Demonstrates: immutable Subject derivation, 2D grid, LoRA via World resource pool
-- No server required.
--
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;'..package.path" examples/03_sweep.lua

local vdsl = require("vdsl")
local C = vdsl.catalogs

local neg = C.quality.neg_default + C.quality.neg_anatomy

-- ============================================================
-- 1. Pose × Style grid
-- ============================================================

local poses = {
  { name = "standing", trait = C.figure.pose.standing + C.camera.full_body },
  { name = "sitting",  trait = C.figure.pose.sitting + C.camera.medium_shot },
  { name = "walking",  trait = C.figure.pose.walking + C.camera.full_body },
  { name = "closeup",  trait = C.figure.pose.looking_at_viewer + C.camera.closeup },
}

local styles = {
  { name = "anime",    trait = C.style.anime },
  { name = "cinema",   trait = C.style.cinematic + C.lighting.golden_hour },
  { name = "painting", trait = C.style.oil + C.lighting.rembrandt },
}

local base = vdsl.subject("1girl, solo, red hair, green eyes")
  :with(C.quality.high)

local w = vdsl.world { clip_skip = 2 }

print(string.format("=== Pose × Style Grid: %d × %d = %d variants ===",
  #poses, #styles, #poses * #styles))

local count = 0
for _, pose in ipairs(poses) do
  for _, style in ipairs(styles) do
    local subject = base:with(pose.trait):with(style.trait)
    local cast = vdsl.cast { subject = subject, negative = neg }
    local result = vdsl.render {
      world = w,
      cast  = { cast },
      seed  = 42,
      steps = 20,
      size  = { 832, 1216 },
    }
    local tag = pose.name .. "_" .. style.name
    vdsl.emit(tag, result)
    count = count + 1
    print(string.format("  [%2d] %-20s %2d nodes", count, tag, result.graph:size()))
  end
end

-- ============================================================
-- 2. CFG sweep (same seed, same prompt)
-- ============================================================

print("\n=== CFG Sweep (seed=42) ===")

local subject_fixed = base
  :with(C.figure.pose.standing)
  :with(C.camera.cowboy_shot)
  :with(C.style.anime)

for _, cfg_val in ipairs({ 3.0, 5.0, 7.0, 9.0, 12.0 }) do
  local result = vdsl.render {
    world = w,
    cast  = { vdsl.cast { subject = subject_fixed, negative = neg } },
    seed  = 42,
    steps = 25,
    cfg   = cfg_val,
    size  = { 832, 1216 },
  }
  local tag = string.format("cfg_%.1f", cfg_val)
  vdsl.emit(tag, result)

  local decoded = vdsl.decode(result.prompt)
  print(string.format("  cfg=%-5.1f  decoded_cfg=%.1f  nodes=%d",
    cfg_val, decoded.sampler.cfg, result.graph:size()))
end

-- ============================================================
-- 3. LoRA weight sweep (World resource pool)
-- ============================================================

print("\n=== LoRA Weight Sweep (World resource pool) ===")

for _, lora_w in ipairs({ 0.2, 0.4, 0.6, 0.8, 1.0 }) do
  local w_lora = vdsl.world {
    clip_skip = 2,
    lora = {
      detail = { name = "my_detail_lora.safetensors", weight = lora_w },
    },
  }

  local subject = base
    :with(C.figure.pose.standing)
    :with(C.camera.cowboy_shot)
    :with(vdsl.trait("detailed"):hint("lora", "detail"))

  local result = vdsl.render {
    world = w_lora,
    cast  = { vdsl.cast { subject = subject, negative = neg } },
    seed  = 42,
    steps = 25,
    size  = { 832, 1216 },
  }
  local tag = string.format("lora_%.1f", lora_w)
  vdsl.emit(tag, result)

  -- Verify compiled weight
  local compiled_w = nil
  for _, node in pairs(result.prompt) do
    if node.class_type == "LoraLoader" then
      compiled_w = node.inputs.strength_model
    end
  end
  print(string.format("  weight=%.1f  compiled=%.1f  nodes=%d",
    lora_w, compiled_w or -1, result.graph:size()))
end

print(string.format("\n=== Total: %d workflows compiled ===", count + 5 + 5))
