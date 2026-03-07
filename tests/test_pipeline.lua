--- test_pipeline.lua: Verify Pipeline DSL compilation and manifest output
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;tests/?.lua;'..package.path" tests/test_pipeline.lua

local vdsl     = require("vdsl")
local pipeline = require("vdsl.pipeline")
local json     = require("vdsl.util.json")
local T        = require("harness")

-- ============================================================
-- Construction validation
-- ============================================================

T.err("new: missing name", function() pipeline.new() end)
T.err("new: empty name",   function() pipeline.new("") end)
T.err("new: nil name",     function() pipeline.new(nil) end)

local p = pipeline.new("test_pipe", { save_dir = "out", seed_base = 100, size = { 512, 512 } })
T.ok("new: returns table", type(p) == "table")

-- ============================================================
-- Pass definition
-- ============================================================

T.err("pass: missing name",    function() p:pass("", function() return {} end) end)
T.err("pass: no fn",           function() p:pass("p1", {}) end)
T.err("pass: bad opts type",   function() p:pass("p1", 42, function() return {} end) end)

-- Valid pass definitions (function-only and table+function)
local p2 = pipeline.new("test2")
p2:pass("p1", function(v, ctx) return {
  world = vdsl.world { model = "m.safetensors" },
  cast  = { vdsl.cast { subject = "cat" } },
  seed = ctx.seed, steps = 10, cfg = 5, size = { 512, 512 },
} end)

T.err("pass: duplicate name", function()
  p2:pass("p1", function() return {} end)
end)

-- Chaining
local p3 = pipeline.new("chain_test")
local ret = p3:pass("a", function(v, ctx) return {
  world = vdsl.world { model = "m.safetensors" },
  cast  = { vdsl.cast { subject = "cat" } },
  seed = 1, steps = 10, cfg = 5, size = { 512, 512 },
} end)
T.ok("pass: returns self (chain)", ret == p3)

-- ============================================================
-- Compile: single pass, no sweep
-- ============================================================

local sp = pipeline.new("single_pass", {
  save_dir  = "sp_out",
  seed_base = 200,
  size      = { 768, 1024 },
})
sp:pass("p1", function(v, ctx)
  return {
    world = vdsl.world { model = "model_a.safetensors" },
    cast  = { vdsl.cast { subject = v.key } },
    seed  = ctx.seed,
    steps = 20,
    cfg   = 7,
  }
end)

local vars = {
  { key = "char_a" },
  { key = "char_b" },
}

local m = sp:compile(vars, { mode = "full" })

T.eq("single: version",       m.version,  1)
T.eq("single: name",          m.name,     "single_pass")
T.eq("single: save_dir",      m.save_dir, "sp_out")
T.eq("single: passes count",  #m.passes,  1)

local pass1 = m.passes[1]
T.eq("single: pass name",           pass1.name, "p1")
T.eq("single: depends_on nil",      pass1.depends_on, nil)
T.eq("single: variation_count",     pass1.variation_count, 2)
T.eq("single: workflows count",     #pass1.workflows, 2)
T.eq("single: wf[1]",               pass1.workflows[1], "p1_char_a.json")
T.eq("single: wf[2]",               pass1.workflows[2], "p1_char_b.json")
T.eq("single: transfers empty",     #pass1.transfers, 0)

-- ============================================================
-- Compile: two passes, no sweep (transfer test)
-- ============================================================

local tp = pipeline.new("two_pass", {
  save_dir  = "tp_out",
  seed_base = 300,
  size      = { 512, 512 },
})
tp:pass("gen", function(v, ctx)
  return {
    world = vdsl.world { model = "base.safetensors" },
    cast  = { vdsl.cast { subject = v.key } },
    seed  = ctx.seed,
    steps = 20,
    cfg   = 7,
  }
end)
tp:pass("refine", function(v, ctx)
  T.ok("ctx: prev_pass set",   ctx.prev_pass == "gen")
  T.ok("ctx: prev_output set", type(ctx.prev_output) == "string")
  return {
    world = vdsl.world { model = "refine.safetensors" },
    cast  = { vdsl.cast { subject = v.key } },
    stage = vdsl.stage { latent_image = ctx.prev_output },
    seed  = ctx.seed,
    steps = 15,
    cfg   = 5,
    denoise = 0.6,
  }
end)

local tm = tp:compile({ { key = "x" }, { key = "y" } }, { mode = "full" })

T.eq("two: passes count", #tm.passes, 2)

local tpass1 = tm.passes[1]
T.eq("two: p1 name",       tpass1.name, "gen")
T.eq("two: p1 depends_on", tpass1.depends_on, nil)
T.eq("two: p1 wf count",   #tpass1.workflows, 2)
T.eq("two: p1 transfers",  #tpass1.transfers, 0)

local tpass2 = tm.passes[2]
T.eq("two: p2 name",             tpass2.name, "refine")
T.eq("two: p2 depends_on",       tpass2.depends_on, "gen")
T.eq("two: p2 wf count",         #tpass2.workflows, 2)
T.eq("two: p2 transfer count",   #tpass2.transfers, 2)

-- Transfers should reference gen pass output (via run_dir with timestamp)
local t1 = tpass2.transfers[1]
T.ok("two: transfer from has run_dir",
  t1.from:find("^output/tp_out/%d+_%d+/gen_x_00001_%.png$") ~= nil)
T.eq("two: transfer to",    t1.to,   "input/gen_x_00001_.png")

-- ============================================================
-- Compile: sweep expansion
-- ============================================================

local sw = pipeline.new("sweep_test", {
  save_dir  = "sw_out",
  seed_base = 0,
  size      = { 512, 512 },
})
sw:pass("base", function(v, ctx)
  return {
    world = vdsl.world { model = "m.safetensors" },
    cast  = { vdsl.cast { subject = v.key } },
    seed  = ctx.seed,
    steps = 20,
    cfg   = 7,
  }
end)
sw:pass("sweep", {
  sweep = { denoise = { 0.5, 0.7 } }
}, function(v, ctx)
  return {
    world   = vdsl.world { model = "r.safetensors" },
    cast    = { vdsl.cast { subject = v.key } },
    stage   = vdsl.stage { latent_image = ctx.prev_output },
    seed    = ctx.seed,
    steps   = 15,
    cfg     = 5,
    denoise = v.sweep.denoise,
  }
end)

local sm = sw:compile({ { key = "a" } }, { mode = "full" })

T.eq("sweep: pass count",    #sm.passes, 2)
T.eq("sweep: base wf count", #sm.passes[1].workflows, 1)
-- 1 variation × 2 denoise values = 2 workflows
T.eq("sweep: sweep wf count",   #sm.passes[2].workflows, 2)
T.eq("sweep: sweep var_count",  sm.passes[2].variation_count, 2)

-- Workflow filenames should contain sweep suffix
local wf1 = sm.passes[2].workflows[1]
local wf2 = sm.passes[2].workflows[2]
T.ok("sweep: wf1 has d05", wf1:find("d05") ~= nil)
T.ok("sweep: wf2 has d07", wf2:find("d07") ~= nil)

-- Transfer for sweep pass should reference base pass output (via run_dir)
T.eq("sweep: transfer count", #sm.passes[2].transfers, 1)
T.ok("sweep: transfer from has run_dir",
  sm.passes[2].transfers[1].from:find("^output/sw_out/%d+_%d+/base_a_00001_%.png$") ~= nil)

-- ============================================================
-- Compile: multi-axis sweep (cross product)
-- ============================================================

local ma = pipeline.new("multi_axis", {
  save_dir  = "ma_out",
  seed_base = 0,
  size      = { 512, 512 },
})
ma:pass("p1", function(v, ctx)
  return {
    world = vdsl.world { model = "m.safetensors" },
    cast  = { vdsl.cast { subject = v.key } },
    seed  = ctx.seed, steps = 10, cfg = 5,
  }
end)
ma:pass("p2", {
  sweep = { denoise = { 0.5, 0.7 }, cfg = { 4, 6 } }
}, function(v, ctx)
  return {
    world   = vdsl.world { model = "r.safetensors" },
    cast    = { vdsl.cast { subject = v.key } },
    stage   = vdsl.stage { latent_image = ctx.prev_output },
    seed    = ctx.seed, steps = 10,
    cfg     = v.sweep.cfg,
    denoise = v.sweep.denoise,
  }
end)

local mam = ma:compile({ { key = "x" } }, { mode = "full" })
-- 1 variation × 2 cfg × 2 denoise = 4 workflows (cross product)
T.eq("multi-axis: sweep wf count",  #mam.passes[2].workflows, 4)
T.eq("multi-axis: sweep var_count", mam.passes[2].variation_count, 4)

-- ============================================================
-- Compile: error cases
-- ============================================================

T.err("compile: no passes", function()
  pipeline.new("empty"):compile({ { key = "a" } })
end)

local np = pipeline.new("no_vars")
np:pass("p1", function() return {
  world = vdsl.world { model = "m.safetensors" },
  cast  = { vdsl.cast { subject = "x" } },
  seed = 1, steps = 10, cfg = 5, size = { 512, 512 },
} end)
T.err("compile: empty variations", function() np:compile({}) end)
T.err("compile: nil variations",   function() np:compile(nil) end)

-- ============================================================
-- Compile: seed assignment
-- ============================================================

local sd = pipeline.new("seed_test", { seed_base = 1000, size = { 512, 512 } })
local captured_seeds = {}
sd:pass("p1", function(v, ctx)
  captured_seeds[v.key] = ctx.seed
  return {
    world = vdsl.world { model = "m.safetensors" },
    cast  = { vdsl.cast { subject = v.key } },
    seed  = ctx.seed, steps = 10, cfg = 5,
  }
end)

sd:compile({ { key = "a" }, { key = "b" }, { key = "c" } })
T.eq("seed: a", captured_seeds.a, 1001)
T.eq("seed: b", captured_seeds.b, 1002)
T.eq("seed: c", captured_seeds.c, 1003)

-- ============================================================
-- Compile: context fields
-- ============================================================

local cf = pipeline.new("ctx_fields", {
  save_dir = "my_dir",
  size     = { 832, 1216 },
})
local captured_ctx
cf:pass("p1", function(v, ctx)
  captured_ctx = ctx
  return {
    world = vdsl.world { model = "m.safetensors" },
    cast  = { vdsl.cast { subject = v.key } },
    seed  = ctx.seed, steps = 10, cfg = 5,
  }
end)

cf:compile({ { key = "z" } })
T.eq("ctx: pass_name",  captured_ctx.pass_name,  "p1")
T.eq("ctx: pass_index", captured_ctx.pass_index,  1)
T.eq("ctx: save_dir",   captured_ctx.save_dir,   "my_dir")
T.eq("ctx: size[1]",    captured_ctx.size[1],     832)
T.eq("ctx: size[2]",    captured_ctx.size[2],     1216)

-- ============================================================
-- Compile: variation view includes base fields
-- ============================================================

local vf = pipeline.new("var_fields", { size = { 512, 512 } })
local captured_v
vf:pass("p1", function(v, ctx)
  captured_v = v
  return {
    world = vdsl.world { model = "m.safetensors" },
    cast  = { vdsl.cast { subject = v.key } },
    seed  = ctx.seed, steps = 10, cfg = 5,
  }
end)

vf:compile({ { key = "hero", style = "anime", lora = "detail_v3" } })
T.eq("var: key",   captured_v.key,   "hero")
T.eq("var: style", captured_v.style, "anime")
T.eq("var: lora",  captured_v.lora,  "detail_v3")
T.ok("var: base",  type(captured_v.base) == "table")

-- ============================================================
-- Cache: hash-based diff skip
-- ============================================================

local function make_cache_pipe(cfg_val)
  local p = pipeline.new("test_cache", {
    save_dir = "tc_out", seed_base = 500, size = { 512, 768 },
  })
  p:pass("p1", function(v, ctx)
    return {
      world = vdsl.world { model = "a.safetensors" },
      cast  = { vdsl.cast { subject = v.key } },
      seed  = ctx.seed, steps = 20, cfg = cfg_val,
    }
  end)
  p:pass("p2", function(v, ctx)
    return {
      world   = vdsl.world { model = "b.safetensors" },
      cast    = { vdsl.cast { subject = v.key } },
      stage   = vdsl.stage { latent_image = ctx.prev_output },
      seed    = ctx.seed, steps = 15, cfg = 5, denoise = 0.5,
    }
  end)
  return p
end

local cache_vars = { { key = "x" }, { key = "y" } }

-- Run 1: initial compile (default mode="cached")
local cm1 = make_cache_pipe(5.0):compile(cache_vars)
T.eq("cache r1: p1 wf count", #cm1.passes[1].workflows, 2)
T.eq("cache r1: p2 wf count", #cm1.passes[2].workflows, 2)

-- Run 2: same params → all skipped (0 workflows in manifest)
local cm2 = make_cache_pipe(5.0):compile(cache_vars)
T.eq("cache r2: p1 wf count (skip)", #cm2.passes[1].workflows, 0)
T.eq("cache r2: p2 wf count (skip)", #cm2.passes[2].workflows, 0)

-- Run 3: change P1 cfg → cascade: P1 + P2 regenerated
local cm3 = make_cache_pipe(7.0):compile(cache_vars)
T.eq("cache r3: p1 wf count (changed)", #cm3.passes[1].workflows, 2)
T.eq("cache r3: p2 wf count (cascade)", #cm3.passes[2].workflows, 2)

-- Run 4: mode="full" ignores manifest
local cm4 = make_cache_pipe(7.0):compile(cache_vars, { mode = "full" })
T.eq("cache r4: p1 wf count (full)", #cm4.passes[1].workflows, 2)
T.eq("cache r4: p2 wf count (full)", #cm4.passes[2].workflows, 2)

-- Cleanup
os.execute("rm -rf output/tc_out")

-- ============================================================
-- Cache: only/except filter
-- ============================================================

local function make_filter_pipe()
  local p = pipeline.new("test_filter", {
    save_dir = "tf_out", seed_base = 600, size = { 512, 768 },
  })
  p:pass("p1", function(v, ctx)
    return {
      world = vdsl.world { model = "a.safetensors" },
      cast  = { vdsl.cast { subject = v.key } },
      seed  = ctx.seed, steps = 20, cfg = 5,
    }
  end)
  return p
end

local fvars = { { key = "a" }, { key = "b" }, { key = "c" } }

-- only filter
local fm1 = make_filter_pipe():compile(fvars, { mode = "full", only = { "a", "c" } })
T.eq("filter only: wf count", #fm1.passes[1].workflows, 2)
T.ok("filter only: has a", fm1.passes[1].workflows[1]:find("p1_a") ~= nil)
T.ok("filter only: has c", fm1.passes[1].workflows[2]:find("p1_c") ~= nil)

-- except filter
local fm2 = make_filter_pipe():compile(fvars, { mode = "full", except = { "b" } })
T.eq("filter except: wf count", #fm2.passes[1].workflows, 2)
T.ok("filter except: has a", fm2.passes[1].workflows[1]:find("p1_a") ~= nil)
T.ok("filter except: has c", fm2.passes[1].workflows[2]:find("p1_c") ~= nil)

-- Cleanup
os.execute("rm -rf output/tf_out")

-- ============================================================
-- Cache: transfer uses correct run_dir for skipped pass
-- ============================================================

local function make_xfer_pipe(p2_cfg)
  local p = pipeline.new("test_xfer_cache", {
    save_dir = "xc_out", seed_base = 700, size = { 512, 768 },
  })
  p:pass("p1", function(v, ctx)
    return {
      world = vdsl.world { model = "a.safetensors" },
      cast  = { vdsl.cast { subject = v.key } },
      seed  = ctx.seed, steps = 20, cfg = 5,
    }
  end)
  p:pass("p2", function(v, ctx)
    return {
      world   = vdsl.world { model = "b.safetensors" },
      cast    = { vdsl.cast { subject = v.key } },
      stage   = vdsl.stage { latent_image = ctx.prev_output },
      seed    = ctx.seed, steps = 15, cfg = p2_cfg, denoise = 0.5,
    }
  end)
  return p
end

-- Run 1: initial (default mode="cached")
local xm1 = make_xfer_pipe(5.0):compile({ { key = "q" } })
local xm1_run = xm1.run_dir

-- Run 2: change P2 only → P1 skipped, P2 regenerated
-- Transfer should point to P1's OLD run_dir
local xm2 = make_xfer_pipe(8.0):compile({ { key = "q" } })
T.eq("xfer: p1 skipped",  #xm2.passes[1].workflows, 0)
T.eq("xfer: p2 compiled", #xm2.passes[2].workflows, 1)
-- Transfer from should reference the old run_dir (where P1 output lives)
local xfer = xm2.passes[2].transfers[1]
T.ok("xfer: from uses old run_dir",
  xfer.from:find(xm1_run, 1, true) ~= nil)

-- Cleanup
os.execute("rm -rf output/xc_out")

-- ============================================================
-- Pick: basic contraction (sweep 3 → 1)
-- ============================================================

local pk = pipeline.new("test_pick", {
  save_dir  = "pk_out",
  seed_base = 0,
  size      = { 512, 512 },
})
pk:pass("p1", function(v, ctx)
  return {
    world = vdsl.world { model = "m.safetensors" },
    cast  = { vdsl.cast { subject = v.key } },
    seed  = ctx.seed, steps = 10, cfg = 5,
  }
end)
pk:pass("p2", {
  sweep = { denoise = { 0.5, 0.6, 0.7 } }
}, function(v, ctx)
  return {
    world   = vdsl.world { model = "r.safetensors" },
    cast    = { vdsl.cast { subject = v.key } },
    stage   = vdsl.stage { latent_image = ctx.prev_output },
    seed    = ctx.seed, steps = 15, cfg = 5,
    denoise = v.sweep.denoise,
  }
end)
-- Pick gate: always select "d06" (auto evaluator)
pk:pick(function(candidates, base_var)
  for _, c in ipairs(candidates) do
    if c.suffix == "d06" then return c.suffix end
  end
  return candidates[1].suffix
end)
pk:pass("p3", function(v, ctx)
  return {
    world   = vdsl.world { model = "f.safetensors" },
    cast    = { vdsl.cast { subject = v.key } },
    stage   = vdsl.stage { latent_image = ctx.prev_output },
    seed    = ctx.seed, steps = 20, cfg = 7,
  }
end)

local pkm = pk:compile({ { key = "a" }, { key = "b" } }, { mode = "full" })

-- p1: 2 workflows (a, b)
T.eq("pick: p1 wf count", #pkm.passes[1].workflows, 2)
-- p2: 6 workflows (a × 3 denoise + b × 3 denoise)
T.eq("pick: p2 wf count", #pkm.passes[2].workflows, 6)
-- p3: 2 workflows (contracted back to a, b after pick)
T.eq("pick: p3 wf count", #pkm.passes[3].workflows, 2)
-- p3 should reference p2 output (the picked one: d06)
T.ok("pick: p3 transfer references picked",
  pkm.passes[3].transfers[1].from:find("p2_a__d06") ~= nil)

-- Cleanup
os.execute("rm -rf output/pk_out")

-- ============================================================
-- Pick: unresolved (evaluator returns nil → partial manifest)
-- ============================================================

local pku = pipeline.new("test_pick_unresolved", {
  save_dir  = "pku_out",
  seed_base = 0,
  size      = { 512, 512 },
})
pku:pass("p1", function(v, ctx)
  return {
    world = vdsl.world { model = "m.safetensors" },
    cast  = { vdsl.cast { subject = v.key } },
    seed  = ctx.seed, steps = 10, cfg = 5,
  }
end)
pku:pass("p2", {
  sweep = { denoise = { 0.5, 0.7 } }
}, function(v, ctx)
  return {
    world   = vdsl.world { model = "r.safetensors" },
    cast    = { vdsl.cast { subject = v.key } },
    stage   = vdsl.stage { latent_image = ctx.prev_output },
    seed    = ctx.seed, steps = 10, cfg = 5,
    denoise = v.sweep.denoise,
  }
end)
-- Pick gate: returns nil (outputs not available)
pku:pick(function(candidates, base_var)
  return nil
end)
pku:pass("p3", function(v, ctx)
  return {
    world = vdsl.world { model = "f.safetensors" },
    cast  = { vdsl.cast { subject = v.key } },
    seed  = ctx.seed, steps = 20, cfg = 7,
  }
end)

local pkum = pku:compile({ { key = "x" } }, { mode = "full" })

-- p1 + p2 should be compiled
T.eq("pick unresolved: p1 wf count", #pkum.passes[1].workflows, 1)
T.eq("pick unresolved: p2 wf count", #pkum.passes[2].workflows, 2)
-- p3 should NOT be compiled (pick unresolved → compilation stopped)
T.eq("pick unresolved: pass count", #pkum.passes, 2)
-- Manifest should have pick_gate marker
T.eq("pick unresolved: pick_gate status", pkum.pick_gate.status, "pending")
T.eq("pick unresolved: pick_gate pass", pkum.pick_gate.after_pass, "p2")

-- Cleanup
os.execute("rm -rf output/pku_out")

-- ============================================================
-- Pick: error cases
-- ============================================================

T.err("pick: no prior pass", function()
  local p = pipeline.new("pick_err")
  p:pick(function() end)
end)

T.err("pick: not a function", function()
  local p = pipeline.new("pick_err2")
  p:pass("p1", function(v, ctx)
    return {
      world = vdsl.world { model = "m.safetensors" },
      cast  = { vdsl.cast { subject = "x" } },
      seed = 1, steps = 10, cfg = 5,
    }
  end)
  p:pick("not_a_function")
end)

-- ============================================================
-- Judge: basic contraction (sweep 3 → 2)
-- ============================================================

local jg = pipeline.new("test_judge", {
  save_dir  = "jg_out",
  seed_base = 0,
  size      = { 512, 512 },
})
jg:pass("p1", function(v, ctx)
  return {
    world = vdsl.world { model = "m.safetensors" },
    cast  = { vdsl.cast { subject = v.key } },
    seed  = ctx.seed, steps = 10, cfg = 5,
  }
end)
jg:pass("p2", {
  sweep = { denoise = { 0.5, 0.6, 0.7 } }
}, function(v, ctx)
  return {
    world   = vdsl.world { model = "r.safetensors" },
    cast    = { vdsl.cast { subject = v.key } },
    stage   = vdsl.stage { latent_image = ctx.prev_output },
    seed    = ctx.seed, steps = 15, cfg = 5,
    denoise = v.sweep.denoise,
  }
end)
-- Judge gate: keep top-2 (d06, d07)
jg:judge(function(candidates, base_var)
  return { "d06", "d07" }
end)
jg:pass("p3", function(v, ctx)
  return {
    world   = vdsl.world { model = "f.safetensors" },
    cast    = { vdsl.cast { subject = v.key } },
    stage   = vdsl.stage { latent_image = ctx.prev_output },
    seed    = ctx.seed, steps = 20, cfg = 7,
  }
end)

local jgm = jg:compile({ { key = "a" }, { key = "b" } }, { mode = "full" })

-- p1: 2 workflows (a, b)
T.eq("judge: p1 wf count", #jgm.passes[1].workflows, 2)
-- p2: 6 workflows (a × 3 + b × 3)
T.eq("judge: p2 wf count", #jgm.passes[2].workflows, 6)
-- p3: 4 workflows (2 survivors per variation × 2 base variations)
T.eq("judge: p3 wf count", #jgm.passes[3].workflows, 4)
-- p3 transfers should reference the 2 survived outputs per base
T.eq("judge: p3 transfer count", #jgm.passes[3].transfers, 4)
-- Transfers should reference the judged outputs
T.ok("judge: p3 xfer[1] references d06 or d07",
  jgm.passes[3].transfers[1].from:find("p2_a__d0[67]") ~= nil)
-- judge_gate should be in manifest
T.eq("judge: gate status", jgm.judge_gate.status, "resolved")
T.eq("judge: gate pass", jgm.judge_gate.after_pass, "p2")

-- Cleanup
os.execute("rm -rf output/jg_out")

-- ============================================================
-- Judge: with pruned and scores
-- ============================================================

local js = pipeline.new("test_judge_scores", {
  save_dir  = "js_out",
  seed_base = 0,
  size      = { 512, 512 },
})
js:pass("p1", function(v, ctx)
  return {
    world = vdsl.world { model = "m.safetensors" },
    cast  = { vdsl.cast { subject = v.key } },
    seed  = ctx.seed, steps = 10, cfg = 5,
  }
end)
js:pass("p2", {
  sweep = { denoise = { 0.5, 0.6, 0.7 } }
}, function(v, ctx)
  return {
    world   = vdsl.world { model = "r.safetensors" },
    cast    = { vdsl.cast { subject = v.key } },
    stage   = vdsl.stage { latent_image = ctx.prev_output },
    seed    = ctx.seed, steps = 15, cfg = 5,
    denoise = v.sweep.denoise,
  }
end)
js:judge(function(candidates, base_var)
  return {
    survivors = { "d06" },
    pruned    = { "d05", "d07" },
    scores    = { d05 = 3.2, d06 = 8.5, d07 = 5.0 },
  }
end)
js:pass("p3", function(v, ctx)
  return {
    world   = vdsl.world { model = "f.safetensors" },
    cast    = { vdsl.cast { subject = v.key } },
    stage   = vdsl.stage { latent_image = ctx.prev_output },
    seed    = ctx.seed, steps = 20, cfg = 7,
  }
end)

local jsm = js:compile({ { key = "a" } }, { mode = "full" })

T.eq("judge scores: p3 wf count", #jsm.passes[3].workflows, 1)
T.eq("judge scores: survivors[1]", jsm.judge_gate.survivors[1], "d06")
T.ok("judge scores: scores recorded", jsm.judge_gate.scores ~= nil)
T.ok("judge scores: pruned recorded", jsm.judge_gate.pruned ~= nil)
T.eq("judge scores: pruned count", #jsm.judge_gate.pruned, 2)

-- Cleanup
os.execute("rm -rf output/js_out")

-- ============================================================
-- Judge: string return (pick-compatible)
-- ============================================================

local jstr = pipeline.new("test_judge_str", {
  save_dir  = "jstr_out",
  seed_base = 0,
  size      = { 512, 512 },
})
jstr:pass("p1", function(v, ctx)
  return {
    world = vdsl.world { model = "m.safetensors" },
    cast  = { vdsl.cast { subject = v.key } },
    seed  = ctx.seed, steps = 10, cfg = 5,
  }
end)
jstr:pass("p2", {
  sweep = { denoise = { 0.5, 0.7 } }
}, function(v, ctx)
  return {
    world   = vdsl.world { model = "r.safetensors" },
    cast    = { vdsl.cast { subject = v.key } },
    stage   = vdsl.stage { latent_image = ctx.prev_output },
    seed    = ctx.seed, steps = 15, cfg = 5,
    denoise = v.sweep.denoise,
  }
end)
jstr:judge(function(candidates)
  return "d07"  -- single string
end)
jstr:pass("p3", function(v, ctx)
  return {
    world   = vdsl.world { model = "f.safetensors" },
    cast    = { vdsl.cast { subject = v.key } },
    stage   = vdsl.stage { latent_image = ctx.prev_output },
    seed    = ctx.seed, steps = 20, cfg = 7,
  }
end)

local jstrm = jstr:compile({ { key = "x" } }, { mode = "full" })

-- String return → 1 survivor → p3 gets 1 workflow
T.eq("judge str: p3 wf count", #jstrm.passes[3].workflows, 1)
T.ok("judge str: p3 transfer references d07",
  jstrm.passes[3].transfers[1].from:find("p2_x__d07") ~= nil)

-- Cleanup
os.execute("rm -rf output/jstr_out")

-- ============================================================
-- Judge: nil return (unresolved)
-- ============================================================

local ju = pipeline.new("test_judge_unresolved", {
  save_dir  = "ju_out",
  seed_base = 0,
  size      = { 512, 512 },
})
ju:pass("p1", function(v, ctx)
  return {
    world = vdsl.world { model = "m.safetensors" },
    cast  = { vdsl.cast { subject = v.key } },
    seed  = ctx.seed, steps = 10, cfg = 5,
  }
end)
ju:pass("p2", {
  sweep = { denoise = { 0.5, 0.7 } }
}, function(v, ctx)
  return {
    world   = vdsl.world { model = "r.safetensors" },
    cast    = { vdsl.cast { subject = v.key } },
    stage   = vdsl.stage { latent_image = ctx.prev_output },
    seed    = ctx.seed, steps = 10, cfg = 5,
    denoise = v.sweep.denoise,
  }
end)
ju:judge(function() return nil end)
ju:pass("p3", function(v, ctx)
  return {
    world = vdsl.world { model = "f.safetensors" },
    cast  = { vdsl.cast { subject = v.key } },
    seed  = ctx.seed, steps = 20, cfg = 7,
  }
end)

local jum = ju:compile({ { key = "x" } }, { mode = "full" })

T.eq("judge unresolved: pass count", #jum.passes, 2)
T.eq("judge unresolved: pick_gate status", jum.pick_gate.status, "pending")
T.eq("judge unresolved: pick_gate type", jum.pick_gate.type, "judge")

-- Cleanup
os.execute("rm -rf output/ju_out")

-- ============================================================
-- Judge: sweep → judge → sweep (multi-stage)
-- ============================================================

local jms = pipeline.new("test_judge_multi", {
  save_dir  = "jms_out",
  seed_base = 0,
  size      = { 512, 512 },
})
jms:pass("p1", function(v, ctx)
  return {
    world = vdsl.world { model = "m.safetensors" },
    cast  = { vdsl.cast { subject = v.key } },
    seed  = ctx.seed, steps = 10, cfg = 5,
  }
end)
jms:pass("p2", {
  sweep = { denoise = { 0.5, 0.6, 0.7 } }
}, function(v, ctx)
  return {
    world   = vdsl.world { model = "r.safetensors" },
    cast    = { vdsl.cast { subject = v.key } },
    stage   = vdsl.stage { latent_image = ctx.prev_output },
    seed    = ctx.seed, steps = 15, cfg = 5,
    denoise = v.sweep.denoise,
  }
end)
jms:judge(function(candidates)
  return { "d06", "d07" }  -- keep 2
end)
jms:pass("p3", {
  sweep = { cfg = { 4, 6 } }
}, function(v, ctx)
  return {
    world   = vdsl.world { model = "f.safetensors" },
    cast    = { vdsl.cast { subject = v.key } },
    stage   = vdsl.stage { latent_image = ctx.prev_output },
    seed    = ctx.seed, steps = 20,
    cfg     = v.sweep.cfg,
  }
end)

local jmsm = jms:compile({ { key = "a" } }, { mode = "full" })

-- p2: 3 workflows (a × 3 denoise)
T.eq("judge multi: p2 wf count", #jmsm.passes[2].workflows, 3)
-- p3: 2 survivors × 2 cfg = 4 workflows
T.eq("judge multi: p3 wf count", #jmsm.passes[3].workflows, 4)

-- Cleanup
os.execute("rm -rf output/jms_out")

-- ============================================================
-- Judge: error cases
-- ============================================================

T.err("judge: no prior pass", function()
  local p = pipeline.new("judge_err")
  p:judge(function() end)
end)

T.err("judge: not a function", function()
  local p = pipeline.new("judge_err2")
  p:pass("p1", function(v, ctx)
    return {
      world = vdsl.world { model = "m.safetensors" },
      cast  = { vdsl.cast { subject = "x" } },
      seed = 1, steps = 10, cfg = 5,
    }
  end)
  p:judge("not_a_function")
end)

T.err("judge: duplicate gate (judge after pick)", function()
  local p = pipeline.new("judge_err3")
  p:pass("p1", function(v, ctx)
    return {
      world = vdsl.world { model = "m.safetensors" },
      cast  = { vdsl.cast { subject = "x" } },
      seed = 1, steps = 10, cfg = 5,
    }
  end)
  p:pick(function() return nil end)
  p:judge(function() return nil end)
end)

T.err("pick: duplicate gate (pick after judge)", function()
  local p = pipeline.new("judge_err4")
  p:pass("p1", function(v, ctx)
    return {
      world = vdsl.world { model = "m.safetensors" },
      cast  = { vdsl.cast { subject = "x" } },
      seed = 1, steps = 10, cfg = 5,
    }
  end)
  p:judge(function() return nil end)
  p:pick(function() return nil end)
end)

-- ============================================================
-- Summary
-- ============================================================

T.summary()
