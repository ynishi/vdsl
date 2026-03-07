--- 05_pipeline.lua: Multi-pass pipeline with sweep and judge gate
-- Demonstrates: Pipeline, pass chaining, denoise sweep, rule-based judge
-- No server required (compile-only).
--
-- Architecture:
--   Pass 1: txt2img base generation (3 character variations)
--   Pass 2: img2img refinement with denoise sweep {0.4, 0.5, 0.6, 0.7}
--     → judge: keep middle 2 values (prune extremes)
--   Pass 3: FaceDetailer pass (only on judge survivors)
--
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;'..package.path" examples/05_pipeline.lua

local vdsl     = require("vdsl")
local pipeline = require("vdsl.pipeline")
local C = vdsl.catalogs

-- ============================================================
-- Shared setup
-- ============================================================

local neg = C.quality.neg_default + C.quality.neg_anatomy + C.quality.neg_face

local variations = {
  {
    key  = "warrior",
    char = vdsl.subject("1girl, solo")
      :with(vdsl.trait("red hair, ponytail, sharp eyes"))
      :with(C.figure.body.toned)
      :with(C.figure.expression.determined)
      :quality("high"),
    outfit = vdsl.trait("armor, shoulder armor, gauntlets, cape"),
    scene  = C.environment.setting.ruins + C.lighting.golden_hour + C.camera.cowboy_shot,
  },
  {
    key  = "mage",
    char = vdsl.subject("1girl, solo")
      :with(vdsl.trait("white hair, long hair, glowing eyes"))
      :with(C.figure.body.slim)
      :with(C.figure.expression.confident)
      :quality("high"),
    outfit = vdsl.trait("robe, ornate staff, floating runes, magical aura"),
    scene  = C.environment.setting.ancient_temple + C.lighting.volumetric + C.camera.full_body,
  },
  {
    key  = "rogue",
    char = vdsl.subject("1girl, solo")
      :with(vdsl.trait("black hair, short hair, scar on cheek"))
      :with(C.figure.body.petite)
      :with(C.figure.expression.smirk)
      :quality("high"),
    outfit = vdsl.trait("leather jacket, hood, daggers, dark clothes"),
    scene  = C.environment.setting.alley + C.lighting.neon + C.environment.time.night + C.camera.medium_shot,
  },
}

-- ============================================================
-- Pipeline definition
-- ============================================================

local pipe = pipeline.new("fantasy_3pass", {
  save_dir  = "fantasy_3pass",
  seed_base = 50000,
  size      = { 832, 1216 },
})

-- Pass 1: txt2img base
pipe:pass("base", function(v, ctx)
  local subject = v.char:with(v.outfit):with(v.scene)
  return {
    world = vdsl.world { clip_skip = 2 },
    cast  = { vdsl.cast { subject = subject, negative = neg } },
    steps = 30,
    cfg   = 6.0,
    seed  = ctx.seed,
  }
end)

-- Pass 2: img2img refinement with denoise sweep
pipe:pass("refine", {
  sweep = { denoise = { 0.4, 0.5, 0.6, 0.7 } }
}, function(v, ctx)
  local subject = v.char:with(v.outfit):with(v.scene)
  return {
    world     = vdsl.world { clip_skip = 2 },
    cast      = { vdsl.cast { subject = subject, negative = neg } },
    stage     = vdsl.stage { latent_image = ctx.prev_output },
    sampler   = "dpmpp_sde",
    scheduler = "karras",
    steps     = 40,
    cfg       = 5.0,
    seed      = ctx.seed,
    denoise   = v.sweep.denoise,
  }
end)

-- Judge gate: prune extreme denoise values, keep middle 2
pipe:judge(function(candidates)
  local sorted = {}
  for _, c in ipairs(candidates) do
    sorted[#sorted + 1] = { suffix = c.suffix, denoise = c.sweep.denoise }
  end
  table.sort(sorted, function(a, b) return a.denoise < b.denoise end)

  local survivors, pruned, scores = {}, {}, {}
  for i, s in ipairs(sorted) do
    local dist = math.abs(i - (#sorted + 1) / 2)
    scores[s.suffix] = 10.0 - dist * 3.0
    if i >= 2 and i <= #sorted - 1 then
      survivors[#survivors + 1] = s.suffix
    else
      pruned[#pruned + 1] = s.suffix
    end
  end

  return { survivors = survivors, pruned = pruned, scores = scores }
end)

-- Pass 3: FaceDetailer (runs only on judge survivors)
pipe:pass("face", function(v, ctx)
  local face_prompt = C.quality.high
    + C.figure.expression.gentle_smile
    + vdsl.trait("detailed face, beautiful detailed face")
    + vdsl.trait("looking at viewer")

  local face_neg = C.quality.neg_default + C.quality.neg_face

  return {
    world   = vdsl.world { clip_skip = 2 },
    cast    = { vdsl.cast { subject = v.char, negative = neg } },
    stage   = vdsl.stage { latent_image = ctx.prev_output },
    steps   = 20,
    cfg     = 6.0,
    seed    = ctx.seed,
    denoise = 0.00,
    post    = vdsl.post("facedetail", {
      detector = "face",
      denoise  = 0.25,
      prompt   = face_prompt,
      negative = face_neg,
    }),
  }
end)

-- ============================================================
-- Compile and report
-- ============================================================

print("=== Fantasy 3-Pass Pipeline ===")
print(string.format("  variations: %d", #variations))
for _, v in ipairs(variations) do
  print(string.format("    - %s", v.key))
end

local p1 = #variations
local p2 = #variations * 4
local p3 = #variations * 2  -- after judge prunes to 2
print(string.format("\n  Workflow count: %d (p1) + %d (p2) + %d (p3) = %d total", p1, p2, p3, p1 + p2 + p3))
print(string.format("  vs full sweep:  %d → %.0f%% reduction",
  #variations * (1 + 4 + 4),
  (1 - (p1 + p2 + p3) / (#variations * 9)) * 100))

pipe:compile(variations)

print("\n=== Compile complete ===")
