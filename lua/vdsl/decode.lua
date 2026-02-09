--- Decode: reconstruct vdsl information from a ComfyUI prompt table.
-- Walks the node graph backwards from SaveImage to extract:
--   world, casts, sampler, stage, post, size
--
-- Best-effort reconstruction. See registry.lua [SPEC] decode for limitations.
--
-- Usage:
--   local decode = require("vdsl.decode")
--   local info = decode(comfy_prompt)
--   -- info.world.model, info.casts[1].prompt, info.sampler.steps, ...

local M = {}

-- ============================================================
-- Internal: node index helpers
-- ============================================================

--- Resolve a node reference to its target node.
-- ComfyUI refs are ["node_id", slot] or just literal values.
-- @param prompt table full prompt
-- @param ref any input value (may be a ref or literal)
-- @return table|nil node, string|nil node_id
local function deref(prompt, ref)
  if type(ref) == "table" and type(ref[1]) == "string" and type(ref[2]) == "number" then
    local node_id = ref[1]
    return prompt[node_id], node_id
  end
  return nil, nil
end

--- Check if a value is a node reference.
local function is_ref(v)
  return type(v) == "table" and type(v[1]) == "string" and type(v[2]) == "number"
end

--- Build a reverse lookup: class_type → list of { id, node }.
local function index_by_type(prompt)
  local idx = {}
  for id, node in pairs(prompt) do
    local ct = node.class_type
    if not idx[ct] then idx[ct] = {} end
    idx[ct][#idx[ct] + 1] = { id = id, node = node }
  end
  return idx
end

--- Find all nodes of a given class_type.
local function find_nodes(idx, class_type)
  return idx[class_type] or {}
end

--- Find exactly one node (nil if 0 or >1).
local function find_one(idx, class_type)
  local nodes = find_nodes(idx, class_type)
  if #nodes == 1 then return nodes[1] end
  return nil
end

-- ============================================================
-- World reconstruction
-- ============================================================

local function decode_world(prompt, idx)
  local ckpt_entries = find_nodes(idx, "CheckpointLoaderSimple")
  if #ckpt_entries == 0 then return nil end

  local ckpt = ckpt_entries[1].node
  local world = {
    model     = ckpt.inputs.ckpt_name,
    vae       = nil,
    clip_skip = 1,
  }

  -- Custom VAE?
  local vae_entries = find_nodes(idx, "VAELoader")
  if #vae_entries > 0 then
    world.vae = vae_entries[1].node.inputs.vae_name
  end

  -- CLIP skip?
  local clip_entries = find_nodes(idx, "CLIPSetLastLayer")
  if #clip_entries > 0 then
    local stop = clip_entries[1].node.inputs.stop_at_clip_layer
    if type(stop) == "number" and stop < 0 then
      world.clip_skip = -stop
    end
  end

  return world
end

-- ============================================================
-- Cast reconstruction
-- ============================================================

--- Unwind a ConditioningCombine chain into leaf CLIPTextEncode refs.
-- The compiler builds a left-folded chain:
--   Combine(Combine(A, B), C) → leaves in order [A, B, C]
local function unwind_conditioning(prompt, ref)
  if not is_ref(ref) then return {} end

  local node = prompt[ref[1]]
  if not node then return {} end

  if node.class_type == "ConditioningCombine" then
    local left  = unwind_conditioning(prompt, node.inputs.conditioning_1)
    local right = unwind_conditioning(prompt, node.inputs.conditioning_2)
    for _, v in ipairs(right) do
      left[#left + 1] = v
    end
    return left
  elseif node.class_type == "CLIPTextEncode" then
    return { { ref = ref, text = node.inputs.text } }
  elseif node.class_type == "ControlNetApply" then
    -- ControlNet modifies conditioning; trace through
    return unwind_conditioning(prompt, node.inputs.conditioning)
  end

  return {}
end

--- Collect LoRA chain from model input, walking backwards.
local function collect_loras(prompt, model_ref)
  local loras = {}

  local ref = model_ref
  while is_ref(ref) do
    local node = prompt[ref[1]]
    if not node then break end
    if node.class_type == "LoraLoader" then
      -- Prepend (we walk backwards, so reverse order)
      table.insert(loras, 1, {
        name   = node.inputs.lora_name,
        weight = node.inputs.strength_model,
      })
      ref = node.inputs.model
    else
      break
    end
  end

  return loras
end

local function decode_casts(prompt, idx, ksampler_node)
  if not ksampler_node then return {}, {} end

  local inputs = ksampler_node.inputs

  -- Unwind positive conditioning chain
  local pos_leaves = unwind_conditioning(prompt, inputs.positive)
  -- Unwind negative conditioning chain
  local neg_leaves = unwind_conditioning(prompt, inputs.negative)

  -- Collect LoRAs from model chain
  local loras = collect_loras(prompt, inputs.model)

  -- IPAdapter detection
  local ipadapter = nil
  local ipa_entries = find_nodes(idx, "IPAdapterApply")
  if #ipa_entries > 0 then
    local ipa_node = ipa_entries[1].node
    ipadapter = { weight = ipa_node.inputs.weight }
    -- Trace image source
    if is_ref(ipa_node.inputs.image) then
      local img_node = prompt[ipa_node.inputs.image[1]]
      if img_node and img_node.class_type == "LoadImage" then
        ipadapter.image = img_node.inputs.image
      end
    end
  end

  -- Build cast list.
  -- Heuristic: pos_leaves and neg_leaves are in corresponding order.
  -- Global negative (from opts.negative or theme) is extra entries at the end
  -- of neg_leaves beyond the positive count.
  local cast_count = #pos_leaves
  local casts = {}

  for i = 1, cast_count do
    local cast = {
      prompt   = pos_leaves[i] and pos_leaves[i].text or "",
      negative = neg_leaves[i] and neg_leaves[i].text or "",
    }
    casts[#casts + 1] = cast
  end

  -- Attach loras to first cast (attribution is lossy, all loras are chained)
  if #casts > 0 and #loras > 0 then
    casts[1].loras = loras
  end

  -- Attach ipadapter to first cast
  if #casts > 0 and ipadapter then
    casts[1].ipadapter = ipadapter
  end

  -- Global negative: extra neg_leaves beyond cast count
  local global_negatives = {}
  for i = cast_count + 1, #neg_leaves do
    global_negatives[#global_negatives + 1] = neg_leaves[i].text
  end

  return casts, global_negatives
end

-- ============================================================
-- Sampler reconstruction
-- ============================================================

--- Find the "primary" KSampler (the first one in the pipeline).
-- In multi-KSampler scenarios (hires/refine), the primary is the one
-- whose latent_image traces to EmptyLatentImage or VAEEncode.
local function find_primary_ksampler(prompt, idx)
  local ksamplers = find_nodes(idx, "KSampler")
  if #ksamplers == 0 then return nil end
  if #ksamplers == 1 then return ksamplers[1].node end

  -- Find which KSampler connects to EmptyLatentImage or VAEEncode
  for _, entry in ipairs(ksamplers) do
    local latent_ref = entry.node.inputs.latent_image
    if is_ref(latent_ref) then
      local src = prompt[latent_ref[1]]
      if src and (src.class_type == "EmptyLatentImage"
              or src.class_type == "VAEEncode") then
        return entry.node
      end
    end
  end

  -- Fallback: return lowest-id KSampler (IDs may be non-numeric strings)
  table.sort(ksamplers, function(a, b)
    local na, nb = tonumber(a.id), tonumber(b.id)
    if na and nb then return na < nb end
    return tostring(a.id) < tostring(b.id)
  end)
  return ksamplers[1].node
end

local function decode_sampler(ksampler_node)
  if not ksampler_node then return nil end
  local inp = ksampler_node.inputs
  return {
    seed      = inp.seed,
    steps     = inp.steps,
    cfg       = inp.cfg,
    sampler   = inp.sampler_name,
    scheduler = inp.scheduler,
    denoise   = inp.denoise,
  }
end

-- ============================================================
-- Stage reconstruction
-- ============================================================

local function decode_stage(prompt, idx)
  local cn_entries = find_nodes(idx, "ControlNetApply")
  local vae_enc_entries = find_nodes(idx, "VAEEncode")

  if #cn_entries == 0 and #vae_enc_entries == 0 then
    return nil
  end

  local stage = {}

  -- ControlNets
  if #cn_entries > 0 then
    stage.controlnet = {}
    for _, entry in ipairs(cn_entries) do
      local cn_node = entry.node
      local cn = { strength = cn_node.inputs.strength }

      -- Trace control_net → ControlNetLoader
      if is_ref(cn_node.inputs.control_net) then
        local loader = prompt[cn_node.inputs.control_net[1]]
        if loader and loader.class_type == "ControlNetLoader" then
          cn.type = loader.inputs.control_net_name
        end
      end

      -- Trace image → LoadImage
      if is_ref(cn_node.inputs.image) then
        local img_node = prompt[cn_node.inputs.image[1]]
        if img_node and img_node.class_type == "LoadImage" then
          cn.image = img_node.inputs.image
        end
      end

      stage.controlnet[#stage.controlnet + 1] = cn
    end
  end

  -- Latent image (img2img via VAEEncode)
  if #vae_enc_entries > 0 then
    local enc = vae_enc_entries[1].node
    if is_ref(enc.inputs.pixels) then
      local img_node = prompt[enc.inputs.pixels[1]]
      if img_node and img_node.class_type == "LoadImage" then
        stage.latent_image = img_node.inputs.image
      end
    end
  end

  return stage
end

-- ============================================================
-- Post reconstruction
-- ============================================================

--- Detect latent-phase post ops (extra KSamplers beyond primary).
local function decode_post_latent(prompt, idx, primary_ksampler)
  local ops = {}
  local ksamplers = find_nodes(idx, "KSampler")
  if #ksamplers <= 1 then return ops end

  for _, entry in ipairs(ksamplers) do
    if entry.node ~= primary_ksampler then
      local inp = entry.node.inputs
      -- Check if preceded by LatentUpscaleBy
      local is_hires = false
      if is_ref(inp.latent_image) then
        local src = prompt[inp.latent_image[1]]
        if src and src.class_type == "LatentUpscaleBy" then
          is_hires = true
          ops[#ops + 1] = {
            type   = "hires",
            params = {
              scale   = src.inputs.scale_by,
              method  = src.inputs.upscale_method,
              steps   = inp.steps,
              cfg     = inp.cfg,
              sampler = inp.sampler_name,
              denoise = inp.denoise,
            },
          }
        end
      end

      if not is_hires then
        ops[#ops + 1] = {
          type   = "refine",
          params = {
            steps     = inp.steps,
            cfg       = inp.cfg,
            sampler   = inp.sampler_name,
            scheduler = inp.scheduler,
            denoise   = inp.denoise,
          },
        }
      end
    end
  end

  return ops
end

--- Detect pixel-phase post ops by walking the image chain
-- from VAEDecode output to SaveImage input.
local function decode_post_pixel(prompt, idx)
  local ops = {}

  -- Map of class_type → decoder function
  local decoders = {
    ImageUpscaleWithModel = function(node)
      local p = { type = "upscale", params = {} }
      if is_ref(node.inputs.upscale_model) then
        local loader = prompt[node.inputs.upscale_model[1]]
        if loader and loader.class_type == "UpscaleModelLoader" then
          p.params.model = loader.inputs.model_name
        end
      end
      return p
    end,

    FaceRestoreWithModel = function(node)
      local p = { type = "face", params = { fidelity = node.inputs.fidelity } }
      if is_ref(node.inputs.facerestore_model) then
        local loader = prompt[node.inputs.facerestore_model[1]]
        if loader and loader.class_type == "FaceRestoreModelLoader" then
          p.params.model = loader.inputs.model_name
        end
      end
      return p
    end,

    ColorCorrect = function(node)
      return {
        type   = "color",
        params = {
          brightness = node.inputs.brightness,
          contrast   = node.inputs.contrast,
          saturation = node.inputs.saturation,
          gamma      = node.inputs.gamma,
        },
      }
    end,

    ImageSharpen = function(node)
      return {
        type   = "sharpen",
        params = {
          radius = node.inputs.sharpen_radius,
          sigma  = node.inputs.sigma,
          alpha  = node.inputs.alpha,
        },
      }
    end,

    ImageScaleBy = function(node)
      return {
        type   = "resize",
        params = {
          scale  = node.inputs.scale_by,
          method = node.inputs.upscale_method,
        },
      }
    end,

    ImageScale = function(node)
      return {
        type   = "resize",
        params = {
          width  = node.inputs.width,
          height = node.inputs.height,
          method = node.inputs.upscale_method,
          crop   = node.inputs.crop,
        },
      }
    end,
  }

  -- Walk from SaveImage backwards through pixel ops
  local save_entries = find_nodes(idx, "SaveImage")
  if #save_entries == 0 then return ops end

  local ref = save_entries[1].node.inputs.images
  local visited = {}

  while is_ref(ref) do
    local node_id = ref[1]
    if visited[node_id] then break end
    visited[node_id] = true

    local node = prompt[node_id]
    if not node then break end

    local decoder = decoders[node.class_type]
    if decoder then
      -- Prepend: we walk backwards, so reverse later
      table.insert(ops, 1, decoder(node))
      -- Continue walking backwards via image input
      ref = node.inputs.image or node.inputs.images
    elseif node.class_type == "VAEDecode" then
      break  -- reached the boundary
    else
      -- Unknown node, try to continue
      ref = node.inputs.image or node.inputs.images
      if not ref then break end
    end
  end

  return ops
end

-- ============================================================
-- Size reconstruction
-- ============================================================

local function decode_size(idx)
  local empty = find_one(idx, "EmptyLatentImage")
  if not empty then return nil end
  local inp = empty.node.inputs
  return { inp.width, inp.height }
end

-- ============================================================
-- Output prefix
-- ============================================================

local function decode_output(idx)
  local save = find_one(idx, "SaveImage")
  if not save then return nil end
  return save.node.inputs.filename_prefix
end

-- ============================================================
-- Main decode function
-- ============================================================

--- Decode a ComfyUI prompt table into vdsl-compatible information.
-- @param prompt table ComfyUI prompt { node_id = { class_type, inputs } }
-- @return table reconstructed info
function M.decode(prompt)
  if type(prompt) ~= "table" then
    error("decode: expected a table, got " .. type(prompt), 2)
  end

  local idx = index_by_type(prompt)

  -- World
  local world = decode_world(prompt, idx)

  -- Primary KSampler
  local primary_ks = find_primary_ksampler(prompt, idx)

  -- Casts + global negatives
  local casts, global_negatives = decode_casts(prompt, idx, primary_ks)

  -- Sampler
  local sampler = decode_sampler(primary_ks)

  -- Stage
  local stage = decode_stage(prompt, idx)

  -- Post (latent + pixel)
  local post_latent = decode_post_latent(prompt, idx, primary_ks)
  local post_pixel  = decode_post_pixel(prompt, idx)

  local post = nil
  if #post_latent > 0 or #post_pixel > 0 then
    post = {}
    for _, op in ipairs(post_latent) do post[#post + 1] = op end
    for _, op in ipairs(post_pixel)  do post[#post + 1] = op end
  end

  -- Size
  local size = decode_size(idx)

  -- Output
  local output = decode_output(idx)

  return {
    world             = world,
    casts             = casts,
    sampler           = sampler,
    stage             = stage,
    post              = post,
    size              = size,
    output            = output,
    global_negatives  = (#global_negatives > 0) and global_negatives or nil,
  }
end

return M
