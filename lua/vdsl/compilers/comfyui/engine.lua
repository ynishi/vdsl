--- ComfyUI Compiler Engine: transforms entity IR into a ComfyUI node graph.
-- render opts -> Graph -> ComfyUI prompt table -> JSON
--
-- Pipeline:
--   World → Casts (combined) → Global Negative → Stage → Latent → KSampler
--   → [Post latent ops] → VAEDecode → [Post pixel ops] → SaveImage
--
-- ComfyUI-specific mappings are isolated here.
-- Entity layer remains domain-general.

local Entity = require("vdsl.entity")
local Graph  = require("vdsl.graph")
local json   = require("vdsl.util.json")
local Weight = require("vdsl.weight")
local Post   = require("vdsl.post")
local params = require("vdsl.compilers.comfyui.parameters")

local M = {}

-- Lazy RNG seeding: deferred to first compile() that needs randomness.
-- Avoids polluting global RNG state at require() time.
local _rng_seeded = false
local function ensure_seeded()
  if not _rng_seeded then
    math.randomseed(os.time())
    _rng_seeded = true
  end
end

-- ============================================================
-- Post-processing phase classification
-- Latent ops execute before VAEDecode, pixel ops after.
-- ============================================================

local LATENT_OPS = { hires = true, refine = true }

-- ============================================================
-- Prompt ordering strategies
-- Each strategy is an ordered list of prompt segments.
-- "subject", "style", "detail" → Subject category groups
-- "atmosphere" → Atmosphere entity text (inserted between groups)
--
-- Based on SDXL prompt research:
--   - CLIP effective length ~20 tokens (Long-CLIP 2024)
--   - Earlier tokens structurally more influential (SOS attention)
--   - Community consensus: subject first, quality last
-- ============================================================

local STRATEGIES = {
  -- subject → style → detail → atmosphere → quality
  -- Rationale:
  --   First 20 tokens = subject identity + style (most semantically critical)
  --   Middle = scene details + emotional tone
  --   End = quality modifiers (trigger trained quality modes, position-insensitive)
  recommended = { "subject", "style", "detail", "atmosphere", "quality" },
}

--- Assemble prompt text from subject + atmosphere using strategy.
-- @param subject Subject entity
-- @param atmosphere_text string|nil resolved atmosphere text
-- @param strategy string|nil strategy name (nil = natural order)
-- @return string
local function assemble_prompt(subject, atmosphere_text, strategy)
  if not strategy or not STRATEGIES[strategy] then
    -- Natural order: subject traits as-is, atmosphere appended
    local text = Entity.resolve_text(subject)
    if atmosphere_text and atmosphere_text ~= "" then
      text = text .. ", " .. atmosphere_text
    end
    return text
  end

  local order = STRATEGIES[strategy]
  local groups = subject:resolve_grouped()
  local parts = {}
  for _, segment in ipairs(order) do
    if segment == "atmosphere" then
      if atmosphere_text and atmosphere_text ~= "" then
        parts[#parts + 1] = atmosphere_text
      end
    else
      local group = groups[segment]
      if group and #group > 0 then
        parts[#parts + 1] = table.concat(group, ", ")
      end
    end
  end
  return table.concat(parts, ", ")
end

-- ============================================================
-- World compilation
-- ============================================================

local function compile_world(g, world)
  local ckpt = g:add("CheckpointLoaderSimple", {
    ckpt_name = world.model,
  })
  local model_ref = ckpt(0)
  local clip_ref  = ckpt(1)
  local vae_ref   = ckpt(2)

  if world.vae then
    local vae_node = g:add("VAELoader", {
      vae_name = world.vae,
    })
    vae_ref = vae_node(0)
  end

  if world.clip_skip > 1 then
    local clip_set = g:add("CLIPSetLastLayer", {
      clip = clip_ref,
      stop_at_clip_layer = -world.clip_skip,
    })
    clip_ref = clip_set(0)
  end

  return model_ref, clip_ref, vae_ref
end

-- ============================================================
-- Cast compilation (supports multiple casts)
-- ============================================================

--- Compile multiple Cast entities. Chains all LoRAs, encodes each prompt,
-- combines conditionings with ConditioningCombine when multiple.
-- @param world World entity (for world.lora model-level LoRA)
-- @param atmosphere_text string|nil resolved atmosphere prompt text
-- @param strategy string|nil prompt ordering strategy
-- @return model_ref, positive_ref, negative_ref
local function compile_casts(g, casts, model_ref, clip_ref, world, atmosphere_text, strategy)
  -- Phase 0: World LoRA (model-level correction, applied before cast LoRAs)
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
    end
  end

  -- Phase 1: Resolve LoRAs from casts.
  -- Priority: cast.lora (full spec) > hint("lora") resolved via world.
  -- Deduplication: track loaded filenames to avoid double-loading.
  local loaded_loras = {}
  -- Mark world-level LoRAs as already loaded
  if world.lora then
    for _, entry in ipairs(world.lora) do
      loaded_loras[entry.name] = true
    end
  end

  for _, cast in ipairs(casts) do
    -- 1a. Explicit cast.lora (full specification — escape hatch)
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

    -- 1b. hint("lora") — resolve via World:resolve_lora()
    local subj = cast.subject
    if subj and type(subj.hints) == "function" then
      local hints = subj:hints()
      if hints and hints.lora then
        local hint_val = hints.lora
        local resolved = nil
        if type(hint_val) == "string" then
          -- Fuzzy key → World resolver
          resolved = world:resolve_lora(hint_val)
        elseif type(hint_val) == "table" and hint_val.name then
          -- Full spec in hint (direct)
          resolved = hint_val
        end
        if resolved and not loaded_loras[resolved.name] then
          local w = Weight.resolve(resolved.weight, 1.0)
          local lora_node = g:add("LoraLoader", {
            model          = model_ref,
            clip           = clip_ref,
            lora_name      = resolved.name,
            strength_model = w,
            strength_clip  = w,
          })
          model_ref = lora_node(0)
          clip_ref  = lora_node(1)
          loaded_loras[resolved.name] = true
        end
      end
    end
  end

  -- Phase 2: Encode each cast's prompt
  local pos_refs = {}
  local neg_refs = {}

  for _, cast in ipairs(casts) do
    local prompt_text   = assemble_prompt(cast.subject, atmosphere_text, strategy)
    local negative_text = Entity.resolve_text(cast.negative)

    local pos = g:add("CLIPTextEncode", {
      clip = clip_ref,
      text = prompt_text,
    })
    pos_refs[#pos_refs + 1] = pos(0)

    local neg = g:add("CLIPTextEncode", {
      clip = clip_ref,
      text = negative_text,
    })
    neg_refs[#neg_refs + 1] = neg(0)

    -- IPAdapter
    if cast.ipadapter then
      local ipa_w = Weight.resolve(cast.ipadapter.weight, 1.0)
      local load_img = g:add("LoadImage", {
        image = cast.ipadapter.image,
      })
      local ipa = g:add("IPAdapterApply", {
        model  = model_ref,
        image  = load_img(0),
        weight = ipa_w,
      })
      model_ref = ipa(0)
    end
  end

  -- Phase 3: Combine conditionings (single cast = no combine needed)
  local pos_ref = pos_refs[1]
  for i = 2, #pos_refs do
    local combine = g:add("ConditioningCombine", {
      conditioning_1 = pos_ref,
      conditioning_2 = pos_refs[i],
    })
    pos_ref = combine(0)
  end

  local neg_ref = neg_refs[1]
  for i = 2, #neg_refs do
    local combine = g:add("ConditioningCombine", {
      conditioning_1 = neg_ref,
      conditioning_2 = neg_refs[i],
    })
    neg_ref = combine(0)
  end

  return model_ref, pos_ref, neg_ref
end

-- ============================================================
-- Global negative compilation
-- ============================================================

--- Resolve global negative text from opts.negative.
-- @return string|nil resolved negative text
local function resolve_global_negative(opts)
  if opts.negative then
    return Entity.resolve_text(opts.negative)
  end
  return nil
end

--- Compile global negative: encode and combine with existing negative_ref.
-- @return negative_ref (updated)
local function compile_global_negative(g, neg_text, negative_ref, clip_ref)
  if not neg_text or neg_text == "" then
    return negative_ref
  end
  local global_neg = g:add("CLIPTextEncode", {
    clip = clip_ref,
    text = neg_text,
  })
  local combined = g:add("ConditioningCombine", {
    conditioning_1 = negative_ref,
    conditioning_2 = global_neg(0),
  })
  return combined(0)
end

-- ============================================================
-- Stage compilation
-- ============================================================

local function compile_stage(g, stage, positive_ref, negative_ref, vae_ref)
  local latent_ref = nil

  if stage.controlnet then
    for _, cn in ipairs(stage.controlnet) do
      local cn_loader = g:add("ControlNetLoader", {
        control_net_name = cn.type,
      })

      local cn_image = g:add("LoadImage", {
        image = cn.image,
      })
      local image_ref = cn_image(0)

      -- Insert preprocessor node if specified
      if cn.preprocessor then
        local pp = params.preprocessors[cn.preprocessor]
        if pp then
          local pp_params = {}
          for k, v in pairs(pp.params) do pp_params[k] = v end
          pp_params.image = image_ref
          pp_params.resolution = 1024
          local preprocessed = g:add(pp.node, pp_params)
          image_ref = preprocessed(0)
        end
      end

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
    local init_img = g:add("LoadImage", {
      image = stage.latent_image,
    })
    local encoded = g:add("VAEEncode", {
      pixels = init_img(0),
      vae    = vae_ref,
    })
    latent_ref = encoded(0)
  end

  return positive_ref, negative_ref, latent_ref
end

-- ============================================================
-- Post-processing compilation
-- ============================================================

--- Compile latent-phase post ops (before VAEDecode).
-- @return latent_ref (updated)
local function compile_post_latent(g, post, latent_ref, model_ref, pos_ref, neg_ref, opts)
  for _, op in ipairs(post:ops()) do
    if LATENT_OPS[op.type] then
      local p = op.params
      local seed = opts.seed
      if seed then seed = seed + 1 end

      if op.type == "hires" then
        -- Latent upscale + 2nd KSampler
        local upscaled = g:add("LatentUpscaleBy", {
          samples        = latent_ref,
          upscale_method = p.method or "nearest-exact",
          scale_by       = p.scale or 1.5,
        })
        local resampled = g:add("KSampler", {
          model        = model_ref,
          positive     = pos_ref,
          negative     = neg_ref,
          latent_image = upscaled(0),
          seed         = seed or math.random(0, 2^32 - 1),
          steps        = p.steps or 10,
          cfg          = p.cfg or opts.cfg or 7.0,
          sampler_name = p.sampler or opts.sampler or "euler",
          scheduler    = p.scheduler or opts.scheduler or "normal",
          denoise      = p.denoise or 0.4,
        })
        latent_ref = resampled(0)

      elseif op.type == "refine" then
        -- 2nd KSampler at same resolution (different sampler/cfg/denoise)
        local refined = g:add("KSampler", {
          model        = model_ref,
          positive     = pos_ref,
          negative     = neg_ref,
          latent_image = latent_ref,
          seed         = seed or math.random(0, 2^32 - 1),
          steps        = p.steps or 10,
          cfg          = p.cfg or opts.cfg or 7.0,
          sampler_name = p.sampler or opts.sampler or "euler",
          scheduler    = p.scheduler or opts.scheduler or "normal",
          denoise      = p.denoise or 0.3,
        })
        latent_ref = refined(0)
      end
    end
  end
  return latent_ref
end

--- Compile pixel-phase post ops (after VAEDecode).
-- ctx carries pipeline refs needed by FaceDetailer (model, clip, vae, etc.).
-- @param ctx table|nil { model, clip, vae, positive, negative, seed, opts }
-- @return image_ref (updated)
local function compile_post_pixel(g, post, image_ref, ctx)
  for _, op in ipairs(post:ops()) do
    if not LATENT_OPS[op.type] then
      local p = op.params

      if op.type == "upscale" then
        -- Model-based upscale
        local loader = g:add("UpscaleModelLoader", {
          model_name = p.model or params.upscale_model,
        })
        local upscaled = g:add("ImageUpscaleWithModel", {
          upscale_model = loader(0),
          image         = image_ref,
        })
        image_ref = upscaled(0)

      elseif op.type == "face" then
        -- Face restoration (CodeFormer/GFPGAN)
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
        -- EllangoK ComfyUI-post-processing-nodes "ColorCorrect"
        -- VDSL API: multiplier (1.0 = no change, 1.1 = +10%)
        -- Node API: offset (-100..100, 0 = no change) for brightness/contrast/saturation
        --           gamma is direct (0.2..2.2, 1.0 = no change)
        --           temperature (-100..100), hue (-90..90) are offset (0 = no change)
        local function mul_to_offset(v, default)
          if v == nil then return 0 end
          -- Round to 1 decimal to avoid IEEE 754 drift (e.g. 1.1→10.0000000000001)
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
        -- Image sharpening
        local sharpened = g:add("ImageSharpen", {
          image          = image_ref,
          sharpen_radius = p.radius or 1,
          sigma          = p.sigma or 1.0,
          alpha          = p.alpha or 1.0,
        })
        image_ref = sharpened(0)

      elseif op.type == "resize" then
        -- Resize: by scale factor or to exact dimensions
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
        -- FaceDetailer (Impact Pack): detect region → crop → re-diffuse → paste.
        -- Requires UltralyticsDetectorProvider (Impact Subpack).
        local detector_key  = p.detector or "face"
        local detector_model = params.detectors[detector_key]
          or params.detectors.face

        local detector = g:add("UltralyticsDetectorProvider", {
          model_name = detector_model,
        })

        local is_segm = detector_model:match("^segm/") ~= nil

        local fd_seed = ctx.seed
        if fd_seed then fd_seed = fd_seed + 100 end

        -- Prompt override for the re-diffusion pass.
        -- Accepts string, Trait, or Subject (resolved via Entity.resolve_text).
        -- FaceDetailer re-generates the detected region, so it implicitly
        -- references the Subject's appearance.  Passing Trait/Subject here
        -- lets callers compose from the same entities used in the main
        -- pipeline, avoiding manual prompt duplication.
        local fd_positive = ctx.positive
        local fd_negative = ctx.negative
        if p.prompt then
          fd_positive = g:add("CLIPTextEncode", {
            clip = ctx.clip,
            text = Entity.resolve_text(p.prompt),
          })(0)
        end
        if p.negative then
          fd_negative = g:add("CLIPTextEncode", {
            clip = ctx.clip,
            text = Entity.resolve_text(p.negative),
          })(0)
        end

        local fd_params = {
          image            = image_ref,
          model            = ctx.model,
          clip             = ctx.clip,
          vae              = ctx.vae,
          positive         = fd_positive,
          negative         = fd_negative,
          guide_size       = p.guide or 512,
          guide_size_for   = true,
          max_size         = p.max_size or 1024,
          seed             = fd_seed or math.random(0, 2^32 - 1),
          steps            = p.steps or 20,
          cfg              = p.cfg or ctx.opts.cfg or 7.0,
          sampler_name     = p.sampler or ctx.opts.sampler or "euler",
          scheduler        = p.scheduler or ctx.opts.scheduler or "normal",
          denoise          = p.denoise or 0.4,
          feather          = p.feather or 5,
          noise_mask       = true,
          force_inpaint    = true,
          bbox_threshold   = p.bbox_threshold or 0.5,
          bbox_dilation    = p.bbox_dilation or 10,
          bbox_crop_factor = p.bbox_crop_factor or 3.0,
          sam_detection_hint       = "center-1",
          sam_dilation             = 0,
          sam_threshold            = 0.93,
          sam_bbox_expansion       = 0,
          sam_mask_hint_threshold  = 0.7,
          sam_mask_hint_use_negative = "False",
          drop_size        = p.drop_size or 10,
          bbox_detector    = detector(0),
          wildcard         = "",
          cycle            = p.cycle or 1,
        }

        -- Connect precise segmentation output for segm models
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

--- Deterministic ordering for hint types.
-- Latent ops first, then pixel ops in a sensible pipeline order.
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

--- Collect merged hints from all casts' subjects.
-- @param casts table list of Cast entities
-- @return table|nil merged { op_type = params } or nil
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

--- Build a Post entity from collected hints.
-- @param hints table { op_type = params }
-- @return Post
local function build_post_from_hints(hints)
  -- Sort by pipeline order
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
-- Theme defaults resolution
-- ============================================================

--- Resolve a render option: opts > world > fallback.
-- @param opts table render options
-- @param key string option key
-- @param fallback any hard-coded default
-- @return any resolved value
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
  if opts.atmosphere and not Entity.is(opts.atmosphere, "trait") then
    error("render: 'atmosphere' must be a Trait entity", 2)
  end
  if opts.strategy then
    if type(opts.strategy) ~= "string" then
      error("render: 'strategy' must be a string", 2)
    end
    if not STRATEGIES[opts.strategy] then
      error("render: unknown strategy '" .. opts.strategy
        .. "', available: recommended", 2)
    end
  end

  ensure_seeded()

  local g = Graph.new()

  -- 1. World
  local model_ref, clip_ref, vae_ref = compile_world(g, opts.world)

  -- 2. Atmosphere (resolved once, applied to all casts)
  local atmosphere_text = nil
  if opts.atmosphere then
    atmosphere_text = Entity.resolve_text(opts.atmosphere)
  end

  -- 3. Casts (multiple supported, combined via ConditioningCombine)
  local positive_ref, negative_ref
  model_ref, positive_ref, negative_ref = compile_casts(
    g, opts.cast, model_ref, clip_ref, opts.world, atmosphere_text, opts.strategy
  )

  -- 4. Global negative (opts.negative)
  local global_neg_text = resolve_global_negative(opts)
  negative_ref = compile_global_negative(
    g, global_neg_text, negative_ref, clip_ref
  )

  -- 5. Stage (optional)
  local stage_latent_ref = nil
  if opts.stage then
    positive_ref, negative_ref, stage_latent_ref = compile_stage(
      g, opts.stage, positive_ref, negative_ref, vae_ref
    )
  end

  -- 6. Latent source
  local latent_ref
  if stage_latent_ref then
    latent_ref = stage_latent_ref
  else
    local size = opt(opts, "size", { 512, 512 })
    local empty = g:add("EmptyLatentImage", {
      width      = size[1],
      height     = size[2],
      batch_size = 1,
    })
    latent_ref = empty(0)
  end

  -- 7. KSampler
  local seed = opts.seed
  if not seed then
    seed = math.random(0, 2^32 - 1)
  end

  local denoise_default = stage_latent_ref and 0.7 or 1.0

  local sampler = g:add("KSampler", {
    model        = model_ref,
    positive     = positive_ref,
    negative     = negative_ref,
    latent_image = latent_ref,
    seed         = seed,
    steps        = opt(opts, "steps", 20),
    cfg          = opt(opts, "cfg", 7.0),
    sampler_name = opt(opts, "sampler", "euler"),
    scheduler    = opt(opts, "scheduler", "normal"),
    denoise      = opts.denoise or denoise_default,
  })
  latent_ref = sampler(0)

  -- 8. Resolve post pipeline (explicit > world > hints > none)
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

  -- 9. Post: latent phase (before VAEDecode)
  if post then
    latent_ref = compile_post_latent(
      g, post, latent_ref,
      model_ref, positive_ref, negative_ref, opts
    )
  end

  -- 10. VAE Decode
  local decoded = g:add("VAEDecode", {
    samples = latent_ref,
    vae     = vae_ref,
  })
  local image_ref = decoded(0)

  -- 11. Post: pixel phase (after VAEDecode)
  if post then
    local ctx = {
      model    = model_ref,
      clip     = clip_ref,
      vae      = vae_ref,
      positive = positive_ref,
      negative = negative_ref,
      seed     = seed,
      opts     = opts,
    }
    image_ref = compile_post_pixel(g, post, image_ref, ctx)
  end

  -- 12. Save
  local prefix = "vdsl"
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
    prompt = prompt,
    json   = json.encode(prompt, true),
    graph  = g,
  }
end

-- ============================================================
-- Prompt token analysis
-- ============================================================

-- CLIP BPE token estimation constants
local CLIP_CHUNK_SIZE  = 75   -- usable tokens per chunk (77 - BOS - EOS)
local CLIP_SWEET_SPOT  = 20   -- highest-influence token range (Long-CLIP 2024)
local CLIP_WARN_MULTI  = 75   -- multi-chunk threshold
local CLIP_WARN_DILUTE = 150  -- quality dilution threshold

-- Punctuation that CLIP BPE tokenizes as individual tokens.
local PUNCT = {
  ["("] = true, [")"] = true, [":"] = true, [","] = true,
  ["."] = true, ["!"] = true, ["?"] = true, [";"] = true,
}

--- Estimate CLIP BPE token count from prompt text.
-- Approximation (±15%) without the actual BPE vocabulary.
-- Words → 1 token each, punctuation → 1 token each.
-- Real CLIP may split uncommon words into subword tokens.
-- @param text string prompt text
-- @return number estimated token count (excludes BOS/EOS)
function M.estimate_tokens(text)
  if not text or text == "" then return 0 end
  local count = 0
  local i = 1
  local len = #text
  while i <= len do
    local c = text:sub(i, i)
    if c == " " or c == "\t" or c == "\n" then
      i = i + 1
    elseif PUNCT[c] then
      count = count + 1
      i = i + 1
    else
      -- Word: consume until whitespace or punctuation
      count = count + 1
      i = i + 1
      while i <= len do
        local nc = text:sub(i, i)
        if nc == " " or nc == "\t" or nc == "\n" or PUNCT[nc] then
          break
        end
        i = i + 1
      end
    end
  end
  return count
end

--- Analyze prompt token usage for render opts.
-- Returns diagnostics without building a ComfyUI graph.
--
-- @param opts table render options (same as vdsl.render)
-- @return table {
--   casts = { [i] = { positive = {...}, negative = {...}, budget = {...} } },
--   warnings = { "string", ... },
--   suggestions = { "string", ... },
--   limits = { chunk_size, sweet_spot },
-- }
function M.check(opts)
  if not opts then
    return { casts = {}, warnings = { "No opts provided" }, suggestions = {} }
  end
  if not opts.cast or #opts.cast == 0 then
    return { casts = {}, warnings = { "No casts provided" }, suggestions = {} }
  end

  -- Resolve atmosphere
  local atmosphere_text = nil
  if opts.atmosphere then
    atmosphere_text = Entity.resolve_text(opts.atmosphere)
  end

  local casts = {}
  local warnings = {}
  local suggestions = {}

  for ci, cast in ipairs(opts.cast) do
    local pos_text = assemble_prompt(cast.subject, atmosphere_text, opts.strategy)
    local neg_text = Entity.resolve_text(cast.negative)

    local pos_tokens = M.estimate_tokens(pos_text)
    local neg_tokens = M.estimate_tokens(neg_text)
    local pos_chunks = math.ceil(math.max(pos_tokens, 1) / CLIP_CHUNK_SIZE)
    local neg_chunks = math.ceil(math.max(neg_tokens, 1) / CLIP_CHUNK_SIZE)

    -- Token budget by category
    local budget = {}
    if Entity.is(cast.subject, "subject") and cast.subject.resolve_grouped then
      local groups = cast.subject:resolve_grouped()
      local order = { "subject", "style", "detail", "quality" }
      for _, cat in ipairs(order) do
        if groups[cat] then
          local cat_text = table.concat(groups[cat], ", ")
          budget[#budget + 1] = {
            category = cat,
            text     = cat_text,
            tokens   = M.estimate_tokens(cat_text),
          }
        end
      end
    end
    if atmosphere_text then
      budget[#budget + 1] = {
        category = "atmosphere",
        text     = atmosphere_text,
        tokens   = M.estimate_tokens(atmosphere_text),
      }
    end

    casts[ci] = {
      positive = { text = pos_text, estimated_tokens = pos_tokens, chunks = pos_chunks },
      negative = { text = neg_text, estimated_tokens = neg_tokens, chunks = neg_chunks },
      budget   = budget,
    }

    -- Warnings
    if pos_tokens > CLIP_WARN_DILUTE then
      warnings[#warnings + 1] = string.format(
        "cast[%d] positive: ~%d tokens (>%d). Quality dilution risk — consider reducing.",
        ci, pos_tokens, CLIP_WARN_DILUTE)
    elseif pos_tokens > CLIP_WARN_MULTI then
      warnings[#warnings + 1] = string.format(
        "cast[%d] positive: ~%d tokens (%d chunks). Cross-chunk context is lost in CLIP.",
        ci, pos_tokens, pos_chunks)
    end

    if neg_tokens > CLIP_WARN_MULTI then
      warnings[#warnings + 1] = string.format(
        "cast[%d] negative: ~%d tokens (%d chunks).",
        ci, neg_tokens, neg_chunks)
    end

    -- First-chunk content analysis
    if pos_tokens > 0 and #budget > 0 then
      local first_chunk_tokens = 0
      local first_chunk_cats = {}
      for _, b in ipairs(budget) do
        if first_chunk_tokens + b.tokens <= CLIP_CHUNK_SIZE then
          first_chunk_tokens = first_chunk_tokens + b.tokens
          first_chunk_cats[#first_chunk_cats + 1] = b.category
        else
          break
        end
      end
      -- Warn if subject isn't fully in first chunk
      if budget[1] and budget[1].category == "subject"
         and budget[1].tokens > CLIP_CHUNK_SIZE then
        warnings[#warnings + 1] = string.format(
          "cast[%d]: subject alone is ~%d tokens (exceeds chunk size %d).",
          ci, budget[1].tokens, CLIP_CHUNK_SIZE)
      end
    end
  end

  -- Trait confidence / tag diagnostics
  for ci, cast in ipairs(opts.cast) do
    local subj = cast.subject
    if Entity.is(subj, "subject") and type(subj.trait_diagnostics) == "function" then
      local diags = subj:trait_diagnostics()
      local has_lora = (cast.lora and #cast.lora > 0)
        or (opts.world and opts.world._lora_map ~= nil)
      -- Also check if any trait has hint("lora")
      if not has_lora then
        local subj_hints = type(subj.hints) == "function" and subj:hints()
        has_lora = subj_hints and subj_hints.lora ~= nil
      end

      for _, d in ipairs(diags) do
        -- Low confidence warning
        if d.confidence < 0.5 then
          local msg = string.format(
            "cast[%d] trait \"%s\": confidence %.2f (low).",
            ci, d.text, d.confidence)
          warnings[#warnings + 1] = msg
        end

        -- Hint: benefits_from — suggest resource if not present
        local bf = d.hints and d.hints.benefits_from
        if bf and bf.resource == "lora" and not has_lora then
          suggestions[#suggestions + 1] = string.format(
            "cast[%d] trait \"%s\": quality improves with a LoRA (none configured).",
            ci, d.text)
        end
      end
    end
  end

  -- Suggestions
  if not opts.strategy and opts.atmosphere then
    suggestions[#suggestions + 1] =
      "strategy = \"recommended\" optimizes token order (subject+style first, quality last)."
  end

  for ci, c in ipairs(casts) do
    if c.positive.estimated_tokens > CLIP_WARN_MULTI and c.positive.estimated_tokens <= CLIP_WARN_DILUTE then
      suggestions[#suggestions + 1] = string.format(
        "cast[%d]: use BREAK in prompt text to control chunk boundaries.",
        ci)
    end
  end

  return {
    casts       = casts,
    warnings    = warnings,
    suggestions = suggestions,
    limits      = {
      chunk_size = CLIP_CHUNK_SIZE,
      sweet_spot = CLIP_SWEET_SPOT,
    },
  }
end

return M
