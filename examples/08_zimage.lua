--- 08_zimage.lua: Z-Image Turbo generation examples
-- Demonstrates: Z-Image compiler with ZSamplerTurbo, natural language prompts,
-- multiple aspect ratios, batch generation.
--
-- Requires:
--   - ComfyUI with ComfyUI-ZImagePowerNodes installed
--   - Z-Image Turbo model (diffusion_models/), Qwen3-4B (text_encoders/), ae.safetensors (vae/)
--
-- Run (compile only):
--   lua -e "package.path='lua/?.lua;lua/?/init.lua;'..package.path" examples/08_zimage.lua
--
-- Run (compile + generate via vdsl_run MCP):
--   vdsl_run(script_file="examples/08_zimage.lua", working_dir=".")

local vdsl  = require("vdsl")
local zimage = require("vdsl.compilers.zimage")

-- ============================================================
-- World: Z-Image Turbo model stack (UNET + CLIP + VAE)
-- ============================================================

local w = vdsl.world {
  model = "z_image_turbo_fp16.safetensors",
  vae   = "ae.safetensors",
}

-- Z-Image uses Qwen3-4B text encoder (separate from checkpoint)
local text_encoder = "qwen_3_4b_bf16.safetensors"

-- ============================================================
-- Prompts: Z-Image excels with natural language descriptions
-- (no danbooru tags needed — just describe what you want)
-- ============================================================

local scenes = {
  {
    name   = "fuji_sunrise",
    prompt = "Breathtaking aerial view of Mount Fuji at sunrise, sea of clouds below, golden hour light painting the snow-capped peak, ultra sharp, landscape photography by National Geographic",
    size   = { 1344, 768 },  -- 16:9 landscape (32-aligned)
    seed   = 77777,
  },
  {
    name   = "cyberpunk_tokyo",
    prompt = "Cyberpunk Tokyo at night, neon signs reflecting on wet streets, a lone figure with an umbrella walking through rain, volumetric fog, cinematic lighting, blade runner aesthetic, 35mm film grain",
    size   = { 1344, 768 },  -- 16:9 landscape (32-aligned)
    seed   = 88888,
  },
  {
    name   = "kaiseki",
    prompt = "Overhead shot of an elegant Japanese kaiseki course, ceramic plates on dark wood table, seasonal autumn ingredients, maple leaf garnish, soft diffused window light, food photography, Michelin star restaurant",
    size   = { 1024, 1024 }, -- 1:1 square
    seed   = 99999,
  },
  {
    name   = "craftsman",
    prompt = "Portrait of an elderly Japanese craftsman in his workshop, weathered hands holding a chisel, warm tungsten lighting, shallow depth of field, Hasselblad medium format, detailed skin texture",
    size   = { 832, 1248 },  -- 2:3 portrait (32-aligned)
    seed   = 11111,
  },
}

-- ============================================================
-- Compile & emit all scenes
-- ============================================================

print("=== Z-Image Turbo Examples ===")
print(string.format("  model: %s", w.model))
print(string.format("  scenes: %d\n", #scenes))

for _, scene in ipairs(scenes) do
  local cast = vdsl.cast { subject = scene.prompt }

  local result = zimage.compile {
    world        = w,
    cast         = { cast },
    seed         = scene.seed,
    size         = scene.size,
    text_encoder = text_encoder,
  }

  vdsl.emit(scene.name, result)

  print(string.format("  %-18s %dx%d  %2d nodes  variant=%s  seed=%d",
    scene.name,
    scene.size[1], scene.size[2],
    result.graph:size(),
    result.variant,
    scene.seed))
end

print("\nDone. Pass to ComfyUI or use vdsl_run MCP to generate.")
