--- test_training.lua: Tests for Training module (Methods, Verify pipeline)
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;tests/?.lua;'..package.path" tests/test_training.lua

local vdsl     = require("vdsl")
local training = require("vdsl.training")
local T        = require("harness")

-- ============================================================
-- Method dispatch
-- ============================================================

-- available_methods includes all 5
local methods = training.available_methods()
T.eq("methods: count", #methods, 5)

-- unknown method errors
T.err("method: unknown", function()
  training.method("nonexistent")
end)

-- ============================================================
-- Method: kohya config generation
-- ============================================================

local kohya = training.method("kohya")

local toml = kohya.config {
  checkpoint = "/workspace/models/wai.safetensors",
  data_dir   = "/workspace/datasets/abc01",
  rank       = 8,
  steps      = 300,
  lr         = 0.0003,
}

T.ok("kohya: has model",       toml:find("wai.safetensors") ~= nil)
T.ok("kohya: has data dir",    toml:find("abc01") ~= nil)
T.ok("kohya: has rank",        toml:find("network_dim = 8") ~= nil)
T.ok("kohya: has steps",       toml:find("max_train_steps = 300") ~= nil)
T.ok("kohya: has lr",          toml:find("0.0003") ~= nil)

-- Dataset directory structure
local ds_path = kohya.dataset_path {
  data_dir = "/workspace/datasets",
  trigger  = "abc01",
  repeats  = 10,
}
T.eq("kohya: ds path", ds_path, "/workspace/datasets/10_abc01")

-- Command generation
local cmd = kohya.command {
  config_path = "/workspace/config.toml",
}
T.ok("kohya: has accelerate",  cmd:find("accelerate launch") ~= nil)
T.ok("kohya: has config",      cmd:find("config.toml") ~= nil)
T.ok("kohya: has cd repo",     cmd:find("cd /workspace/sd%-scripts") ~= nil)

-- Validation
T.err("kohya: no checkpoint", function()
  kohya.config { data_dir = "/x" }
end)

T.err("kohya: no data_dir", function()
  kohya.config { checkpoint = "/x" }
end)

-- ============================================================
-- Method: sliders config generation
-- ============================================================

local sliders = training.method("sliders")

-- sliders requires a concept-like archetype with axis
-- We pass a minimal table that satisfies the interface
local concept_arch = { kind = "concept", name = "test_slider", axis = {} }

local slider_cfg = sliders.config {
  archetype  = concept_arch,
  checkpoint = "/workspace/models/wai.safetensors",
  rank       = 4,
  iterations = 1000,
  lr         = 0.0002,
}

T.ok("sliders: has name",     slider_cfg:find("test_slider") ~= nil)
T.ok("sliders: has rank",     slider_cfg:find("rank: 4") ~= nil)
T.ok("sliders: has iter",     slider_cfg:find("1000") ~= nil)
T.ok("sliders: has xformers false", slider_cfg:find("use_xformers: false") ~= nil)
T.ok("sliders: has bfloat16",      slider_cfg:find("bfloat16") ~= nil)

-- Prompts generation
local slider_prompts = sliders.prompts {
  target        = "1girl",
  positive      = "1girl, voluptuous",
  unconditional = "1girl, slim",
}
T.ok("sliders: prompts target",   slider_prompts:find("1girl") ~= nil)
T.ok("sliders: prompts positive", slider_prompts:find("voluptuous") ~= nil)
T.ok("sliders: prompts action",   slider_prompts:find("enhance") ~= nil)

-- Prompts validation
T.err("sliders: prompts no target", function()
  sliders.prompts { positive = "x", unconditional = "y" }
end)

local slider_cmd = sliders.command {
  config_path = "/workspace/config.yaml",
  name        = "test_slider",
  dataset_dir = "/workspace/datasets/test",
}
T.ok("sliders: has python3",  slider_cmd:find("python3") ~= nil)
T.ok("sliders: has config",   slider_cmd:find("config.yaml") ~= nil)
T.ok("sliders: has folder_main", slider_cmd:find("folder_main") ~= nil)
T.ok("sliders: scales uses =",  slider_cmd:find('--scales="') ~= nil)

-- ============================================================
-- Method: LECO config generation
-- ============================================================

local leco = training.method("leco")

local leco_arch = {
  kind = "concept",
  name = "test_leco",
  axis = {
    before = { prompt = "normal lighting" },
    after  = { prompt = "dramatic chiaroscuro lighting" },
  },
}

local leco_cfg = leco.config {
  archetype  = leco_arch,
  checkpoint = "/workspace/models/wai.safetensors",
  rank       = 4,
  iterations = 500,
  lr         = 0.0001,
}

T.ok("leco: has name",       leco_cfg:find("test_leco") ~= nil)
T.ok("leco: has rank",       leco_cfg:find("rank: 4") ~= nil)
T.ok("leco: has iter",       leco_cfg:find("500") ~= nil)
T.ok("leco: has before",     leco_cfg:find("normal lighting") ~= nil)
T.ok("leco: has after",      leco_cfg:find("dramatic chiaroscuro lighting") ~= nil)

local leco_cmd = leco.command {
  config_path = "/workspace/leco_config.yaml",
}
T.ok("leco: has python",     leco_cmd:find("python") ~= nil)
T.ok("leco: has config",     leco_cmd:find("leco_config.yaml") ~= nil)

-- LECO text extraction from concept axis
T.eq("leco: before prompt",  leco.axis_prompt(leco_arch, "before"), "normal lighting")
T.eq("leco: after prompt",   leco.axis_prompt(leco_arch, "after"), "dramatic chiaroscuro lighting")

-- ============================================================
-- Method: LyCORIS config generation
-- ============================================================

local lycoriss = training.method("lycoriss")

local lyco_toml = lycoriss.config {
  checkpoint = "/workspace/models/wai.safetensors",
  data_dir   = "/workspace/datasets/abc01",
  algo       = "loha",
  rank       = 8,
  steps      = 400,
}

T.ok("lycoriss: has model",       lyco_toml:find("wai.safetensors") ~= nil)
T.ok("lycoriss: has lycoris mod", lyco_toml:find("lycoris.kohya") ~= nil)
T.ok("lycoriss: has algo",        lyco_toml:find("loha") ~= nil)
T.ok("lycoriss: has rank",        lyco_toml:find("network_dim = 8") ~= nil)
T.ok("lycoriss: has steps",       lyco_toml:find("max_train_steps = 400") ~= nil)

-- LoKr variant
local lokr_toml = lycoriss.config {
  checkpoint = "/workspace/models/wai.safetensors",
  data_dir   = "/workspace/datasets/abc01",
  algo       = "lokr",
  rank       = 4,
}

T.ok("lycoriss: lokr algo",  lokr_toml:find("lokr") ~= nil)
T.ok("lycoriss: lokr rank",  lokr_toml:find("network_dim = 4") ~= nil)

-- Unknown algo
T.err("lycoriss: unknown algo", function()
  lycoriss.config {
    checkpoint = "/x", data_dir = "/x", algo = "invalid",
  }
end)

-- ============================================================
-- Method: Textual Inversion config generation
-- ============================================================

local ti = training.method("ti")

local ti_cfg = ti.config {
  checkpoint  = "/workspace/models/wai.safetensors",
  data_dir    = "/workspace/datasets/abc01",
  token       = "abc01",
  num_vectors = 8,
  steps       = 2000,
  lr          = 0.005,
}

T.ok("ti: has model",         ti_cfg:find("wai.safetensors") ~= nil)
T.ok("ti: has token",         ti_cfg:find("abc01") ~= nil)
T.ok("ti: has num_vectors",   ti_cfg:find("num_vectors_per_token = 8") ~= nil)
T.ok("ti: has steps",         ti_cfg:find("max_train_steps = 2000") ~= nil)
T.ok("ti: has lr",            ti_cfg:find("0.005") ~= nil)

local ti_cmd = ti.command {
  config_path = "/workspace/ti_config.toml",
}
T.ok("ti: has train cmd",    ti_cmd:find("train_textual_inversion") ~= nil)
T.ok("ti: has config",       ti_cmd:find("ti_config.toml") ~= nil)

-- ============================================================
-- Verify: Pipeline construction
-- ============================================================

-- verify builds a Pipeline with sweep + judge gate
local pipe = training.verify {
  name      = "verify_test",
  lora      = "test_abc.safetensors",
  world     = vdsl.world { model = "model_a.safetensors" },
  weights   = { 0.3, 0.5, 0.7, 1.0 },
  seed_base = 42000,
  size      = { 832, 1216 },
}

-- pipe is a Pipeline instance
T.ok("verify: returns pipeline",  pipe ~= nil)
T.ok("verify: has compile",       type(pipe.compile) == "function")

-- Compile with test variations (requires VDSL_OUT_DIR for JSON output)
-- Here we verify the pipeline structure compiles without error
local test_vars = {
  { key = "dress",  subject = vdsl.subject("1girl"):with("black dress") },
  { key = "bikini", subject = vdsl.subject("1girl"):with("white bikini") },
}

-- Set VDSL_OUT_DIR to a temp dir for testing (compile writes JSONs there)
local tmp_dir = os.tmpname() .. "_vdsl_test"
os.execute("mkdir -p " .. tmp_dir)

-- Temporarily set env var (Lua doesn't have setenv, so we test without it)
-- Instead, test that compile produces the manifest structure
local manifest = pipe:compile(test_vars)

T.ok("verify: manifest",          manifest ~= nil)
T.eq("verify: manifest name",     manifest.name, "verify_test")
T.eq("verify: passes count",      #manifest.passes, 1)
T.eq("verify: pass name",         manifest.passes[1].name, "sweep")

-- Sweep: 4 weights × 2 tests = 8 workflows
T.eq("verify: variation count",   manifest.passes[1].variation_count, 8)

-- Cleanup
os.execute("rm -rf " .. tmp_dir)

-- Validation errors
T.err("verify: no lora", function()
  training.verify {
    world = vdsl.world { model = "x.safetensors" },
    weights = { 0.5 },
  }
end)

T.err("verify: no world", function()
  training.verify {
    lora = "x.safetensors",
    weights = { 0.5 },
  }
end)

T.err("verify: no weights", function()
  training.verify {
    lora = "x.safetensors",
    world = vdsl.world { model = "x.safetensors" },
  }
end)

T.err("verify: empty weights", function()
  training.verify {
    lora = "x.safetensors",
    world = vdsl.world { model = "x.safetensors" },
    weights = {},
  }
end)

-- ============================================================
-- Verify: with existing world LoRAs
-- ============================================================

local pipe2 = training.verify {
  name    = "verify_merge",
  lora    = "new_lora.safetensors",
  world   = vdsl.world {
    model = "model_a.safetensors",
    lora  = { { name = "existing.safetensors", weight = 0.5 } },
  },
  weights = { 0.7 },
}

local manifest2 = pipe2:compile({
  { key = "test", subject = vdsl.subject("1girl") },
})

T.ok("verify merge: compiles", manifest2 ~= nil)
T.eq("verify merge: 1 workflow", manifest2.passes[1].variation_count, 1)

-- ============================================================
-- Env: declarative environment specification
-- ============================================================

local env = training.env

-- Create a basic env spec
local spec1 = env.new {
  name = "test_env",
  pip = {
    install = {
      { "diffusers", "0.32.2" },
      { "transformers", "4.47.1" },
    },
    uninstall = { "xformers" },
  },
  verify = { "torch", "diffusers" },
  notes = { "test note" },
}

T.ok("env: creates spec",    spec1 ~= nil)
T.ok("env: has summary",     type(spec1.summary) == "function")
T.ok("env: has setup_script", type(spec1.setup_script) == "function")

-- Summary contains key info
local summary = spec1:summary()
T.ok("env: summary name",     summary:find("test_env") ~= nil)
T.ok("env: summary packages", summary:find("diffusers==0.32.2") ~= nil)
T.ok("env: summary uninstall", summary:find("xformers") ~= nil)
T.ok("env: summary note",     summary:find("test note") ~= nil)

-- Setup script is valid bash
local script = spec1:setup_script()
T.ok("env: script shebang",   script:find("#!/bin/bash") ~= nil)
T.ok("env: script set -e",    script:find("set %-e") ~= nil)
T.ok("env: script pip install", script:find("pip install diffusers==0.32.2") ~= nil)
T.ok("env: script pip uninstall", script:find("pip uninstall %-y xformers") ~= nil)
T.ok("env: script verify",    script:find("import torch") ~= nil)

-- Verify script
local vscript = spec1:verify_script()
T.ok("env: verify imports",   vscript:find("import diffusers") ~= nil)

-- Merge two specs
local spec2 = env.new {
  name = "extra",
  pip = {
    install = {
      { "wandb" },
      { "diffusers", "0.33.0" },  -- override version
    },
  },
  verify = { "wandb" },
}

local merged = spec1:merge(spec2)
local ms = merged:summary()
T.ok("env merge: combined name", ms:find("test_env%+extra") ~= nil)
T.ok("env merge: has wandb",    ms:find("wandb") ~= nil)
-- diffusers version should be overridden by spec2
T.ok("env merge: diffusers override", ms:find("diffusers==0.33.0") ~= nil)
-- verify deduplicates
local mvs = merged:verify_script()
T.ok("env merge: verify torch",   mvs:find("import torch") ~= nil)
T.ok("env merge: verify wandb",   mvs:find("import wandb") ~= nil)

-- Pre-built base spec exists
T.ok("env: base_sdxl_cu124",  env.base_sdxl_cu124 ~= nil)
local base_summary = env.base_sdxl_cu124:summary()
T.ok("env: base has diffusers", base_summary:find("diffusers") ~= nil)
T.ok("env: base has xformers uninstall", base_summary:find("xformers") ~= nil)

-- Sliders method carries env spec
local sliders_env = sliders.env
T.ok("sliders: has env",       sliders_env ~= nil)
local sliders_script = sliders_env:setup_script()
T.ok("sliders env: has git clone",    sliders_script:find("git clone") ~= nil)
T.ok("sliders env: has mkdir models", sliders_script:find("mkdir %-p /workspace/sliders/models") ~= nil)
T.ok("sliders env: has randn note",   sliders_env:summary():find("randn_tensor") ~= nil)

-- ============================================================
-- Env: kohya method carries env spec
-- ============================================================

local kohya_env = kohya.env
T.ok("kohya: has env",           kohya_env ~= nil)
local kohya_script = kohya_env:setup_script()
T.ok("kohya env: has git clone",     kohya_script:find("git clone") ~= nil)
T.ok("kohya env: has sd-scripts",    kohya_script:find("sd%-scripts") ~= nil)
T.ok("kohya env: has pip install -e", kohya_script:find("pip install %-e .") ~= nil)
T.ok("kohya env: has bitsandbytes",  kohya_env:summary():find("bitsandbytes") ~= nil)
T.ok("kohya env: has mkdir",         kohya_script:find("mkdir %-p /workspace/models") ~= nil)

-- ============================================================
-- Env: lycoriss method carries env spec
-- ============================================================

local lycoriss_env = lycoriss.env
T.ok("lycoriss: has env",          lycoriss_env ~= nil)
local lyco_script = lycoriss_env:setup_script()
T.ok("lycoriss env: has lycoris",  lyco_script:find("lycoris%-lora") ~= nil)
T.ok("lycoriss env: has sd-scripts", lyco_script:find("sd%-scripts") ~= nil)
T.ok("lycoriss env: verify lycoris", lycoriss_env:verify_script():find("import lycoris") ~= nil)

-- ============================================================
T.summary()
