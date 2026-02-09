--- Compiler: transforms entity IR into a ComfyUI node graph.
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
local json   = require("vdsl.json")
local Weight = require("vdsl.weight")
local Post   = require("vdsl.post")

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
-- @return model_ref, positive_ref, negative_ref
local function compile_casts(g, casts, model_ref, clip_ref)
  -- Phase 1: Chain all LoRAs from all casts onto model/clip
  for _, cast in ipairs(casts) do
    if cast.lora then
      for _, lora in ipairs(cast.lora) do
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
  end

  -- Phase 2: Encode each cast's prompt
  local pos_refs = {}
  local neg_refs = {}

  for _, cast in ipairs(casts) do
    local prompt_text   = Entity.resolve_text(cast.subject)
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

--- Resolve global negative text from opts.negative and opts.theme.
-- Priority: opts.negative > theme.negatives.default
-- @return string|nil resolved negative text
local function resolve_global_negative(opts)
  if opts.negative then
    return Entity.resolve_text(opts.negative)
  end
  if opts.theme and opts.theme.negatives and opts.theme.negatives.default then
    return Entity.resolve_text(opts.theme.negatives.default)
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

local function compile_stage(g, stage, positive_ref, vae_ref)
  local latent_ref = nil

  if stage.controlnet then
    for _, cn in ipairs(stage.controlnet) do
      local cn_loader = g:add("ControlNetLoader", {
        control_net_name = cn.type,
      })
      local cn_image = g:add("LoadImage", {
        image = cn.image,
      })
      local cn_apply = g:add("ControlNetApply", {
        conditioning = positive_ref,
        control_net  = cn_loader(0),
        image        = cn_image(0),
        strength     = cn.strength,
      })
      positive_ref = cn_apply(0)
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

  return positive_ref, latent_ref
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
-- @return image_ref (updated)
local function compile_post_pixel(g, post, image_ref)
  for _, op in ipairs(post:ops()) do
    if not LATENT_OPS[op.type] then
      local p = op.params

      if op.type == "upscale" then
        -- Model-based upscale
        local loader = g:add("UpscaleModelLoader", {
          model_name = p.model or "4x-UltraSharp.pth",
        })
        local upscaled = g:add("ImageUpscaleWithModel", {
          upscale_model = loader(0),
          image         = image_ref,
        })
        image_ref = upscaled(0)

      elseif op.type == "face" then
        -- Face restoration (CodeFormer/GFPGAN)
        local loader = g:add("FaceRestoreModelLoader", {
          model_name = p.model or "codeformer-v0.1.0.pth",
        })
        local restored = g:add("FaceRestoreWithModel", {
          facerestore_model = loader(0),
          image             = image_ref,
          fidelity          = p.fidelity or 0.5,
        })
        image_ref = restored(0)

      elseif op.type == "color" then
        -- Color correction (brightness, contrast, saturation, gamma)
        local corrected = g:add("ColorCorrect", {
          image      = image_ref,
          brightness = p.brightness or 1.0,
          contrast   = p.contrast or 1.0,
          saturation = p.saturation or 1.0,
          gamma      = p.gamma or 1.0,
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
  hires   = 1,
  refine  = 2,
  upscale = 3,
  face    = 4,
  color   = 5,
  sharpen = 6,
  resize  = 7,
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
  for op_type, params in pairs(hints) do
    sorted[#sorted + 1] = { type = op_type, params = params }
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

--- Resolve a render option: opts > theme.defaults > fallback.
-- @param opts table render options
-- @param key string option key
-- @param fallback any hard-coded default
-- @return any resolved value
local function opt(opts, key, fallback)
  if opts[key] ~= nil then return opts[key] end
  if opts.theme and opts.theme.defaults and opts.theme.defaults[key] ~= nil then
    return opts.theme.defaults[key]
  end
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
  if opts.theme and not Entity.is(opts.theme, "theme") then
    error("render: 'theme' must be a Theme entity", 2)
  end

  ensure_seeded()

  local g = Graph.new()

  -- 1. World
  local model_ref, clip_ref, vae_ref = compile_world(g, opts.world)

  -- 2. Casts (multiple supported, combined via ConditioningCombine)
  local positive_ref, negative_ref
  model_ref, positive_ref, negative_ref = compile_casts(
    g, opts.cast, model_ref, clip_ref
  )

  -- 3. Global negative (opts.negative > theme.negatives.default)
  local global_neg_text = resolve_global_negative(opts)
  negative_ref = compile_global_negative(
    g, global_neg_text, negative_ref, clip_ref
  )

  -- 4. Stage (optional)
  local stage_latent_ref = nil
  if opts.stage then
    positive_ref, stage_latent_ref = compile_stage(
      g, opts.stage, positive_ref, vae_ref
    )
  end

  -- 5. Latent source
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

  -- 6. KSampler
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

  -- 7. Resolve post pipeline (explicit > hints > none)
  local post = opts.post
  if not post and opts.auto_post ~= false then
    local hints = collect_hints(opts.cast)
    if hints then
      post = build_post_from_hints(hints)
    end
  end

  -- 8. Post: latent phase (before VAEDecode)
  if post then
    latent_ref = compile_post_latent(
      g, post, latent_ref,
      model_ref, positive_ref, negative_ref, opts
    )
  end

  -- 9. VAE Decode
  local decoded = g:add("VAEDecode", {
    samples = latent_ref,
    vae     = vae_ref,
  })
  local image_ref = decoded(0)

  -- 10. Post: pixel phase (after VAEDecode)
  if post then
    image_ref = compile_post_pixel(g, post, image_ref)
  end

  -- 11. Save
  local prefix = "vdsl"
  if opts.output then
    prefix = opts.output:gsub("%.[^%.]+$", "")
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

return M
