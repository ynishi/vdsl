--- Z-Image-specific parameter presets.
-- Node class_type mappings, model filenames, and default values
-- for the Z-Image / Z-Image Turbo model family.
--
-- Z-Image uses UNETLoader + CLIPLoader + VAELoader (3-node split),
-- unlike SDXL which bundles everything in CheckpointLoaderSimple.
--
-- Turbo variant uses SamplerCustom with KarrasScheduler + custom sigma
-- manipulation (SetFirstSigma, ExtendIntermediateSigmas).

local config = require("vdsl.config")

local M = {}

-- ============================================================
-- Model defaults
-- ============================================================

--- Default diffusion model filename (placed in models/diffusion_models/).
M.diffusion_model = config.get("zimage_model") or "z_image_turbo.safetensors"

--- Default text encoder filename (placed in models/text_encoders/).
-- Z-Image uses Qwen3-4B as its text encoder.
M.text_encoder = config.get("zimage_text_encoder") or "qwen3-4b-fp16.safetensors"

--- Default text encoder type for CLIPLoader.
-- Must match a valid ComfyUI CLIPLoader type option.
M.clip_type = config.get("zimage_clip_type") or "qwen_image"

--- Default VAE filename (placed in models/vae/).
M.vae = config.get("zimage_vae") or "ae.safetensors"

--- UNETLoader weight dtype.
M.weight_dtype = config.get("zimage_weight_dtype") or "default"

-- ============================================================
-- Sampler defaults (Turbo)
-- ============================================================

M.turbo = {
  sampler   = "euler",
  steps     = 9,       -- 9 inference_steps = 8 DiT forwards (NFE=8)
  cfg       = 0.0,     -- Turbo requires cfg=0 (no guidance)
  scheduler = "karras",

  -- KarrasScheduler parameters
  sigma_max = 1.0,
  sigma_min = 0.0292,
  rho       = 3.4,

  -- SetFirstSigma
  first_sigma = 1.8,

  -- ExtendIntermediateSigmas
  extend_ratio = 1,
}

-- ============================================================
-- Sampler defaults (Base)
-- ============================================================

M.base = {
  sampler   = "euler",
  steps     = 30,
  cfg       = 4.0,
  scheduler = "karras",

  sigma_max = 14.615,
  sigma_min = 0.0292,
  rho       = 7.0,
}

-- ============================================================
-- Latent configuration
-- ============================================================

--- Z-Image uses 16-channel latent (same as SD3/Flux).
M.latent_channels = 16

--- Latent block size (pixels per latent unit).
M.latent_block_size = 8

--- Grid alignment (image dimensions must be divisible by this).
M.grid_size = 32

-- ============================================================
-- Resolution presets (from ZImagePowerNodes)
-- Landscape orientations; swap for portrait.
-- ============================================================

M.resolutions = {
  ["1:1"]   = { 1024, 1024 },  -- 1,048,576 px
  ["4:3"]   = { 1184, 896  },  -- 1,060,864 px (was 888)
  ["3:2"]   = { 1248, 832  },  -- 1,038,336 px (was 1256x840)
  ["16:10"] = { 1280, 800  },  -- 1,024,000 px (was 1296x808)
  ["16:9"]  = { 1344, 768  },  -- 1,032,192 px (was 1368x768)
  ["2:1"]   = { 1440, 736  },  -- 1,059,840 px (was 1448x724)
  ["21:9"]  = { 1568, 672  },  -- 1,053,696 px (already aligned)
}

--- Default resolution.
M.default_size = { 1248, 832 }  -- 3:2 photo (32-aligned)

--- Maximum total pixel count (width * height).
-- Z-Image native training resolution is 1024x1024 = 1,048,576.
-- Exceeding this degrades quality; use post-processing upscale instead.
M.max_pixels = 1048576

-- ============================================================
-- Prompt enhancement defaults
-- ============================================================

--- Default safety/cleanup suffix appended to prompts when enabled.
-- Encodes "what NOT to generate" as positive constraints,
-- since Z-Image Turbo ignores negative prompts.
M.default_prompt_suffix = "sharp focus, correct anatomy, clean image, high fidelity"

-- ============================================================
-- FaceDetailer defaults (Impact Pack)
-- ============================================================

--- FaceDetailer settings tuned for Z-Image Turbo.
-- Uses the same Turbo model for re-sampling detected faces.
-- Lower denoise (0.2) preserves face structure while fixing LoRA artifacts.
M.face_detail_turbo = {
  steps           = 8,
  cfg             = 1.0,
  sampler         = "euler",
  scheduler       = "sgm_uniform",
  denoise         = 0.2,
  guide_size      = 1024,
  max_size        = 1024,
  feather         = 5,
  bbox_threshold  = 0.5,
  bbox_dilation   = 10,
  bbox_crop_factor = 3.0,
  drop_size       = 10,
  cycle           = 1,
  noise_mask      = true,
  force_inpaint   = true,
}

--- FaceDetailer settings for Z-Image Base.
-- Higher steps and cfg for non-distilled model.
M.face_detail_base = {
  steps           = 20,
  cfg             = 4.0,
  sampler         = "euler",
  scheduler       = "normal",
  denoise         = 0.4,
  guide_size      = 1024,
  max_size        = 1024,
  feather         = 5,
  bbox_threshold  = 0.5,
  bbox_dilation   = 10,
  bbox_crop_factor = 3.0,
  drop_size       = 10,
  cycle           = 1,
  noise_mask      = true,
  force_inpaint   = true,
}

-- ============================================================
-- Post-processing model defaults (shared with comfyui compiler)
-- ============================================================

local comfy_params = require("vdsl.compilers.comfyui.parameters")
M.upscale_model = comfy_params.upscale_model
M.face_model    = comfy_params.face_model
M.detectors     = comfy_params.detectors
M.preprocessors = comfy_params.preprocessors

return M
