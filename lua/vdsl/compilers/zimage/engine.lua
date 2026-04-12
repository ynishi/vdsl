--- Z-Image Compiler Engine: transforms entity IR into a ComfyUI node graph
--- for the Z-Image / Z-Image Turbo model family.
--
-- Pipeline:
--   UNETLoader + CLIPLoader + VAELoader
--   → [LoraLoader chain] (both Turbo and Base)
--   → CLIPTextEncode (natural language prompt + optional suffix)
--   → KarrasScheduler → SetFirstSigma → [ExtendIntermediateSigmas]
--   → SamplerCustom (no CFG for Turbo)
--   → [Post latent ops] → VAEDecode → [Post pixel ops] → SaveImage
--
-- Key differences from the comfyui/engine.lua (SDXL):
--   1. 3-node model loading (UNET/CLIP/VAE separate)
--   2. Natural language prompts (no danbooru tag ordering)
--   3. SamplerCustom with explicit sigma schedule (not KSampler)
--   4. Turbo: cfg=0, no negative prompt
--   5. 16-channel latent (EmptySD3LatentImage)
--   6. No CLIP skip (Qwen3-4B encoder)
--   7. Resolution validation (32-divisibility, pixel limit warning)
--   8. LoRA support in both Turbo and Base variants
--   9. Optional prompt_suffix for safety/cleanup constraints
--  10. FaceDetailer with variant-aware defaults (Turbo: 8 steps, cfg=1.0)

local Entity = require("vdsl.entity")
local Graph  = require("vdsl.graph")
local json   = require("vdsl.util.json")
local Weight = require("vdsl.weight")
local Post   = require("vdsl.post")
local params = require("vdsl.compilers.zimage.parameters")

local M = {}

local _rng_seeded = false
local function ensure_seeded()
  if not _rng_seeded then
    math.randomseed(os.time())
    _rng_seeded = true
  end
end

-- ============================================================
-- Post-processing phase classification (shared with comfyui)
-- ============================================================

local LATENT_OPS = { hires = true, refine = true }

-- ============================================================
-- Resolution validation
-- ============================================================

--- Round a dimension up to the nearest multiple of grid_size.
-- @param v number pixel dimension
-- @return number aligned dimension
local function align32(v)
  local gs = params.grid_size  -- 32
  return math.ceil(v / gs) * gs
end

--- Validate and optionally correct image dimensions.
-- Warns if not divisible by 32 or if pixel count exceeds training resolution.
-- Auto-corrects to 32-aligned only when align32 flag is set.
-- @param size table {width, height}
-- @param do_align boolean if true, auto-correct to 32-aligned
-- @return table {width, height} (possibly corrected)
local function validate_size(size, do_align)
  local w, h = size[1], size[2]

  -- Check grid alignment (32-divisibility recommended for quality)
  local aw, ah = align32(w), align32(h)
  if aw ~= w or ah ~= h then
    if do_align then
      io.stderr:write(string.format(
        "[vdsl/zimage] size %dx%d -> %dx%d (aligned to %d)\n",
        w, h, aw, ah, params.grid_size))
      w, h = aw, ah
    else
      io.stderr:write(string.format(
        "[vdsl/zimage] WARNING: size %dx%d not divisible by %d. "
        .. "Set align32=true to auto-correct.\n",
        w, h, params.grid_size))
    end
  end

  -- Check total pixel count
  local pixels = w * h
  if pixels > params.max_pixels then
    io.stderr:write(string.format(
      "[vdsl/zimage] WARNING: %dx%d = %d pixels exceeds training resolution %d. "
      .. "Consider post-processing upscale instead.\n",
      w, h, pixels, params.max_pixels))
  end

  return { w, h }
end

-- ============================================================
-- Variant detection
-- ============================================================

--- Determine if we should use Turbo settings.
-- Turbo = cfg 0, no negative, 8-step schedule.
-- @param opts table render options
-- @return boolean
local function is_turbo(opts)
  -- Explicit override
  if opts.variant == "base" then return false end
  if opts.variant == "turbo" then return true end
  -- Auto-detect from world.cfg: cfg > 0.5 implies Base model
  local cfg = opts.world and opts.world.cfg
  if cfg ~= nil and cfg > 0.5 then return false end
  -- Default to turbo (most common Z-Image use case)
  return true
end

-- ============================================================
-- World compilation (3-node split)
-- ============================================================

local function compile_world(g, world, opts)
  -- UNET (diffusion model)
  local unet = g:add("UNETLoader", {
    unet_name    = world.model,
    weight_dtype = params.weight_dtype,
  })
  local model_ref = unet(0)

  -- CLIP (text encoder)
  -- Check opts.text_encoder, world.text_encoder, then parameter default
  local clip_name = (opts and opts.text_encoder) or world.text_encoder or params.text_encoder
  local clip_type = (opts and opts.clip_type) or world.clip_type or params.clip_type
  local clip = g:add("CLIPLoader", {
    clip_name = clip_name,
    type      = clip_type,
  })
  local clip_ref = clip(0)

  -- VAE
  local vae_name = world.vae or params.vae
  local vae = g:add("VAELoader", {
    vae_name = vae_name,
  })
  local vae_ref = vae(0)

  return model_ref, clip_ref, vae_ref
end

-- ============================================================
-- Cast compilation
-- ============================================================

--- Compile casts: encode prompts, chain LoRAs, apply prompt suffix.
-- LoRAs are supported in both Turbo and Base variants.
-- Negative prompts are only used in Base variant.
-- @param opts table compile options (for loras and prompt_suffix)
-- @return model_ref, positive_ref, negative_ref_or_nil
local function compile_casts(g, casts, model_ref, clip_ref, world, turbo, opts)
  -- Phase 1: LoRAs
  -- Sources: world.lora, cast.lora, opts.loras (all supported in both variants)
  local loaded_loras = {}

  -- World-level LoRAs
  if world.lora then
    for _, lora in ipairs(world.lora) do
      local w = Weight.resolve(lora.weight, 1.0)
      local lora_node = g:add("LoraLoader", {
        model          = model_ref,
        clip           = clip_ref,
        lora_name      = lora.name,
        strength_model = w,
        strength_clip  = w,
      })
      model_ref = lora_node(0)
      clip_ref  = lora_node(1)
      loaded_loras[lora.name] = true
    end
  end

  -- opts.loras (compile-time LoRAs, e.g. per-scene LoRA)
  if opts and opts.loras then
    for _, lora in ipairs(opts.loras) do
      local name = lora.file or lora.name
      if name and not loaded_loras[name] then
        local w = Weight.resolve(lora.weight, 1.0)
        local lora_node = g:add("LoraLoader", {
          model          = model_ref,
          clip           = clip_ref,
          lora_name      = name,
          strength_model = w,
          strength_clip  = w,
        })
        model_ref = lora_node(0)
        clip_ref  = lora_node(1)
        loaded_loras[name] = true
      end
    end
  end

  -- Cast-level LoRAs
  for _, cast in ipairs(casts) do
    if cast.lora then
      for _, lora in ipairs(cast.lora) do
        if not loaded_loras[lora.name] then
          local w = Weight.resolve(lora.weight, 1.0)
          local lora_node = g:add("LoraLoader", {
            model          = model_ref,
            clip           = clip_ref,
            lora_name      = lora.name,
            strength_model = w,
            strength_clip  = w,
          })
          model_ref = lora_node(0)
          clip_ref  = lora_node(1)
          loaded_loras[lora.name] = true
        end
      end
    end
  end

  -- Phase 2: Encode prompts
  -- Z-Image uses natural language — resolve in "natural" mode
  -- to prefer :desc() text over danbooru tags when available.

  -- Resolve prompt suffix (safety/cleanup constraints)
  local suffix = nil
  if opts then
    if opts.prompt_suffix == true then
      -- true → use default suffix
      suffix = params.default_prompt_suffix
    elseif type(opts.prompt_suffix) == "string" then
      -- custom string
      suffix = opts.prompt_suffix
    end
  end

  local pos_refs = {}
  local neg_refs = {}

  for _, cast in ipairs(casts) do
    local prompt_text = Entity.resolve_text(cast.subject, "natural")

    -- Append safety/cleanup suffix if enabled
    if suffix and suffix ~= "" then
      prompt_text = prompt_text .. ", " .. suffix
    end

    local pos = g:add("CLIPTextEncode", {
      clip = clip_ref,
      text = prompt_text,
    })
    pos_refs[#pos_refs + 1] = pos(0)

    -- Negative: only for Base variant
    if not turbo then
      local negative_text = Entity.resolve_text(cast.negative, "natural")
      if negative_text ~= "" then
        local neg = g:add("CLIPTextEncode", {
          clip = clip_ref,
          text = negative_text,
        })
        neg_refs[#neg_refs + 1] = neg(0)
      end
    end
  end

  -- Phase 3: Combine conditionings
  local pos_ref = pos_refs[1]
  for i = 2, #pos_refs do
    local combine = g:add("ConditioningCombine", {
      conditioning_1 = pos_ref,
      conditioning_2 = pos_refs[i],
    })
    pos_ref = combine(0)
  end

  local neg_ref = nil
  if #neg_refs > 0 then
    neg_ref = neg_refs[1]
    for i = 2, #neg_refs do
      local combine = g:add("ConditioningCombine", {
        conditioning_1 = neg_ref,
        conditioning_2 = neg_refs[i],
      })
      neg_ref = combine(0)
    end
  end

  return model_ref, pos_ref, neg_ref
end

-- ============================================================
-- Global negative (Base only)
-- ============================================================

local function compile_global_negative(g, neg_text, negative_ref, clip_ref, turbo)
  if turbo then return nil end
  if not neg_text or neg_text == "" then return negative_ref end

  local global_neg = g:add("CLIPTextEncode", {
    clip = clip_ref,
    text = neg_text,
  })

  if negative_ref then
    local combined = g:add("ConditioningCombine", {
      conditioning_1 = negative_ref,
      conditioning_2 = global_neg(0),
    })
    return combined(0)
  end
  return global_neg(0)
end

-- ============================================================
-- Stage compilation (ControlNet, img2img)
-- ============================================================

local function compile_stage(g, stage, positive_ref, negative_ref, clip_ref, vae_ref)
  local latent_ref = nil

  if stage.controlnet then
    -- ControlNetApplyAdvanced requires a negative conditioning input.
    -- For Turbo (no negative prompt), create an empty encoding.
    if not negative_ref then
      local empty_neg = g:add("CLIPTextEncode", {
        clip = clip_ref,
        text = "",
      })
      negative_ref = empty_neg(0)
    end

    for _, cn in ipairs(stage.controlnet) do
      local cn_loader = g:add("ControlNetLoader", {
        control_net_name = cn.type,
      })

      local cn_image = g:add("LoadImage", { image = cn.image })
      local image_ref = cn_image(0)

      local cn_apply = g:add("ControlNetApplyAdvanced", {
        positive      = positive_ref,
        negative      = negative_ref,
        control_net   = cn_loader(0),
        image         = image_ref,
        strength      = cn.strength,
        start_percent = cn.start_percent or 0.0,
        end_percent   = cn.end_percent or 1.0,
        vae           = vae_ref,
      })
      positive_ref = cn_apply(0)
      negative_ref = cn_apply(1)
    end
  end

  if stage.latent_image then
    local init_img = g:add("LoadImage", { image = stage.latent_image })
    local encoded = g:add("VAEEncode", {
      pixels = init_img(0),
      vae    = vae_ref,
    })
    latent_ref = encoded(0)
  end

  return positive_ref, negative_ref, latent_ref
end

-- ============================================================
-- Sigma schedule compilation (Z-Image specific)
-- ============================================================

--- Build the sigma schedule for Z-Image sampling.
-- Turbo: KarrasScheduler → SetFirstSigma → ExtendIntermediateSigmas
-- Base:  KarrasScheduler (standard)
-- @return sigmas_ref
local function compile_sigmas(g, opts, turbo)
  local preset = turbo and params.turbo or params.base

  local steps     = opts.steps or preset.steps
  local sigma_max = opts.sigma_max or preset.sigma_max
  local sigma_min = opts.sigma_min or preset.sigma_min
  local rho       = opts.rho or preset.rho

  local karras = g:add("KarrasScheduler", {
    steps     = steps,
    sigma_max = sigma_max,
    sigma_min = sigma_min,
    rho       = rho,
  })
  local sigmas_ref = karras(0)

  if turbo then
    -- Adjust first sigma for Turbo noise calibration
    local first_sigma = opts.first_sigma or preset.first_sigma
    local set_first = g:add("SetFirstSigma", {
      sigmas = sigmas_ref,
      sigma  = first_sigma,
    })
    sigmas_ref = set_first(0)

    -- Extend intermediate sigmas for smoother denoising
    local extend_steps = opts.extend_steps or preset.extend_ratio or 1
    if extend_steps and extend_steps > 0 then
      local extend = g:add("ExtendIntermediateSigmas", {
        sigmas        = sigmas_ref,
        steps         = extend_steps,
        start_at_sigma = opts.extend_start or -1.0,
        end_at_sigma   = opts.extend_end or 12.0,
        spacing        = opts.extend_spacing or "linear",
      })
      sigmas_ref = extend(0)
    end
  end

  return sigmas_ref
end

-- ============================================================
-- Post-processing (latent phase)
-- ============================================================

local function compile_post_latent(g, post, latent_ref, model_ref, pos_ref, neg_ref, opts, turbo)
  for _, op in ipairs(post:ops()) do
    if LATENT_OPS[op.type] then
      local p = op.params
      local seed = opts.seed
      if seed then seed = seed + 1 end

      if op.type == "hires" then
        local upscaled = g:add("LatentUpscaleBy", {
          samples        = latent_ref,
          upscale_method = p.method or "nearest-exact",
          scale_by       = p.scale or 1.5,
        })

        -- Hires re-sample: always use base-like sigma range
        -- (Turbo's narrow range sigma_max=1.0 is insufficient for refinement)
        local hires_sigmas = compile_sigmas(g, {
          steps     = p.steps or 10,
          sigma_max = p.sigma_max or params.base.sigma_max,
          sigma_min = p.sigma_min or params.base.sigma_min,
          rho       = p.rho or params.base.rho,
        }, false)  -- hires pass uses standard schedule (no SetFirstSigma)

        local sampler_node = g:add("KSamplerSelect", {
          sampler_name = p.sampler or opts.sampler or "euler",
        })

        local noise_seed = seed or math.random(0, 2^32 - 1)
        local resampled = g:add("SamplerCustom", {
          model        = model_ref,
          add_noise    = true,
          noise_seed   = noise_seed,
          cfg          = p.cfg or params.base.cfg,
          positive     = pos_ref,
          negative     = neg_ref,
          sampler      = sampler_node(0),
          sigmas       = hires_sigmas,
          latent_image = upscaled(0),
        })
        latent_ref = resampled(0)

      elseif op.type == "refine" then
        -- Refine: always use base-like sigma range
        local refine_sigmas = compile_sigmas(g, {
          steps     = p.steps or 10,
          sigma_max = p.sigma_max or params.base.sigma_max,
          sigma_min = p.sigma_min or params.base.sigma_min,
          rho       = p.rho or params.base.rho,
        }, false)

        local sampler_node = g:add("KSamplerSelect", {
          sampler_name = p.sampler or opts.sampler or "euler",
        })

        local noise_seed = seed or math.random(0, 2^32 - 1)
        local refined = g:add("SamplerCustom", {
          model        = model_ref,
          add_noise    = true,
          noise_seed   = noise_seed,
          cfg          = p.cfg or params.base.cfg,
          positive     = pos_ref,
          negative     = neg_ref,
          sampler      = sampler_node(0),
          sigmas       = refine_sigmas,
          latent_image = latent_ref,
        })
        latent_ref = refined(0)
      end
    end
  end
  return latent_ref
end

-- ============================================================
-- Post-processing (pixel phase) — reuse comfyui logic
-- ============================================================

local function compile_post_pixel(g, post, image_ref, ctx)
  for _, op in ipairs(post:ops()) do
    if not LATENT_OPS[op.type] then
      local p = op.params

      if op.type == "upscale" then
        local loader = g:add("UpscaleModelLoader", {
          model_name = p.model or params.upscale_model,
        })
        local upscaled = g:add("ImageUpscaleWithModel", {
          upscale_model = loader(0),
          image         = image_ref,
        })
        image_ref = upscaled(0)

      elseif op.type == "face" then
        local loader = g:add("FaceRestoreModelLoader", {
          model_name = p.model or params.face_model,
        })
        local restored = g:add("FaceRestoreWithModel", {
          facerestore_model = loader(0),
          image             = image_ref,
          fidelity          = p.fidelity or 0.5,
        })
        image_ref = restored(0)

      elseif op.type == "color" then
        local function mul_to_offset(v, default)
          if v == nil then return 0 end
          local raw = (v - (default or 1.0)) * 100
          return math.floor(raw * 10 + 0.5) / 10
        end
        local corrected = g:add("ColorCorrect", {
          image       = image_ref,
          temperature = p.temperature or 0,
          hue         = p.hue or 0,
          brightness  = mul_to_offset(p.brightness, 1.0),
          contrast    = mul_to_offset(p.contrast, 1.0),
          saturation  = mul_to_offset(p.saturation, 1.0),
          gamma       = p.gamma or 1.0,
        })
        image_ref = corrected(0)

      elseif op.type == "sharpen" then
        local sharpened = g:add("ImageSharpen", {
          image          = image_ref,
          sharpen_radius = p.radius or 1,
          sigma          = p.sigma or 1.0,
          alpha          = p.alpha or 1.0,
        })
        image_ref = sharpened(0)

      elseif op.type == "resize" then
        if p.scale then
          local scaled = g:add("ImageScaleBy", {
            image          = image_ref,
            upscale_method = p.method or "nearest-exact",
            scale_by       = p.scale,
          })
          image_ref = scaled(0)
        elseif p.width and p.height then
          local scaled = g:add("ImageScale", {
            image          = image_ref,
            upscale_method = p.method or "nearest-exact",
            width          = p.width,
            height         = p.height,
            crop           = p.crop or "disabled",
          })
          image_ref = scaled(0)
        end

      elseif op.type == "facedetail" and ctx then
        -- Select variant-appropriate defaults (Turbo vs Base)
        local fd_defaults = ctx.turbo
          and params.face_detail_turbo
          or  params.face_detail_base

        local detector_key   = p.detector or "face"
        local detector_model = params.detectors[detector_key]
          or params.detectors.face

        local detector = g:add("UltralyticsDetectorProvider", {
          model_name = detector_model,
        })

        local is_segm = detector_model:match("^segm/") ~= nil

        local fd_seed = ctx.seed
        if fd_seed then fd_seed = fd_seed + 100 end

        local fd_positive = ctx.positive
        local fd_negative = ctx.negative
        if p.prompt then
          fd_positive = g:add("CLIPTextEncode", {
            clip = ctx.clip,
            text = Entity.resolve_text(p.prompt, "natural"),
          })(0)
        end
        if p.negative then
          fd_negative = g:add("CLIPTextEncode", {
            clip = ctx.clip,
            text = Entity.resolve_text(p.negative, "natural"),
          })(0)
        end

        -- For Turbo FaceDetailer, if no negative conditioning exists,
        -- create an empty one (FaceDetailer node requires it)
        if not fd_negative then
          fd_negative = g:add("CLIPTextEncode", {
            clip = ctx.clip,
            text = "",
          })(0)
        end

        local fd_params = {
          image            = image_ref,
          model            = ctx.model,
          clip             = ctx.clip,
          vae              = ctx.vae,
          positive         = fd_positive,
          negative         = fd_negative,
          guide_size       = p.guide or fd_defaults.guide_size,
          guide_size_for   = true,
          max_size         = p.max_size or fd_defaults.max_size,
          seed             = fd_seed or math.random(0, 2^32 - 1),
          steps            = p.steps or fd_defaults.steps,
          cfg              = p.cfg or fd_defaults.cfg,
          sampler_name     = p.sampler or fd_defaults.sampler,
          scheduler        = p.scheduler or fd_defaults.scheduler,
          denoise          = p.denoise or fd_defaults.denoise,
          feather          = p.feather or fd_defaults.feather,
          noise_mask       = fd_defaults.noise_mask,
          force_inpaint    = fd_defaults.force_inpaint,
          bbox_threshold   = p.bbox_threshold or fd_defaults.bbox_threshold,
          bbox_dilation    = p.bbox_dilation or fd_defaults.bbox_dilation,
          bbox_crop_factor = p.bbox_crop_factor or fd_defaults.bbox_crop_factor,
          sam_detection_hint       = "center-1",
          sam_dilation             = 0,
          sam_threshold            = 0.93,
          sam_bbox_expansion       = 0,
          sam_mask_hint_threshold  = 0.7,
          sam_mask_hint_use_negative = "False",
          drop_size        = p.drop_size or fd_defaults.drop_size,
          bbox_detector    = detector(0),
          wildcard         = "",
          cycle            = p.cycle or fd_defaults.cycle,
        }

        if is_segm then
          fd_params.segm_detector_opt = detector(1)
        end

        local detailed = g:add("FaceDetailer", fd_params)
        image_ref = detailed(0)
      end
    end
  end
  return image_ref
end

-- ============================================================
-- Hint collection and auto-Post generation
-- ============================================================

local HINT_ORDER = {
  hires      = 1,
  refine     = 2,
  upscale    = 3,
  facedetail = 4,
  face       = 5,
  color      = 6,
  sharpen    = 7,
  resize     = 8,
}

local function collect_hints(casts)
  local merged = nil
  for _, cast in ipairs(casts) do
    local subj = cast.subject
    if subj and type(subj.hints) == "function" then
      local h = subj:hints()
      if h then
        if not merged then merged = {} end
        for k, v in pairs(h) do
          merged[k] = v
        end
      end
    end
  end
  return merged
end

local function build_post_from_hints(hints)
  local sorted = {}
  for op_type, p in pairs(hints) do
    sorted[#sorted + 1] = { type = op_type, params = p }
  end
  table.sort(sorted, function(a, b)
    return (HINT_ORDER[a.type] or 99) < (HINT_ORDER[b.type] or 99)
  end)

  local post = Post.new(sorted[1].type, sorted[1].params)
  for i = 2, #sorted do
    post = post + Post.new(sorted[i].type, sorted[i].params)
  end
  return post
end

-- ============================================================
-- Option resolution
-- ============================================================

local function opt(opts, key, fallback)
  if opts[key] ~= nil then return opts[key] end
  local world = opts.world
  if world and world[key] ~= nil then return world[key] end
  return fallback
end

-- ============================================================
-- Main compilation
-- ============================================================

function M.compile(opts)
  -- Validation
  if not opts.world then
    error("render: 'world' is required", 2)
  end
  if not Entity.is(opts.world, "world") then
    error("render: 'world' must be a World entity", 2)
  end
  if not opts.cast or #opts.cast == 0 then
    error("render: 'cast' requires at least one Cast entity", 2)
  end
  if not Entity.is(opts.cast[1], "cast") then
    error("render: 'cast[1]' must be a Cast entity", 2)
  end
  if opts.stage and not Entity.is(opts.stage, "stage") then
    error("render: 'stage' must be a Stage entity", 2)
  end
  if opts.post and not Entity.is(opts.post, "post") then
    error("render: 'post' must be a Post entity", 2)
  end

  ensure_seeded()

  local turbo = is_turbo(opts)
  local preset = turbo and params.turbo or params.base

  local g = Graph.new()

  -- 1. World (3-node split)
  local model_ref, clip_ref, vae_ref = compile_world(g, opts.world, opts)

  -- 2. Casts (prompt encoding, LoRA, prompt suffix)
  local positive_ref, negative_ref
  model_ref, positive_ref, negative_ref = compile_casts(
    g, opts.cast, model_ref, clip_ref, opts.world, turbo, opts
  )

  -- 3. Global negative (Base only)
  if opts.negative then
    local neg_text = Entity.resolve_text(opts.negative, "natural")
    negative_ref = compile_global_negative(
      g, neg_text, negative_ref, clip_ref, turbo
    )
  end

  -- 4. Stage (optional: ControlNet, img2img)
  local stage_latent_ref = nil
  if opts.stage then
    positive_ref, negative_ref, stage_latent_ref = compile_stage(
      g, opts.stage, positive_ref, negative_ref, clip_ref, vae_ref
    )
  end

  -- 5. Latent source
  local latent_ref
  if stage_latent_ref then
    latent_ref = stage_latent_ref
  else
    local size = opt(opts, "size", params.default_size)
    -- Validate dimensions (32-divisibility, pixel limit)
    size = validate_size(size, opts.align32)
    -- Z-Image uses 16-channel latent (EmptySD3LatentImage)
    local empty = g:add("EmptySD3LatentImage", {
      width      = size[1],
      height     = size[2],
      batch_size = 1,
    })
    latent_ref = empty(0)
  end

  -- 6-8. Sampling (variant-dependent)
  local seed = opts.seed
  if not seed then
    seed = math.random(0, 2^32 - 1)
  end

  if turbo then
    -- Turbo: use ZSamplerTurbo (ComfyUI-ZImagePowerNodes)
    -- This node encapsulates the proprietary 3-stage sigma schedule,
    -- noise bias estimation, and euler sampling internally.
    local steps = opt(opts, "steps", preset.steps)
    local denoise = opt(opts, "denoise", 1.0)
    local sampled
    if denoise < 0.98 then
      -- ZSamplerTurbo (standard) has denoise min=0.98 (t2i only).
      -- For I2I (denoise < 0.98), use ZSamplerTurboAdvanced which
      -- supports full denoise range 0.0-1.0.
      sampled = g:add("ZSamplerTurboAdvanced //ZImagePowerNodes", {
        model                    = model_ref,
        positive                 = positive_ref,
        latent_input             = latent_ref,
        seed                     = seed,
        steps                    = steps,
        denoise                  = denoise,
        divider                   = "",
        initial_noise_calibration = 0.0,
        noise_bias_estimation    = "experimental",
        noise_bias_sample_size   = "image_size",
        noise_bias_scale         = 0.12,
        noise_overdose           = 0.33,
      })
    else
      sampled = g:add("ZSamplerTurbo //ZImagePowerNodes", {
        model        = model_ref,
        positive     = positive_ref,
        latent_input = latent_ref,
        seed         = seed,
        steps        = steps,
        denoise      = denoise,
      })
    end
    latent_ref = sampled(0)
  else
    -- Base: use SamplerCustom with KarrasScheduler sigma schedule
    local sigmas_ref = compile_sigmas(g, opts, false)

    local sampler_name = opt(opts, "sampler", preset.sampler)
    local sampler_select = g:add("KSamplerSelect", {
      sampler_name = sampler_name,
    })

    -- SamplerCustom requires negative conditioning.
    local neg_for_sampler = negative_ref
    if not neg_for_sampler then
      local empty_neg = g:add("CLIPTextEncode", {
        clip = clip_ref,
        text = "",
      })
      neg_for_sampler = empty_neg(0)
    end

    local cfg_value = opt(opts, "cfg", preset.cfg)

    local sampled = g:add("SamplerCustom", {
      model        = model_ref,
      add_noise    = true,
      noise_seed   = seed,
      cfg          = cfg_value,
      positive     = positive_ref,
      negative     = neg_for_sampler,
      sampler      = sampler_select(0),
      sigmas       = sigmas_ref,
      latent_image = latent_ref,
    })
    latent_ref = sampled(0)
  end

  -- 9. Resolve post pipeline (explicit > world > hints > none)
  local post = opts.post
  if not post and opts.world.post then
    post = opts.world.post
  end
  if not post and opts.auto_post ~= false then
    local hints = collect_hints(opts.cast)
    if hints then
      post = build_post_from_hints(hints)
    end
  end

  -- 10. Post: latent phase
  if post then
    latent_ref = compile_post_latent(
      g, post, latent_ref,
      model_ref, positive_ref, negative_ref, opts, turbo
    )
  end

  -- 11. VAE Decode
  local decoded = g:add("VAEDecode", {
    samples = latent_ref,
    vae     = vae_ref,
  })
  local image_ref = decoded(0)

  -- 12. Post: pixel phase
  if post then
    local ctx = {
      model    = model_ref,
      clip     = clip_ref,
      vae      = vae_ref,
      positive = positive_ref,
      negative = negative_ref,
      seed     = seed,
      turbo    = turbo,
      opts     = opts,
    }
    image_ref = compile_post_pixel(g, post, image_ref, ctx)
  end

  -- 13. Save
  local prefix = "vdsl_zi"
  if opts.output then
    prefix = opts.output:gsub("%.[^%.]+$", "")
  end
  if opts.gen_id then
    local short = opts.gen_id:sub(1, 8)
    prefix = prefix .. "_" .. short
  end
  g:add("SaveImage", {
    images          = image_ref,
    filename_prefix = prefix,
  })

  local prompt = g:to_prompt()
  return {
    prompt    = prompt,
    json      = json.encode(prompt, true),
    graph     = g,
    variant   = turbo and "turbo" or "base",
    conflicts = {},
  }
end

return M
