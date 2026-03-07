--- Verify: Pipeline-based post-training LoRA quality verification.
--
-- Builds a Pipeline with weight sweep + judge gate for systematic
-- LoRA weight evaluation. Returns a configured Pipeline instance
-- that the caller compiles with test variations.
--
-- Flow:
--   1. training.verify { lora, world, weights, ... }  → Pipeline
--   2. pipe:compile(test_variations)                   → weight × tests
--   3. Judge gate selects best weight(s)
--
-- Test variations are standard Pipeline variations with subject/negative:
--   { key = "dress", subject = vdsl.subject("1girl"):with("black dress") }
--
-- Execution (ComfyUI submit, judge evaluation) is external (MCP/manual).

local pipeline = require("vdsl.pipeline")
local World    = require("vdsl.world")

local M = {}

--- Create a verification Pipeline for a trained LoRA.
--
-- @param opts table {
--   name       string    pipeline name (used for manifest)
--   lora       string    LoRA filename to verify
--   world      World     base world (model, sampler, etc.)
--   weights    table     array of weight values to sweep (e.g. {0.3, 0.5, 0.7, 1.0})
--   size?      table     { width, height } (default { 832, 1216 })
--   seed_base? number    base seed (default 50000)
--   save_dir?  string    output directory (default opts.name)
--   judge?     function  custom judge evaluator (default: pipeline.prompt)
-- }
-- @return Pipeline configured pipeline instance
function M.new(opts)
  if type(opts) ~= "table" then
    error("training.verify: expected a table, got " .. type(opts), 2)
  end
  if not opts.lora or opts.lora == "" then
    error("training.verify: 'lora' is required", 2)
  end
  if not opts.world then
    error("training.verify: 'world' is required", 2)
  end
  if not opts.weights or type(opts.weights) ~= "table" or #opts.weights == 0 then
    error("training.verify: 'weights' must be a non-empty array", 2)
  end

  local name      = opts.name or ("verify_" .. opts.lora:gsub("%.safetensors$", ""))
  local size      = opts.size or { 832, 1216 }
  local seed_base = opts.seed_base or 50000
  local save_dir  = opts.save_dir or name

  -- Capture world fields for cloning in the pass function
  local base_world = opts.world
  local lora_name  = opts.lora

  local pipe = pipeline.new(name, {
    save_dir  = save_dir,
    seed_base = seed_base,
    size      = size,
  })

  -- Single pass: weight sweep
  pipe:pass("sweep", {
    sweep = { weight = opts.weights },
  }, function(v, ctx)
    -- Build a new World with the LoRA at this sweep weight
    local world_opts = {
      model     = base_world.model,
      vae       = base_world.vae,
      clip_skip = base_world.clip_skip,
      sampler   = base_world.sampler,
      steps     = base_world.steps,
      cfg       = base_world.cfg,
      scheduler = base_world.scheduler,
      post      = base_world.post,
      lora      = { { name = lora_name, weight = v.sweep.weight } },
    }

    -- Merge existing world LoRAs (if base world already has some)
    if base_world.lora then
      for _, entry in ipairs(base_world.lora) do
        world_opts.lora[#world_opts.lora + 1] = {
          name   = entry.name,
          weight = entry.weight,
        }
      end
    end

    local world = World.new(world_opts)

    -- Build cast from variation's subject/negative
    local vdsl = require("vdsl")
    local subject = v.subject
    if type(subject) == "string" then
      subject = vdsl.subject(subject)
    end

    local cast = vdsl.cast {
      subject  = subject,
      negative = v.negative,
    }

    return {
      world = world,
      cast  = { cast },
      seed  = ctx.seed,
    }
  end)

  -- Judge gate: select best weight(s)
  local judge_fn = opts.judge or function(candidates, _base)
    -- Default: check if outputs exist, prompt if they do
    local all_exist = true
    for _, c in ipairs(candidates) do
      if not c.exists then
        all_exist = false
        break
      end
    end
    if not all_exist then return nil end
    return pipeline.prompt(candidates)
  end

  pipe:judge(judge_fn)

  return pipe
end

return M
