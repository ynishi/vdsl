--- test_shot.lua: Shot entity + integration tests
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;tests/?.lua;'..package.path" tests/test_shot.lua

local vdsl    = require("vdsl")
local Entity  = require("vdsl.entity")
local Shot    = require("vdsl.shot")
local T       = require("harness")

-- Isolate from user config
vdsl.config._override({})

-- ============================================================
-- Fixtures
-- ============================================================

local function make_world()
  return vdsl.world { model = "test.safetensors" }
end

local function make_cast()
  return vdsl.cast { subject = "a cat", negative = "bad quality" }
end

local function make_opts(overrides)
  local base = {
    world = make_world(),
    cast  = { make_cast() },
    seed  = 42,
    steps = 20,
    cfg   = 7.0,
    size  = { 512, 512 },
  }
  if overrides then
    for k, v in pairs(overrides) do base[k] = v end
  end
  return base
end

-- ============================================================
-- 1. Shot lifecycle
-- ============================================================

local opts = make_opts()
local shot = vdsl.shot(opts)

T.ok("shot: is entity",         Entity.is(shot, "shot"))
T.ok("shot: is_entity",         Entity.is_entity(shot))
T.eq("shot: type_of",           Entity.type_of(shot), "shot")

-- field forwarding
T.eq("shot: seed",              shot.seed, 42)
T.eq("shot: steps",             shot.steps, 20)
T.eq("shot: cfg",               shot.cfg, 7.0)
T.ok("shot: world forwarded",   Entity.is(shot.world, "world"))
T.ok("shot: cast forwarded",    Entity.is(shot.cast[1], "cast"))

-- :clone() independent deep copy
local cloned = shot:clone()
T.ok("clone: equals original",  shot:equals(cloned))
T.ok("clone: is type",          Entity.is(cloned, "shot"))
cloned.seed = 999
T.ok("clone: independent",      not shot:equals(cloned))
T.eq("clone: orig unchanged",   shot.seed, 42)

-- :with() override new instance
local modified = shot:with({ seed = 99 })
T.eq("with: seed overridden",   modified.seed, 99)
T.eq("with: orig seed",         shot.seed, 42)
T.ok("with: is type",           Entity.is(modified, "shot"))

-- :equals()
local shot2 = vdsl.shot(make_opts())
T.ok("equals: same opts",       shot:equals(shot2))

-- ============================================================
-- 2. cast single-entity normalisation
-- ============================================================

local single_cast = make_cast()
local shot_single = vdsl.shot {
  world = make_world(),
  cast  = single_cast,
  seed  = 1,
}
T.ok("single cast: is shot",    Entity.is(shot_single, "shot"))
T.ok("single cast: normalised", type(shot_single.cast) == "table")
T.ok("single cast: array",      Entity.is(shot_single.cast[1], "cast"))

-- ============================================================
-- 3. Validation errors
-- ============================================================

T.err("no world",    function() Shot.new({ cast = { make_cast() } }) end)
T.err("bad world",   function() Shot.new({ world = "nope", cast = { make_cast() } }) end)
T.err("no cast",     function() Shot.new({ world = make_world() }) end)
T.err("empty cast",  function() Shot.new({ world = make_world(), cast = {} }) end)
T.err("bad stage",   function()
  Shot.new({ world = make_world(), cast = { make_cast() }, stage = "bad" })
end)
T.err("bad strategy", function()
  Shot.new({ world = make_world(), cast = { make_cast() }, strategy = "unknown" })
end)
T.err("bad on_conflict", function()
  Shot.new({ world = make_world(), cast = { make_cast() }, on_conflict = "nonsense" })
end)

-- ============================================================
-- 4. Binary equivalence: Shot.compile vs direct compiler.compile
-- ============================================================

local compiler = require("vdsl.compiler")
local fixed_opts = {
  world = vdsl.world { model = "sdxl.safetensors" },
  cast  = { vdsl.cast { subject = "portrait girl", negative = "ugly" } },
  seed  = 12345,
  steps = 25,
  cfg   = 7.5,
  size  = { 1024, 1024 },
}

local direct_result = compiler.compile(fixed_opts)
local shot_result   = vdsl.render(fixed_opts)   -- now goes through Shot

T.eq("binary equiv: json",    direct_result.json, shot_result.json)

-- Also verify via Shot:compile() directly
local shot_direct = vdsl.shot(fixed_opts)
local shot_compile_result = shot_direct:compile()
T.eq("shot compile: json",    direct_result.json, shot_compile_result.json)

-- ============================================================
-- 5. Shot:serialize / Shot.from roundtrip
-- ============================================================

local world_for_rt = vdsl.world {
  model    = "rt_model.safetensors",
  denoise  = 0.85,
  steps    = 30,
}
local rt_opts = {
  world      = world_for_rt,
  cast       = { make_cast() },
  seed       = 777,
  on_conflict = "ignore",
  steps      = 30,
}
local rt_shot = vdsl.shot(rt_opts)
local json_str = rt_shot:serialize()
T.ok("serialize: is string",  type(json_str) == "string")

local restored = Shot.from(json_str)
T.ok("from: is shot",         Entity.is(restored, "shot"))
T.eq("from: seed",            restored.seed, 777)
T.eq("from: on_conflict",     restored.on_conflict, "ignore")
T.eq("from: steps",           restored.steps, 30)
T.ok("from: world entity",    Entity.is(restored.world, "world"))
T.eq("from: world.model",     restored.world.model, "rt_model.safetensors")

-- ============================================================
-- 6. world.denoise resolution via opt()
-- ============================================================

local world_denoise = vdsl.world { model = "d.safetensors", denoise = 0.55 }
local dn_shot = vdsl.shot {
  world = world_denoise,
  cast  = { make_cast() },
  seed  = 1,
}
local dn_result = dn_shot:compile()

-- Find KSampler node and check denoise field
local ksampler_denoise = nil
for _, node in pairs(dn_result.prompt) do
  if node.class_type == "KSampler" then
    ksampler_denoise = node.inputs.denoise
    break
  end
end
T.eq("world.denoise: resolved", ksampler_denoise, 0.55)

-- opts.denoise takes priority over world.denoise
local dn_shot_explicit = vdsl.shot {
  world   = world_denoise,
  cast    = { make_cast() },
  seed    = 1,
  denoise = 0.90,
}
local dn_result2 = dn_shot_explicit:compile()
local ksampler_denoise2 = nil
for _, node in pairs(dn_result2.prompt) do
  if node.class_type == "KSampler" then
    ksampler_denoise2 = node.inputs.denoise
    break
  end
end
T.eq("opts.denoise: priority", ksampler_denoise2, 0.90)

-- ============================================================
-- 7. mask drop: stage.mask is nil
-- ============================================================

local stage_no_mask = vdsl.stage {
  controlnet = { { type = "depth", image = "d.png" } },
}
T.eq("mask drop: mask nil",  stage_no_mask.mask, nil)

-- stage still works in shot
local shot_with_stage = vdsl.shot {
  world = make_world(),
  cast  = { make_cast() },
  stage = stage_no_mask,
  seed  = 2,
}
T.ok("stage: shot is valid",  Entity.is(shot_with_stage, "shot"))

T.summary()
