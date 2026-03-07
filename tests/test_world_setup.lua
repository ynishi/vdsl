--- test_world_setup.lua: Verify World entity as execution environment container.
-- Tests that sampler/steps/cfg/size/lora/post can be specified via World,
-- and that the resolution chain (opts > world > theme > fallback) works correctly.
--
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;tests/?.lua;'..package.path" tests/test_world_setup.lua

local vdsl = require("vdsl")
local T    = require("harness")

-- ============================================================
-- World entity: new fields accepted
-- ============================================================
local w = vdsl.world {
  model     = "wai_v16.safetensors",
  clip_skip = 2,
  sampler   = "dpmpp_2m",
  steps     = 30,
  cfg       = 7.0,
  scheduler = "karras",
  size      = { 832, 1216 },
  denoise   = 0.8,
}
T.ok("world: is world",      vdsl.entity.is(w, "world"))
T.eq("world: model",         w.model,     "wai_v16.safetensors")
T.eq("world: sampler",       w.sampler,   "dpmpp_2m")
T.eq("world: steps",         w.steps,     30)
T.eq("world: cfg",           w.cfg,       7.0)
T.eq("world: scheduler",     w.scheduler, "karras")
T.eq("world: size[1]",       w.size[1],   832)
T.eq("world: size[2]",       w.size[2],   1216)
T.eq("world: denoise",       w.denoise,   0.8)

-- Fields are nil when not specified (backward compat)
local w_minimal = vdsl.world { model = "base.safetensors" }
T.eq("world minimal: sampler nil",   w_minimal.sampler,   nil)
T.eq("world minimal: steps nil",     w_minimal.steps,     nil)
T.eq("world minimal: cfg nil",       w_minimal.cfg,       nil)
T.eq("world minimal: size nil",      w_minimal.size,      nil)
T.eq("world minimal: lora nil",      w_minimal.lora,      nil)
T.eq("world minimal: post nil",      w_minimal.post,      nil)

-- ============================================================
-- World with lora
-- ============================================================
-- Array form (backward compat)
local w_lora = vdsl.world {
  model = "wai.safetensors",
  lora  = { { name = "detail.safetensors", weight = 0.6 } },
}
T.eq("world lora array: name",   w_lora.lora[1].name,   "detail.safetensors")
T.eq("world lora array: weight", w_lora.lora[1].weight,  0.6)

-- Dict form (named LoRA pool)
local w_lora_dict = vdsl.world {
  model = "wai.safetensors",
  lora  = {
    style  = { name = "style_v1.safetensors", weight = 0.8 },
    detail = { name = "add_detail.safetensors", weight = 0.6 },
  },
}
T.eq("world lora dict: style",  w_lora_dict._lora_map.style.name, "style_v1.safetensors")
T.eq("world lora dict: detail", w_lora_dict._lora_map.detail.weight, 0.6)
-- Backward compat: world.lora still works as array
T.eq("world lora dict: compat len", #w_lora_dict.lora, 2)

-- resolve_lora: exact key
local resolved = w_lora_dict:resolve_lora("style")
T.eq("resolve lora: exact", resolved.name, "style_v1.safetensors")
-- resolve_lora: fuzzy key substring
local resolved2 = w_lora_dict:resolve_lora("det")
T.eq("resolve lora: fuzzy key", resolved2.name, "add_detail.safetensors")
-- resolve_lora: miss
local resolved3 = w_lora_dict:resolve_lora("nonexistent")
T.eq("resolve lora: miss", resolved3, nil)

-- ============================================================
-- World with post
-- ============================================================
local w_post = vdsl.world {
  model = "wai.safetensors",
  post  = vdsl.post("face", { fidelity = 0.5 }),
}
T.ok("world post: is post", vdsl.entity.is(w_post.post, "post"))

-- ============================================================
-- Render: World provides sampler params (no opts override)
-- ============================================================
local r_world = vdsl.render {
  world = vdsl.world {
    model   = "model.safetensors",
    sampler = "dpmpp_2m",
    steps   = 25,
    cfg     = 6.5,
    scheduler = "karras",
    size    = { 768, 1024 },
  },
  cast = { vdsl.cast { subject = "a cat", negative = "bad" } },
  seed = 100,
}

for _, node in pairs(r_world.prompt) do
  if node.class_type == "KSampler" then
    T.eq("world render: sampler", node.inputs.sampler_name, "dpmpp_2m")
    T.eq("world render: steps",   node.inputs.steps,        25)
    T.eq("world render: cfg",     node.inputs.cfg,          6.5)
    T.eq("world render: scheduler", node.inputs.scheduler,  "karras")
  end
  if node.class_type == "EmptyLatentImage" then
    T.eq("world render: width",  node.inputs.width,  768)
    T.eq("world render: height", node.inputs.height, 1024)
  end
end

-- ============================================================
-- HINT override: opts > world
-- ============================================================
local r_hint = vdsl.render {
  world = vdsl.world {
    model   = "model.safetensors",
    sampler = "dpmpp_2m",
    steps   = 25,
    cfg     = 6.5,
    size    = { 768, 1024 },
  },
  cast    = { vdsl.cast { subject = "a cat", negative = "bad" } },
  seed    = 100,
  -- HINT: override world values
  steps   = 40,
  cfg     = 8.0,
  sampler = "euler",
  size    = { 512, 512 },
}

for _, node in pairs(r_hint.prompt) do
  if node.class_type == "KSampler" then
    T.eq("hint override: sampler", node.inputs.sampler_name, "euler")
    T.eq("hint override: steps",   node.inputs.steps,        40)
    T.eq("hint override: cfg",     node.inputs.cfg,          8.0)
  end
  if node.class_type == "EmptyLatentImage" then
    T.eq("hint override: width",  node.inputs.width,  512)
    T.eq("hint override: height", node.inputs.height, 512)
  end
end

-- ============================================================
-- Backward compat: opts-only (no world params) still works
-- ============================================================
local r_compat = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "a cat", negative = "bad" } },
  seed  = 1,
  steps = 15,
  cfg   = 4.0,
  sampler = "euler_ancestral",
  size  = { 640, 480 },
}

for _, node in pairs(r_compat.prompt) do
  if node.class_type == "KSampler" then
    T.eq("compat: sampler", node.inputs.sampler_name, "euler_ancestral")
    T.eq("compat: steps",   node.inputs.steps,        15)
    T.eq("compat: cfg",     node.inputs.cfg,          4.0)
  end
  if node.class_type == "EmptyLatentImage" then
    T.eq("compat: width",  node.inputs.width,  640)
    T.eq("compat: height", node.inputs.height, 480)
  end
end

-- ============================================================
-- World.lora: applied before cast LoRA in node graph
-- ============================================================
local r_wlora = vdsl.render {
  world = vdsl.world {
    model = "model.safetensors",
    lora  = { { name = "world_lora.safetensors", weight = 0.5 } },
  },
  cast = {
    vdsl.cast {
      subject  = "warrior",
      negative = "ugly",
      lora     = { { name = "cast_lora.safetensors", weight = 0.8 } },
    },
  },
  seed  = 1,
  steps = 10,
}

-- Count LoRA nodes and verify both are present
local lora_nodes = {}
for _, node in pairs(r_wlora.prompt) do
  if node.class_type == "LoraLoader" then
    lora_nodes[#lora_nodes + 1] = node.inputs.lora_name
  end
end
T.eq("world+cast lora: count", #lora_nodes, 2)
-- World LoRA should appear (order verified by node ID, but both present)
local has_world_lora = false
local has_cast_lora = false
for _, name in ipairs(lora_nodes) do
  if name == "world_lora.safetensors" then has_world_lora = true end
  if name == "cast_lora.safetensors" then has_cast_lora = true end
end
T.ok("world+cast lora: world lora present", has_world_lora)
T.ok("world+cast lora: cast lora present",  has_cast_lora)

-- ============================================================
-- World.lora only (no cast lora)
-- ============================================================
local r_wlora_only = vdsl.render {
  world = vdsl.world {
    model = "model.safetensors",
    lora  = { { name = "model_fix.safetensors", weight = 0.3 } },
  },
  cast = { vdsl.cast { subject = "cat", negative = "bad" } },
  seed = 1, steps = 10,
}

local wlora_count = 0
for _, node in pairs(r_wlora_only.prompt) do
  if node.class_type == "LoraLoader" then
    T.eq("world lora only: name", node.inputs.lora_name, "model_fix.safetensors")
    T.eq("world lora only: weight", node.inputs.strength_model, 0.3)
    wlora_count = wlora_count + 1
  end
end
T.eq("world lora only: count", wlora_count, 1)

-- ============================================================
-- World.post: used when opts.post is absent
-- ============================================================
local r_wpost = vdsl.render {
  world = vdsl.world {
    model = "model.safetensors",
    post  = vdsl.post("face", { fidelity = 0.7 }),
  },
  cast = { vdsl.cast { subject = "portrait", negative = "bad" } },
  seed = 1, steps = 10,
  auto_post = false,  -- disable hint-based auto post
}

local has_face_restore = false
for _, node in pairs(r_wpost.prompt) do
  if node.class_type == "FaceRestoreWithModel" then
    has_face_restore = true
    T.eq("world post: fidelity", node.inputs.fidelity, 0.7)
  end
end
T.ok("world post: face restore present", has_face_restore)

-- ============================================================
-- opts.post overrides world.post (HINT pattern)
-- ============================================================
local r_post_hint = vdsl.render {
  world = vdsl.world {
    model = "model.safetensors",
    post  = vdsl.post("face", { fidelity = 0.7 }),
  },
  cast = { vdsl.cast { subject = "portrait", negative = "bad" } },
  seed = 1, steps = 10,
  post = vdsl.post("sharpen", { radius = 2, sigma = 1.5 }),  -- HINT override
}

local has_sharpen = false
local has_face_in_override = false
for _, node in pairs(r_post_hint.prompt) do
  if node.class_type == "ImageSharpen" then has_sharpen = true end
  if node.class_type == "FaceRestoreWithModel" then has_face_in_override = true end
end
T.ok("post hint: sharpen present",    has_sharpen)
T.ok("post hint: face NOT present",   not has_face_in_override)

-- ============================================================
-- Resolution chain: opts > world > fallback
-- ============================================================

-- World overrides fallback
local r_chain1 = vdsl.render {
  world = vdsl.world {
    model = "model.safetensors",
    steps = 35,
  },
  cast  = { vdsl.cast { subject = "cat", negative = "bad" } },
  seed  = 1,
}

for _, node in pairs(r_chain1.prompt) do
  if node.class_type == "KSampler" then
    T.eq("chain: world steps > fallback", node.inputs.steps, 35)
    T.eq("chain: fallback cfg used",      node.inputs.cfg,   7.0)
  end
end

-- opts overrides world
local r_chain2 = vdsl.render {
  world = vdsl.world {
    model = "model.safetensors",
    steps = 35,
    cfg   = 7.0,
  },
  cast  = { vdsl.cast { subject = "cat", negative = "bad" } },
  seed  = 1,
  steps = 20,
  cfg   = 3.0,
}

for _, node in pairs(r_chain2.prompt) do
  if node.class_type == "KSampler" then
    T.eq("chain: opts steps > world", node.inputs.steps, 20)
    T.eq("chain: opts cfg > world",   node.inputs.cfg,   3.0)
  end
end

T.summary()
