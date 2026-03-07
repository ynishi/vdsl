--- test_compiler.lua: Verify DSL compilation and JSON output
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;tests/?.lua;'..package.path" tests/test_compiler.lua

local vdsl = require("vdsl")
local json = require("vdsl.util.json")
local T    = require("harness")

-- Isolate from user config (workspaces/config.lua)
vdsl.config._override({})

-- ============================================================
-- JSON encoder tests
-- ============================================================
T.eq("json: string",   json.encode("hello"),    '"hello"')
T.eq("json: number",   json.encode(42),         "42")
T.eq("json: float",    json.encode(7.5),        "7.5")
T.eq("json: bool",     json.encode(true),       "true")
T.eq("json: null",     json.encode(nil),        "null")
T.eq("json: array",    json.encode({1, 2, 3}),  "[1,2,3]")
T.eq("json: node ref", json.encode({"4", 0}),   '["4",0]')
T.eq("json: escape",   json.encode('a"b'),      '"a\\"b"')

-- ============================================================
-- JSON decoder tests
-- ============================================================
T.eq("decode: string",    json.decode('"hello"'),     "hello")
T.eq("decode: number",    json.decode('42'),           42)
T.eq("decode: float",     json.decode('3.14'),         3.14)
T.eq("decode: negative",  json.decode('-7'),           -7)
T.eq("decode: exponent",  json.decode('1e3'),          1000)
T.eq("decode: true",      json.decode('true'),         true)
T.eq("decode: false",     json.decode('false'),        false)
T.eq("decode: null",      json.decode('null'),         nil)

local arr = json.decode('[1, 2, 3]')
T.eq("decode: arr len",   #arr, 3)
T.eq("decode: arr[1]",    arr[1], 1)
T.eq("decode: arr[3]",    arr[3], 3)

local obj = json.decode('{"a": 1, "b": "hello"}')
T.eq("decode: obj.a", obj.a, 1)
T.eq("decode: obj.b", obj.b, "hello")

local nested = json.decode('{"x": [1, {"y": true}]}')
T.eq("decode: nested arr",   nested.x[1], 1)
T.eq("decode: nested obj.y", nested.x[2].y, true)

T.eq("decode: escape quote",     json.decode('"a\\"b"'),     'a"b')
T.eq("decode: escape newline",   json.decode('"a\\nb"'),     'a\nb')
T.eq("decode: escape tab",       json.decode('"a\\tb"'),     'a\tb')
T.eq("decode: escape slash",     json.decode('"a\\/b"'),     'a/b')
T.eq("decode: escape backslash", json.decode('"a\\\\b"'),    'a\\b')
T.eq("decode: unicode ascii",    json.decode('"\\u0041"'),   "A")

local empty_arr = json.decode('[]')
T.eq("decode: empty array", #empty_arr, 0)
local empty_obj = json.decode('{}')
T.eq("decode: empty obj", type(empty_obj), "table")

local ref = json.decode('["4", 0]')
T.eq("decode: ref id",   ref[1], "4")
T.eq("decode: ref slot", ref[2], 0)

local ws = json.decode('  {  "a"  :  1  }  ')
T.eq("decode: whitespace", ws.a, 1)

-- JSON roundtrip
local rt_data = { name = "test", values = {1, 2, 3}, nested = { flag = true } }
local encoded = json.encode(rt_data)
local decoded = json.decode(encoded)
T.eq("roundtrip: name",      decoded.name,        "test")
T.eq("roundtrip: values[2]", decoded.values[2],   2)
T.eq("roundtrip: nested",    decoded.nested.flag,  true)

-- ============================================================
-- World entity tests
-- ============================================================
local w = vdsl.world { model = "test_model.safetensors" }
T.ok("world: is world",      vdsl.entity.is(w, "world"))
T.eq("world: model",         w.model, "test_model.safetensors")
T.eq("world: clip_skip",     w.clip_skip, 1)

local w2 = vdsl.world { model = "xl.safetensors", vae = "custom.safetensors", clip_skip = 2 }
T.eq("world: vae",           w2.vae, "custom.safetensors")
T.eq("world: clip_skip 2",   w2.clip_skip, 2)

T.err("world: missing model", function() vdsl.world {} end)

-- ============================================================
-- Stage entity tests
-- ============================================================
local s = vdsl.stage {}
T.ok("stage: is stage",      vdsl.entity.is(s, "stage"))
T.eq("stage: cn nil",        s.controlnet, nil)

local s2 = vdsl.stage {
  controlnet = { { type = "depth", image = "d.png", strength = 0.8 } },
  latent_image = "init.png",
}
T.eq("stage: cn type",       s2.controlnet[1].type, "depth")
T.eq("stage: cn strength",   s2.controlnet[1].strength, 0.8)
T.eq("stage: latent",        s2.latent_image, "init.png")

-- ============================================================
-- Minimal render (txt2img)
-- ============================================================
local r1 = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "a cat", negative = "bad" } },
  seed  = 1,
  steps = 10,
  cfg   = 5.0,
  size  = { 512, 512 },
}

T.ok("render: has prompt", type(r1.prompt) == "table")
T.ok("render: has json",   type(r1.json) == "string")
T.ok("render: has graph",  r1.graph ~= nil)

local node_types = {}
for _, node in pairs(r1.prompt) do
  node_types[node.class_type] = true
end
T.ok("render: Checkpoint",    node_types["CheckpointLoaderSimple"])
T.ok("render: CLIPEncode",    node_types["CLIPTextEncode"])
T.ok("render: EmptyLatent",   node_types["EmptyLatentImage"])
T.ok("render: KSampler",      node_types["KSampler"])
T.ok("render: VAEDecode",     node_types["VAEDecode"])
T.ok("render: SaveImage",     node_types["SaveImage"])

for _, node in pairs(r1.prompt) do
  if node.class_type == "KSampler" then
    T.eq("ksampler: seed",  node.inputs.seed,  1)
    T.eq("ksampler: steps", node.inputs.steps, 10)
    T.eq("ksampler: cfg",   node.inputs.cfg,   5.0)
  end
end

-- ============================================================
-- Full render (LoRA, ControlNet, VAE, clip_skip)
-- ============================================================
local r2 = vdsl.render {
  world = vdsl.world {
    model     = "xl.safetensors",
    vae       = "custom_vae.safetensors",
    clip_skip = 2,
  },
  cast = {
    vdsl.cast {
      subject  = "warrior",
      negative = "ugly",
      lora     = { { name = "detail.safetensors", weight = 0.6 } },
    },
  },
  stage = vdsl.stage {
    controlnet = { { type = "depth_model.pth", image = "depth.png", strength = 0.7 } },
  },
  seed  = 42,
  steps = 30,
}

local types2 = {}
for _, node in pairs(r2.prompt) do
  types2[node.class_type] = (types2[node.class_type] or 0) + 1
end
T.ok("full: VAELoader",        types2["VAELoader"] == 1)
T.ok("full: CLIPSetLastLayer",  types2["CLIPSetLastLayer"] == 1)
T.ok("full: LoraLoader",       types2["LoraLoader"] == 1)
T.ok("full: ControlNetLoader", types2["ControlNetLoader"] == 1)
T.ok("full: ControlNetApplyAdvanced", types2["ControlNetApplyAdvanced"] == 1)
T.ok("full: CLIPEncode x2",    types2["CLIPTextEncode"] == 2)
T.ok("full: LoadImage",        types2["LoadImage"] == 1)

-- ============================================================
-- Validation errors
-- ============================================================
T.err("render: no world", function()
  vdsl.render { cast = { vdsl.cast { subject = "x" } } }
end)

T.err("render: no cast", function()
  vdsl.render { world = vdsl.world { model = "m" } }
end)

T.err("render: empty cast", function()
  vdsl.render { world = vdsl.world { model = "m" }, cast = {} }
end)

-- ============================================================
-- Multiple Casts (ConditioningCombine)
-- ============================================================
local r_multi = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast = {
    vdsl.cast { subject = "warrior woman", negative = "ugly" },
    vdsl.cast { subject = "dragon", negative = "blurry" },
    vdsl.cast { subject = "castle background", negative = "low quality" },
  },
  seed = 42,
}

local multi_types = {}
for _, node in pairs(r_multi.prompt) do
  multi_types[node.class_type] = (multi_types[node.class_type] or 0) + 1
end

-- 3 casts = 6 CLIPTextEncode (3 positive + 3 negative)
T.eq("multi: CLIPEncode x6", multi_types["CLIPTextEncode"], 6)
-- 3 casts combined pairwise = 2 ConditioningCombine for positive + 2 for negative
T.eq("multi: CondCombine x4", multi_types["ConditioningCombine"], 4)
-- Still 1 KSampler
T.eq("multi: KSampler x1", multi_types["KSampler"], 1)

-- Verify all prompts appear in the graph
local multi_texts = {}
for _, node in pairs(r_multi.prompt) do
  if node.class_type == "CLIPTextEncode" then
    multi_texts[#multi_texts + 1] = node.inputs.text
  end
end
local function has_text(texts, search)
  for _, t in ipairs(texts) do
    if t:find(search, 1, true) then return true end
  end
  return false
end
T.ok("multi: warrior in graph", has_text(multi_texts, "warrior woman"))
T.ok("multi: dragon in graph",  has_text(multi_texts, "dragon"))
T.ok("multi: castle in graph",  has_text(multi_texts, "castle"))

-- Single cast still works (no ConditioningCombine added)
local r_single = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast = { vdsl.cast { subject = "solo cat" } },
  seed = 1,
}
local single_types = {}
for _, node in pairs(r_single.prompt) do
  single_types[node.class_type] = (single_types[node.class_type] or 0) + 1
end
T.eq("single: no CondCombine", single_types["ConditioningCombine"], nil)

-- ============================================================
-- Post: hires fix (latent phase)
-- ============================================================
local r_hires = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "landscape" } },
  post  = vdsl.post("hires", { scale = 1.5, steps = 10, denoise = 0.4 }),
  seed  = 42,
  steps = 20,
}

local hires_types = {}
for _, node in pairs(r_hires.prompt) do
  hires_types[node.class_type] = (hires_types[node.class_type] or 0) + 1
end
-- hires = LatentUpscaleBy + 2nd KSampler
T.eq("hires: LatentUpscaleBy",  hires_types["LatentUpscaleBy"], 1)
T.eq("hires: KSampler x2",     hires_types["KSampler"], 2)
T.eq("hires: VAEDecode x1",    hires_types["VAEDecode"], 1)

-- Verify 2nd KSampler has correct denoise
local ksampler_count = 0
for _, node in pairs(r_hires.prompt) do
  if node.class_type == "KSampler" then
    ksampler_count = ksampler_count + 1
    if node.inputs.denoise == 0.4 then
      T.eq("hires: 2nd pass steps", node.inputs.steps, 10)
      T.eq("hires: 2nd pass seed",  node.inputs.seed,  43)  -- seed + 1
    end
  end
end
T.eq("hires: total KSamplers", ksampler_count, 2)

-- ============================================================
-- Post: pixel upscale
-- ============================================================
local r_upscale = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "portrait" } },
  post  = vdsl.post("upscale", { model = "4x-UltraSharp.pth" }),
  seed  = 42,
}

local up_types = {}
for _, node in pairs(r_upscale.prompt) do
  up_types[node.class_type] = (up_types[node.class_type] or 0) + 1
end
T.eq("upscale: ModelLoader",       up_types["UpscaleModelLoader"], 1)
T.eq("upscale: ImageUpscale",      up_types["ImageUpscaleWithModel"], 1)
T.eq("upscale: KSampler x1",       up_types["KSampler"], 1)

-- ============================================================
-- Post: chain (hires + upscale)
-- ============================================================
local r_chain = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "hero" } },
  post  = vdsl.post("hires", { scale = 1.5, denoise = 0.3 })
        + vdsl.post("upscale", { model = "4x-UltraSharp.pth" }),
  seed  = 42,
}

local chain_types = {}
for _, node in pairs(r_chain.prompt) do
  chain_types[node.class_type] = (chain_types[node.class_type] or 0) + 1
end
-- hires (latent) then upscale (pixel) - auto sorted by compiler
T.eq("chain: LatentUpscaleBy",      chain_types["LatentUpscaleBy"], 1)
T.eq("chain: KSampler x2",          chain_types["KSampler"], 2)
T.eq("chain: UpscaleModelLoader",   chain_types["UpscaleModelLoader"], 1)
T.eq("chain: ImageUpscale",         chain_types["ImageUpscaleWithModel"], 1)

-- ============================================================
-- Post entity composability
-- ============================================================
local Entity = require("vdsl.entity")
local p1 = vdsl.post("hires", { scale = 1.5 })
T.ok("post: is post",        Entity.is(p1, "post"))
T.eq("post: ops count",      #p1:ops(), 1)
T.eq("post: op type",        p1:ops()[1].type, "hires")

local p2 = p1 + vdsl.post("upscale", { model = "x.pth" })
T.eq("post: chain count",    #p2:ops(), 2)
T.eq("post: chain[1]",       p2:ops()[1].type, "hires")
T.eq("post: chain[2]",       p2:ops()[2].type, "upscale")

local p3 = p1:then_do("upscale", { model = "y.pth" })
T.eq("post: then_do count",  #p3:ops(), 2)

T.err("post: empty type", function() vdsl.post("") end)

-- ============================================================
-- Post: refine (latent, 2nd pass without upscale)
-- ============================================================
local r_refine = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "portrait" } },
  post  = vdsl.post("refine", { steps = 8, denoise = 0.25, sampler = "dpmpp_2m" }),
  seed  = 42,
}

local refine_types = {}
for _, node in pairs(r_refine.prompt) do
  refine_types[node.class_type] = (refine_types[node.class_type] or 0) + 1
end
T.eq("refine: KSampler x2",       refine_types["KSampler"], 2)
T.eq("refine: no LatentUpscale",   refine_types["LatentUpscaleBy"], nil)

-- Verify refine KSampler params
for _, node in pairs(r_refine.prompt) do
  if node.class_type == "KSampler" and node.inputs.denoise == 0.25 then
    T.eq("refine: sampler",  node.inputs.sampler_name, "dpmpp_2m")
    T.eq("refine: steps",    node.inputs.steps, 8)
    T.eq("refine: seed",     node.inputs.seed, 43)
  end
end

-- ============================================================
-- Post: face restoration (pixel)
-- ============================================================
local r_face = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "portrait woman" } },
  post  = vdsl.post("face", { model = "codeformer-v0.1.0.pth", fidelity = 0.7 }),
  seed  = 42,
}

local face_types = {}
for _, node in pairs(r_face.prompt) do
  face_types[node.class_type] = (face_types[node.class_type] or 0) + 1
end
T.eq("face: RestoreLoader",  face_types["FaceRestoreModelLoader"], 1)
T.eq("face: RestoreModel",   face_types["FaceRestoreWithModel"], 1)

for _, node in pairs(r_face.prompt) do
  if node.class_type == "FaceRestoreWithModel" then
    T.eq("face: fidelity", node.inputs.fidelity, 0.7)
  end
end

-- ============================================================
-- Post: color correction (pixel)
-- ============================================================
local r_color = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "sunset" } },
  post  = vdsl.post("color", {
    brightness = 1.1, contrast = 1.2, saturation = 0.9, gamma = 0.95,
  }),
  seed  = 42,
}

local color_types = {}
for _, node in pairs(r_color.prompt) do
  color_types[node.class_type] = (color_types[node.class_type] or 0) + 1
end
T.eq("color: ColorCorrect", color_types["ColorCorrect"], 1)

for _, node in pairs(r_color.prompt) do
  if node.class_type == "ColorCorrect" then
    -- VDSL multiplier → EllangoK offset: (mul - 1.0) * 100
    -- 1.1 → 10, 1.2 → 20, 0.9 → -10, gamma is direct
    T.eq("color: brightness", node.inputs.brightness, 10.0)
    T.eq("color: contrast",   node.inputs.contrast, 20.0)
    T.eq("color: saturation", node.inputs.saturation, -10.0)
    T.eq("color: gamma",      node.inputs.gamma, 0.95)
    T.eq("color: temperature", node.inputs.temperature, 0)
    T.eq("color: hue",         node.inputs.hue, 0)
  end
end

-- ============================================================
-- Post: sharpen (pixel)
-- ============================================================
local r_sharp = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "detail shot" } },
  post  = vdsl.post("sharpen", { radius = 2, sigma = 1.5, alpha = 0.8 }),
  seed  = 42,
}

local sharp_types = {}
for _, node in pairs(r_sharp.prompt) do
  sharp_types[node.class_type] = (sharp_types[node.class_type] or 0) + 1
end
T.eq("sharpen: ImageSharpen", sharp_types["ImageSharpen"], 1)

for _, node in pairs(r_sharp.prompt) do
  if node.class_type == "ImageSharpen" then
    T.eq("sharpen: radius", node.inputs.sharpen_radius, 2)
    T.eq("sharpen: sigma",  node.inputs.sigma, 1.5)
    T.eq("sharpen: alpha",  node.inputs.alpha, 0.8)
  end
end

-- ============================================================
-- Post: resize by scale (pixel)
-- ============================================================
local r_resize_s = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "thumb" } },
  post  = vdsl.post("resize", { scale = 0.5, method = "bilinear" }),
  seed  = 42,
}

local resize_s_types = {}
for _, node in pairs(r_resize_s.prompt) do
  resize_s_types[node.class_type] = (resize_s_types[node.class_type] or 0) + 1
end
T.eq("resize scale: ImageScaleBy", resize_s_types["ImageScaleBy"], 1)

for _, node in pairs(r_resize_s.prompt) do
  if node.class_type == "ImageScaleBy" then
    T.eq("resize scale: factor", node.inputs.scale_by, 0.5)
    T.eq("resize scale: method", node.inputs.upscale_method, "bilinear")
  end
end

-- ============================================================
-- Post: resize by dimensions (pixel)
-- ============================================================
local r_resize_d = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "wallpaper" } },
  post  = vdsl.post("resize", { width = 1920, height = 1080 }),
  seed  = 42,
}

local resize_d_types = {}
for _, node in pairs(r_resize_d.prompt) do
  resize_d_types[node.class_type] = (resize_d_types[node.class_type] or 0) + 1
end
T.eq("resize dims: ImageScale", resize_d_types["ImageScale"], 1)

for _, node in pairs(r_resize_d.prompt) do
  if node.class_type == "ImageScale" then
    T.eq("resize dims: width",  node.inputs.width, 1920)
    T.eq("resize dims: height", node.inputs.height, 1080)
  end
end

-- ============================================================
-- Post: full pipeline chain (latent + pixel mixed)
-- ============================================================
local r_full_post = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "detailed portrait" } },
  post  = vdsl.post("hires", { scale = 1.5, denoise = 0.4 })
        + vdsl.post("upscale", { model = "4x-UltraSharp.pth" })
        + vdsl.post("face", { fidelity = 0.6 })
        + vdsl.post("color", { contrast = 1.1 })
        + vdsl.post("sharpen", { radius = 1 }),
  seed  = 42,
}

local full_post_types = {}
for _, node in pairs(r_full_post.prompt) do
  full_post_types[node.class_type] = (full_post_types[node.class_type] or 0) + 1
end
T.eq("full post: KSampler x2",       full_post_types["KSampler"], 2)
T.eq("full post: LatentUpscaleBy",    full_post_types["LatentUpscaleBy"], 1)
T.eq("full post: UpscaleModel",       full_post_types["UpscaleModelLoader"], 1)
T.eq("full post: ImageUpscale",       full_post_types["ImageUpscaleWithModel"], 1)
T.eq("full post: FaceRestore",        full_post_types["FaceRestoreWithModel"], 1)
T.eq("full post: ColorCorrect",       full_post_types["ColorCorrect"], 1)
T.eq("full post: ImageSharpen",       full_post_types["ImageSharpen"], 1)
T.eq("full post: VAEDecode x1",       full_post_types["VAEDecode"], 1)

-- ============================================================
-- Catalog: validation
-- ============================================================
local cat_ok = vdsl.catalog {
  portrait = vdsl.trait("portrait, face closeup"),
  anime    = vdsl.trait("anime style"),
}
T.ok("catalog: returns table",    type(cat_ok) == "table")
T.ok("catalog: portrait is trait", Entity.is(cat_ok.portrait, "trait"))
T.eq("catalog: portrait text",    cat_ok.portrait.text, "portrait, face closeup")

T.err("catalog: non-trait value", function()
  vdsl.catalog { bad = "just a string" }
end)

T.err("catalog: non-string key", function()
  vdsl.catalog { [1] = vdsl.trait("x") }
end)

T.err("catalog: not a table", function()
  vdsl.catalog("oops")
end)

-- ============================================================
-- Trait:hint() basics
-- ============================================================
local t_face = vdsl.trait("portrait"):hint("face", { fidelity = 0.7 })
T.ok("hint: is trait",        Entity.is(t_face, "trait"))
T.eq("hint: text preserved",  t_face.text, "portrait")
T.ok("hint: has hints",       t_face:hints() ~= nil)
T.eq("hint: face fidelity",   t_face:hints().face.fidelity, 0.7)

-- Immutability: original unchanged
local t_orig = vdsl.trait("base")
local t_hinted = t_orig:hint("hires", { scale = 1.5 })
T.eq("hint: orig no hints",   t_orig:hints(), nil)
T.ok("hint: new has hints",   t_hinted:hints() ~= nil)

-- Multiple hints on one trait
local t_multi = vdsl.trait("photo"):hint("face", {}):hint("sharpen", { radius = 2 })
T.ok("hint: multi face",      t_multi:hints().face ~= nil)
T.ok("hint: multi sharpen",   t_multi:hints().sharpen ~= nil)
T.eq("hint: multi sharpen r", t_multi:hints().sharpen.radius, 2)

-- Hints merge via +
local t_a = vdsl.trait("left"):hint("face", { fidelity = 0.5 })
local t_b = vdsl.trait("right"):hint("hires", { scale = 2.0 })
local t_ab = t_a + t_b
T.ok("hint+: face",    t_ab:hints().face ~= nil)
T.ok("hint+: hires",   t_ab:hints().hires ~= nil)
T.eq("hint+: scale",   t_ab:hints().hires.scale, 2.0)

-- Right side wins on conflict
local t_c = vdsl.trait("a"):hint("face", { fidelity = 0.3 })
local t_d = vdsl.trait("b"):hint("face", { fidelity = 0.9 })
local t_cd = t_c + t_d
T.eq("hint+: right wins", t_cd:hints().face.fidelity, 0.9)

T.err("hint: empty op", function() vdsl.trait("x"):hint("") end)

-- ============================================================
-- Subject:hints() collection
-- ============================================================
local subj_h = vdsl.subject("warrior")
  :with(vdsl.trait("portrait"):hint("face", { fidelity = 0.6 }))
  :with(vdsl.trait("anime"):hint("hires", { scale = 1.5 }))
local sh = subj_h:hints()
T.ok("subj hints: not nil",   sh ~= nil)
T.ok("subj hints: face",      sh.face ~= nil)
T.eq("subj hints: fidelity",  sh.face.fidelity, 0.6)
T.ok("subj hints: hires",     sh.hires ~= nil)
T.eq("subj hints: scale",     sh.hires.scale, 1.5)

-- Subject without hints
local subj_no = vdsl.subject("plain cat")
T.eq("subj hints: nil", subj_no:hints(), nil)

-- ============================================================
-- Catalog + hints: full integration
-- ============================================================
local my_catalog = vdsl.catalog {
  portrait = vdsl.trait("portrait, face closeup"):hint("face", { fidelity = 0.7 }),
  anime_hq = vdsl.trait("anime style"):hint("hires", { scale = 1.5, denoise = 0.4 }),
}

local cat_subj = vdsl.subject("warrior woman")
  :with(my_catalog.portrait)
  :with(my_catalog.anime_hq)

local cat_hints = cat_subj:hints()
T.ok("cat+hint: face",       cat_hints.face ~= nil)
T.eq("cat+hint: fidelity",   cat_hints.face.fidelity, 0.7)
T.ok("cat+hint: hires",      cat_hints.hires ~= nil)
T.eq("cat+hint: hires scale", cat_hints.hires.scale, 1.5)

-- ============================================================
-- Auto-post from hints (no explicit post)
-- ============================================================
local r_auto = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = cat_subj } },
  seed  = 42,
}

local auto_types = {}
for _, node in pairs(r_auto.prompt) do
  auto_types[node.class_type] = (auto_types[node.class_type] or 0) + 1
end
-- hires hint → LatentUpscaleBy + 2nd KSampler
T.eq("auto: KSampler x2",        auto_types["KSampler"], 2)
T.eq("auto: LatentUpscaleBy",    auto_types["LatentUpscaleBy"], 1)
-- face hint → FaceRestoreModelLoader + FaceRestoreWithModel
T.eq("auto: FaceRestoreLoader",  auto_types["FaceRestoreModelLoader"], 1)
T.eq("auto: FaceRestore",        auto_types["FaceRestoreWithModel"], 1)
-- Only 1 VAEDecode
T.eq("auto: VAEDecode x1",       auto_types["VAEDecode"], 1)

-- Verify face params from hint
for _, node in pairs(r_auto.prompt) do
  if node.class_type == "FaceRestoreWithModel" then
    T.eq("auto: face fidelity", node.inputs.fidelity, 0.7)
  end
end

-- Verify hires params from hint
for _, node in pairs(r_auto.prompt) do
  if node.class_type == "KSampler" and node.inputs.denoise == 0.4 then
    T.ok("auto: hires pass found", true)
  end
end

-- ============================================================
-- Explicit post overrides hints
-- ============================================================
local r_override = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = cat_subj } },
  post  = vdsl.post("sharpen", { radius = 3 }),
  seed  = 42,
}

local override_types = {}
for _, node in pairs(r_override.prompt) do
  override_types[node.class_type] = (override_types[node.class_type] or 0) + 1
end
-- Explicit post: only sharpen, no face/hires from hints
T.eq("override: ImageSharpen",      override_types["ImageSharpen"], 1)
T.eq("override: no FaceRestore",    override_types["FaceRestoreWithModel"], nil)
T.eq("override: no LatentUpscale",  override_types["LatentUpscaleBy"], nil)
T.eq("override: KSampler x1",       override_types["KSampler"], 1)

-- ============================================================
-- auto_post=false disables hint-based post
-- ============================================================
local r_no_auto = vdsl.render {
  world     = vdsl.world { model = "model.safetensors" },
  cast      = { vdsl.cast { subject = cat_subj } },
  auto_post = false,
  seed      = 42,
}

local no_auto_types = {}
for _, node in pairs(r_no_auto.prompt) do
  no_auto_types[node.class_type] = (no_auto_types[node.class_type] or 0) + 1
end
T.eq("no auto: KSampler x1",        no_auto_types["KSampler"], 1)
T.eq("no auto: no FaceRestore",     no_auto_types["FaceRestoreWithModel"], nil)
T.eq("no auto: no LatentUpscale",   no_auto_types["LatentUpscaleBy"], nil)

-- ============================================================
-- Auto-post ordering: latent ops before pixel ops
-- ============================================================
local cat_full = vdsl.catalog {
  face_fix  = vdsl.trait("face detail"):hint("face", { fidelity = 0.5 }),
  hi_res    = vdsl.trait("high resolution"):hint("hires", { scale = 2.0 }),
  sharp     = vdsl.trait("sharp details"):hint("sharpen", { radius = 1 }),
}

local subj_full = vdsl.subject("test")
  :with(cat_full.sharp)      -- pixel: order 6
  :with(cat_full.face_fix)   -- pixel: order 4
  :with(cat_full.hi_res)     -- latent: order 1

local r_order = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = subj_full } },
  seed  = 42,
}

local order_types = {}
for _, node in pairs(r_order.prompt) do
  order_types[node.class_type] = (order_types[node.class_type] or 0) + 1
end
-- All three ops present regardless of insertion order
T.eq("order: LatentUpscaleBy",     order_types["LatentUpscaleBy"], 1)
T.eq("order: KSampler x2",        order_types["KSampler"], 2)
T.eq("order: FaceRestore",        order_types["FaceRestoreWithModel"], 1)
T.eq("order: ImageSharpen",       order_types["ImageSharpen"], 1)
T.eq("order: VAEDecode x1",       order_types["VAEDecode"], 1)

-- ============================================================
-- No hints, no post = plain pipeline
-- ============================================================
local r_plain = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "plain subject, no hints" } },
  seed  = 42,
}
local plain_types = {}
for _, node in pairs(r_plain.prompt) do
  plain_types[node.class_type] = (plain_types[node.class_type] or 0) + 1
end
T.eq("plain: KSampler x1",    plain_types["KSampler"], 1)
T.eq("plain: no Face",        plain_types["FaceRestoreWithModel"], nil)
T.eq("plain: no Upscale",     plain_types["LatentUpscaleBy"], nil)
T.eq("plain: no Sharpen",     plain_types["ImageSharpen"], nil)

-- ============================================================
-- Cast with Trait subject (Trait auto-coerced to Subject)
-- ============================================================
local mood_trait = vdsl.trait("golden hour, warm light"):hint("color", { gamma = 0.9 })
local cast_from_trait = vdsl.cast { subject = mood_trait }
T.ok("cast+trait: is cast",    Entity.is(cast_from_trait, "cast"))
T.ok("cast+trait: subject ok", Entity.is(cast_from_trait.subject, "subject"))

-- Hints preserved through Trait → Subject coercion
local cft_hints = cast_from_trait.subject:hints()
T.ok("cast+trait: hints preserved", cft_hints ~= nil and cft_hints.color ~= nil)
T.eq("cast+trait: gamma",          cft_hints.color.gamma, 0.9)

-- Mood/lighting as Cast in render
local r_mood_cast = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast  = {
    vdsl.cast { subject = "warrior woman", negative = "ugly" },
    vdsl.cast {
      subject = mood_trait,
      lora = { { name = "ic-light.safetensors", weight = 0.5 } },
    },
  },
  seed = 42,
}

local mood_cast_types = {}
local mood_cast_texts = {}
for _, node in pairs(r_mood_cast.prompt) do
  mood_cast_types[node.class_type] = (mood_cast_types[node.class_type] or 0) + 1
  if node.class_type == "CLIPTextEncode" then
    mood_cast_texts[#mood_cast_texts + 1] = node.inputs.text
  end
end
-- 2 casts: warrior + golden_hour
T.eq("mood cast: CLIPEncode x4", mood_cast_types["CLIPTextEncode"], 4)
-- 2 casts combined = 1 CondCombine for pos + 1 for neg
T.eq("mood cast: CondCombine x2", mood_cast_types["ConditioningCombine"], 2)
-- LoRA from mood cast
T.eq("mood cast: LoraLoader x1", mood_cast_types["LoraLoader"], 1)
-- Auto-post: golden_hour has color hint → ColorCorrect
T.eq("mood cast: ColorCorrect", mood_cast_types["ColorCorrect"], 1)

-- Golden hour text in graph
local function find_text(texts, search)
  for _, t in ipairs(texts) do
    if t:find(search, 1, true) then return true end
  end
  return false
end
T.ok("mood cast: golden hour in graph", find_text(mood_cast_texts, "golden hour"))
T.ok("mood cast: warrior in graph",     find_text(mood_cast_texts, "warrior"))

-- Verify color params from hint
for _, node in pairs(r_mood_cast.prompt) do
  if node.class_type == "ColorCorrect" then
    T.eq("mood cast: gamma", node.inputs.gamma, 0.9)
  end
end

-- ============================================================
-- Global negative via opts.negative (string)
-- ============================================================
local r_global_neg = vdsl.render {
  world    = vdsl.world { model = "model.safetensors" },
  cast     = { vdsl.cast { subject = "cat" } },
  negative = "ugly, blurry, deformed",
  seed     = 42,
}

local gn_types = {}
local gn_texts = {}
for _, node in pairs(r_global_neg.prompt) do
  gn_types[node.class_type] = (gn_types[node.class_type] or 0) + 1
  if node.class_type == "CLIPTextEncode" then
    gn_texts[#gn_texts + 1] = node.inputs.text
  end
end
-- 1 cast positive + 1 cast negative + 1 global negative = 3 CLIPTextEncode
T.eq("global neg: CLIPEncode x3", gn_types["CLIPTextEncode"], 3)
-- Global negative combined with cast negative = 1 ConditioningCombine
T.eq("global neg: CondCombine x1", gn_types["ConditioningCombine"], 1)
T.ok("global neg: text in graph", find_text(gn_texts, "ugly, blurry, deformed"))

-- ============================================================
-- Global negative via opts.negative (Trait)
-- ============================================================
local r_global_neg_trait = vdsl.render {
  world    = vdsl.world { model = "model.safetensors" },
  cast     = { vdsl.cast { subject = "cat" } },
  negative = vdsl.trait("bad quality, ugly"),
  seed     = 42,
}

local gnt_texts = {}
for _, node in pairs(r_global_neg_trait.prompt) do
  if node.class_type == "CLIPTextEncode" then
    gnt_texts[#gnt_texts + 1] = node.inputs.text
  end
end
T.ok("global neg trait: text in graph", find_text(gnt_texts, "bad quality, ugly"))

-- ============================================================
-- No negative = no global negative (clean pipeline)
-- ============================================================
local r_no_neg = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "cat" } },
  seed  = 42,
}
local nn_types = {}
for _, node in pairs(r_no_neg.prompt) do
  nn_types[node.class_type] = (nn_types[node.class_type] or 0) + 1
end
-- Single cast, no global neg = no ConditioningCombine
T.eq("no neg: no CondCombine", nn_types["ConditioningCombine"], nil)

-- ============================================================
-- Default fallback (steps=20, cfg=7.0, 512x512)
-- ============================================================
local r_no_theme = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "test" } },
  seed  = 42,
}

for _, node in pairs(r_no_theme.prompt) do
  if node.class_type == "KSampler" then
    T.eq("fallback: steps", node.inputs.steps, 20)
    T.eq("fallback: cfg",   node.inputs.cfg, 7.0)
  end
  if node.class_type == "EmptyLatentImage" then
    T.eq("fallback: width",  node.inputs.width, 512)
    T.eq("fallback: height", node.inputs.height, 512)
  end
end

-- ============================================================
-- Post: FaceDetailer with string prompt (baseline)
-- ============================================================
local r_fd_str = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "1girl, red eyes", negative = "ugly" } },
  post  = vdsl.post("facedetail", {
    detector = "face",
    prompt   = "red eyes, detailed iris",
    negative = "blurry eyes",
  }),
  seed = 42,
}

local fd_str_types = {}
local fd_str_texts = {}
for _, node in pairs(r_fd_str.prompt) do
  fd_str_types[node.class_type] = (fd_str_types[node.class_type] or 0) + 1
  if node.class_type == "CLIPTextEncode" then
    fd_str_texts[#fd_str_texts + 1] = node.inputs.text
  end
end
T.eq("fd str: FaceDetailer x1",           fd_str_types["FaceDetailer"], 1)
T.eq("fd str: UltralyticsDetector x1",    fd_str_types["UltralyticsDetectorProvider"], 1)
-- main pos + main neg + fd prompt + fd negative = 4
T.eq("fd str: CLIPTextEncode x4",         fd_str_types["CLIPTextEncode"], 4)
T.ok("fd str: prompt text in graph",      find_text(fd_str_texts, "red eyes, detailed iris"))
T.ok("fd str: negative text in graph",    find_text(fd_str_texts, "blurry eyes"))

-- ============================================================
-- Post: FaceDetailer with Trait prompt
-- ============================================================
local fd_trait_prompt = vdsl.trait("red eyes, slit pupils")
  + vdsl.trait("demon horns, pointed ears")
local fd_trait_neg = vdsl.trait("round pupil, no horns")

local r_fd_trait = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "1girl", negative = "ugly" } },
  post  = vdsl.post("facedetail", {
    detector = "face",
    prompt   = fd_trait_prompt,
    negative = fd_trait_neg,
  }),
  seed = 42,
}

local fd_trait_types = {}
local fd_trait_texts = {}
for _, node in pairs(r_fd_trait.prompt) do
  fd_trait_types[node.class_type] = (fd_trait_types[node.class_type] or 0) + 1
  if node.class_type == "CLIPTextEncode" then
    fd_trait_texts[#fd_trait_texts + 1] = node.inputs.text
  end
end
T.eq("fd trait: FaceDetailer x1",         fd_trait_types["FaceDetailer"], 1)
T.eq("fd trait: CLIPTextEncode x4",       fd_trait_types["CLIPTextEncode"], 4)
T.ok("fd trait: prompt resolved",         find_text(fd_trait_texts, "red eyes, slit pupils"))
T.ok("fd trait: prompt has horns",        find_text(fd_trait_texts, "demon horns"))
T.ok("fd trait: negative resolved",       find_text(fd_trait_texts, "round pupil"))

-- ============================================================
-- Post: FaceDetailer with Subject prompt (partial Subject as subquery)
-- ============================================================
local fd_sub = vdsl.subject("1girl")
  :with(vdsl.trait("red eyes, glowing eyes"))
  :with(vdsl.trait("pale skin, black hair"))

local r_fd_sub = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "1girl, warrior", negative = "ugly" } },
  post  = vdsl.post("facedetail", {
    detector = "face",
    prompt   = fd_sub,
    negative = vdsl.trait("normal eyes"),
  }),
  seed = 42,
}

local fd_sub_texts = {}
for _, node in pairs(r_fd_sub.prompt) do
  if node.class_type == "CLIPTextEncode" then
    fd_sub_texts[#fd_sub_texts + 1] = node.inputs.text
  end
end
T.ok("fd subject: prompt has base",       find_text(fd_sub_texts, "1girl"))
T.ok("fd subject: prompt has eyes",       find_text(fd_sub_texts, "red eyes"))
T.ok("fd subject: prompt has skin",       find_text(fd_sub_texts, "pale skin"))
T.ok("fd subject: negative resolved",     find_text(fd_sub_texts, "normal eyes"))

-- ============================================================
-- Post: FaceDetailer with Trait + Trait composition
-- ============================================================
local char_face = vdsl.trait("red eyes, slit pupils, demon horns")
local scene_wet = vdsl.trait("wet eyelashes, rain on face")

local r_fd_compose = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "1girl", negative = "ugly" } },
  post  = vdsl.post("facedetail", {
    detector = "face",
    prompt   = char_face + scene_wet,
  }),
  seed = 42,
}

local fd_compose_texts = {}
for _, node in pairs(r_fd_compose.prompt) do
  if node.class_type == "CLIPTextEncode" then
    fd_compose_texts[#fd_compose_texts + 1] = node.inputs.text
  end
end
T.ok("fd compose: has char traits",       find_text(fd_compose_texts, "demon horns"))
T.ok("fd compose: has scene traits",      find_text(fd_compose_texts, "wet eyelashes"))

-- ============================================================
-- Post: FaceDetailer with no prompt override (uses main conditioning)
-- ============================================================
local r_fd_noprompt = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "1girl, warrior", negative = "ugly" } },
  post  = vdsl.post("facedetail", { detector = "face", denoise = 0.4 }),
  seed  = 42,
}

local fd_noprompt_types = {}
for _, node in pairs(r_fd_noprompt.prompt) do
  fd_noprompt_types[node.class_type] = (fd_noprompt_types[node.class_type] or 0) + 1
end
T.eq("fd noprompt: FaceDetailer x1",      fd_noprompt_types["FaceDetailer"], 1)
-- main pos + main neg only (no extra CLIPTextEncode for fd prompt)
T.eq("fd noprompt: CLIPTextEncode x2",    fd_noprompt_types["CLIPTextEncode"], 2)

-- ============================================================
-- Post: FaceDetailer person detector (segm model)
-- ============================================================
local r_fd_person = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "1girl", negative = "ugly" } },
  post  = vdsl.post("facedetail", {
    detector = "person",
    prompt   = vdsl.trait("tattoo on neck, pale skin"),
    negative = vdsl.trait("clean neck"),
  }),
  seed = 42,
}

local fd_person_texts = {}
local fd_person_detector = nil
for _, node in pairs(r_fd_person.prompt) do
  if node.class_type == "CLIPTextEncode" then
    fd_person_texts[#fd_person_texts + 1] = node.inputs.text
  end
  if node.class_type == "UltralyticsDetectorProvider" then
    fd_person_detector = node.inputs.model_name
  end
end
T.ok("fd person: prompt resolved",        find_text(fd_person_texts, "tattoo on neck"))
T.ok("fd person: negative resolved",      find_text(fd_person_texts, "clean neck"))
T.eq("fd person: segm model",             fd_person_detector, "segm/person_yolov8m-seg.pt")

-- ============================================================
-- Post: FaceDetailer chained (person → face, like mazoku_snap)
-- ============================================================
local body_prompt = vdsl.trait("tattoo on neck, intricate markings, pale skin")
local face_prompt = vdsl.trait("red eyes, slit pupils") + vdsl.trait("demon horns, black horns")

local r_fd_chain = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "1girl, demon", negative = "ugly" } },
  post  = vdsl.post("facedetail", {
    detector = "person",
    prompt   = body_prompt,
    negative = vdsl.trait("clean skin"),
  })
  + vdsl.post("facedetail", {
    detector = "face",
    prompt   = face_prompt,
    negative = vdsl.trait("round pupil"),
  }),
  seed = 42,
}

local fd_chain_types = {}
local fd_chain_texts = {}
for _, node in pairs(r_fd_chain.prompt) do
  fd_chain_types[node.class_type] = (fd_chain_types[node.class_type] or 0) + 1
  if node.class_type == "CLIPTextEncode" then
    fd_chain_texts[#fd_chain_texts + 1] = node.inputs.text
  end
end
T.eq("fd chain: FaceDetailer x2",         fd_chain_types["FaceDetailer"], 2)
T.eq("fd chain: UltralyticsDetector x2",  fd_chain_types["UltralyticsDetectorProvider"], 2)
-- main pos + main neg + person prompt + person neg + face prompt + face neg = 6
T.eq("fd chain: CLIPTextEncode x6",       fd_chain_types["CLIPTextEncode"], 6)
T.ok("fd chain: body prompt",             find_text(fd_chain_texts, "tattoo on neck"))
T.ok("fd chain: face prompt",             find_text(fd_chain_texts, "red eyes"))
T.ok("fd chain: face negative",           find_text(fd_chain_texts, "round pupil"))

-- ============================================================
-- hint("lora") — World resolver integration
-- ============================================================

-- Dict-form world with named LoRA pool
local r_hint_lora = vdsl.render {
  world = vdsl.world {
    model = "model.safetensors",
    lora = {
      style  = { name = "style_v1.safetensors", weight = 0.8 },
      detail = { name = "add_detail.safetensors", weight = 0.6 },
    },
  },
  cast = {
    vdsl.cast {
      subject = vdsl.subject("1girl"):with(
        vdsl.trait("detailed eyes"):hint("lora", "detail")
      ),
    },
  },
  seed = 42,
}

local hint_lora_types = {}
local hint_lora_names = {}
for _, node in pairs(r_hint_lora.prompt) do
  hint_lora_types[node.class_type] = (hint_lora_types[node.class_type] or 0) + 1
  if node.class_type == "LoraLoader" then
    hint_lora_names[#hint_lora_names + 1] = node.inputs.lora_name
  end
end
-- World has 2 LoRAs in pool, but only "detail" is hinted + both world-level applied
T.eq("hint lora: LoraLoader x2", hint_lora_types["LoraLoader"], 2)
T.ok("hint lora: style loaded (world-level)", find_text(hint_lora_names, "style_v1.safetensors"))
T.ok("hint lora: detail loaded (hint-resolved)", find_text(hint_lora_names, "add_detail.safetensors"))

-- hint("lora") with full spec in hint (no World resolution needed)
local r_hint_direct = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast = {
    vdsl.cast {
      subject = vdsl.subject("1girl"):with(
        vdsl.trait("torn clothes"):hint("lora", { name = "torn_v1.safetensors", weight = 0.7 })
      ),
    },
  },
  seed = 42,
}

local hint_direct_types = {}
local hint_direct_lora = nil
for _, node in pairs(r_hint_direct.prompt) do
  hint_direct_types[node.class_type] = (hint_direct_types[node.class_type] or 0) + 1
  if node.class_type == "LoraLoader" then
    hint_direct_lora = node.inputs
  end
end
T.eq("hint direct: LoraLoader x1", hint_direct_types["LoraLoader"], 1)
T.eq("hint direct: lora_name",     hint_direct_lora.lora_name, "torn_v1.safetensors")
T.eq("hint direct: strength",      hint_direct_lora.strength_model, 0.7)

-- Dedup: hint("lora") same as world-level → no double load
local r_hint_dedup = vdsl.render {
  world = vdsl.world {
    model = "model.safetensors",
    lora = {
      style = { name = "style_v1.safetensors", weight = 0.8 },
    },
  },
  cast = {
    vdsl.cast {
      subject = vdsl.subject("1girl"):with(
        vdsl.trait("anime style"):hint("lora", "style")
      ),
    },
  },
  seed = 42,
}

local dedup_lora_count = 0
for _, node in pairs(r_hint_dedup.prompt) do
  if node.class_type == "LoraLoader" then
    dedup_lora_count = dedup_lora_count + 1
  end
end
-- "style" already loaded at world-level → hint should NOT double-load
T.eq("hint dedup: LoraLoader x1", dedup_lora_count, 1)

-- Cast.lora full spec (escape hatch, backward compat)
local r_cast_lora = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast = {
    vdsl.cast {
      subject = "1girl",
      lora = { { name = "explicit.safetensors", weight = 0.9 } },
    },
  },
  seed = 42,
}

local cast_lora_types = {}
local cast_lora_node = nil
for _, node in pairs(r_cast_lora.prompt) do
  cast_lora_types[node.class_type] = (cast_lora_types[node.class_type] or 0) + 1
  if node.class_type == "LoraLoader" then
    cast_lora_node = node.inputs
  end
end
T.eq("cast lora: LoraLoader x1",  cast_lora_types["LoraLoader"], 1)
T.eq("cast lora: name",           cast_lora_node.lora_name, "explicit.safetensors")
T.eq("cast lora: weight",         cast_lora_node.strength_model, 0.9)

-- ============================================================
-- JSON structure check
-- ============================================================
T.ok("json: starts {",        r1.json:sub(1, 1) == "{")
T.ok("json: has class_type",  r1.json:find("class_type") ~= nil)
T.ok("json: has KSampler",    r1.json:find("KSampler") ~= nil)

-- ============================================================
-- check(): Trait conflict detection
-- ============================================================
local C = vdsl.catalogs

do -- hair/eyes conflict tests (scoped to avoid local var limit)
-- Conflict detected: purple eyes + purple hair
local conflict_subj = vdsl.subject("1girl")
  :with(C.figure.eyes.purple)
  :with(C.figure.hair.purple)
local conflict_diag = vdsl.check({
  world = vdsl.world { model = "m.safetensors" },
  cast  = { vdsl.cast { subject = conflict_subj } },
})
local has_conflict = false
for _, w in ipairs(conflict_diag.warnings) do
  if w:find("conflict") then has_conflict = true; break end
end
T.ok("conflict: purple eyes + purple hair detected", has_conflict)

-- Both directions: hair.purple conflicts with purple eyes, AND eyes.purple conflicts with purple hair
local conflict_count = 0
for _, w in ipairs(conflict_diag.warnings) do
  if w:find("conflict") then conflict_count = conflict_count + 1 end
end
T.ok("conflict: bidirectional (both sides report)", conflict_count >= 2)

-- No conflict: blue eyes + brown hair (no matching conflicts tag)
local safe_subj = vdsl.subject("1girl")
  :with(C.figure.eyes.blue)
  :with(C.figure.hair.brown)
local safe_diag = vdsl.check({
  world = vdsl.world { model = "m.safetensors" },
  cast  = { vdsl.cast { subject = safe_subj } },
})
local safe_conflict = false
for _, w in ipairs(safe_diag.warnings) do
  if w:find("conflict") then safe_conflict = true; break end
end
T.ok("conflict: blue eyes + brown hair = no conflict", not safe_conflict)

-- Conflict detected: blue eyes + blonde hair (SDXL bias)
local bias_subj = vdsl.subject("1girl")
  :with(C.figure.eyes.blue)
  :with(C.figure.hair.blonde)
local bias_diag = vdsl.check({
  world = vdsl.world { model = "m.safetensors" },
  cast  = { vdsl.cast { subject = bias_subj } },
})
local has_bias = false
for _, w in ipairs(bias_diag.warnings) do
  if w:find("conflict") and w:find("blonde") then has_bias = true; break end
end
T.ok("conflict: blue eyes + blonde hair detected", has_bias)

-- Conflict detected: red hair + red eyes (color bleeding)
local red_subj = vdsl.subject("1girl")
  :with(C.figure.hair.red)
  :with(C.figure.eyes.red)
local red_diag = vdsl.check({
  world = vdsl.world { model = "m.safetensors" },
  cast  = { vdsl.cast { subject = red_subj } },
})
local has_red = false
for _, w in ipairs(red_diag.warnings) do
  if w:find("conflict") and w:find("red") then has_red = true; break end
end
T.ok("conflict: red hair + red eyes detected", has_red)

-- No conflict: unrelated traits
local unrelated_subj = vdsl.subject("1girl")
  :with(C.figure.hair.black)
  :with(C.figure.eyes.yellow)
  :with(C.figure.body.slim)
local unrelated_diag = vdsl.check({
  world = vdsl.world { model = "m.safetensors" },
  cast  = { vdsl.cast { subject = unrelated_subj } },
})
local unrelated_conflict = false
for _, w in ipairs(unrelated_diag.warnings) do
  if w:find("conflict") then unrelated_conflict = true; break end
end
T.ok("conflict: black hair + yellow eyes + slim = no conflict", not unrelated_conflict)

-- Conflict with custom trait (not from catalog)
local custom_subj = vdsl.subject("1girl")
  :with(C.figure.eyes.purple)
  :with(vdsl.trait("purple hair, long hair"))
local custom_diag = vdsl.check({
  world = vdsl.world { model = "m.safetensors" },
  cast  = { vdsl.cast { subject = custom_subj } },
})
local custom_conflict = false
for _, w in ipairs(custom_diag.warnings) do
  if w:find("conflict") and w:find("purple hair") then custom_conflict = true; break end
end
T.ok("conflict: catalog eyes.purple vs custom 'purple hair' detected", custom_conflict)

-- empty_eyes conflicts with white eyes (from existing tag)
local empty_subj = vdsl.subject("1girl")
  :with(C.figure.eyes.empty)
  :with(vdsl.trait("white eyes"))
local empty_diag = vdsl.check({
  world = vdsl.world { model = "m.safetensors" },
  cast  = { vdsl.cast { subject = empty_subj } },
})
local empty_conflict = false
for _, w in ipairs(empty_diag.warnings) do
  if w:find("conflict") and w:find("white eyes") then empty_conflict = true; break end
end
T.ok("conflict: empty_eyes + 'white eyes' detected", empty_conflict)
end -- hair/eyes conflict tests

do -- catalog conflict tests (scoped to avoid local var limit)
-- === Lighting conflicts ===
local light_subj = vdsl.subject("1girl")
  :with(C.lighting.golden_hour)
  :with(C.lighting.blue_hour)
local light_diag = vdsl.check({
  world = vdsl.world { model = "m.safetensors" },
  cast  = { vdsl.cast { subject = light_subj } },
})
local light_conflict = false
for _, w in ipairs(light_diag.warnings) do
  if w:find("conflict") and w:find("blue hour") then light_conflict = true; break end
end
T.ok("conflict: golden_hour + blue_hour detected", light_conflict)

local hilo_subj = vdsl.subject("1girl")
  :with(C.lighting.high_key)
  :with(C.lighting.low_key)
local hilo_diag = vdsl.check({
  world = vdsl.world { model = "m.safetensors" },
  cast  = { vdsl.cast { subject = hilo_subj } },
})
local hilo_conflict = false
for _, w in ipairs(hilo_diag.warnings) do
  if w:find("conflict") and w:find("key lighting") then hilo_conflict = true; break end
end
T.ok("conflict: high_key + low_key detected", hilo_conflict)

-- === Color palette conflicts ===
local temp_subj = vdsl.subject("1girl")
  :with(C.color.palette.warm_tones)
  :with(C.color.palette.cool_tones)
local temp_diag = vdsl.check({
  world = vdsl.world { model = "m.safetensors" },
  cast  = { vdsl.cast { subject = temp_subj } },
})
local temp_conflict = false
for _, w in ipairs(temp_diag.warnings) do
  if w:find("conflict") and w:find("tones") then temp_conflict = true; break end
end
T.ok("conflict: warm_tones + cool_tones detected", temp_conflict)

local sat_subj = vdsl.subject("1girl")
  :with(C.color.palette.vibrant)
  :with(C.color.palette.desaturated)
local sat_diag = vdsl.check({
  world = vdsl.world { model = "m.safetensors" },
  cast  = { vdsl.cast { subject = sat_subj } },
})
local sat_conflict = false
for _, w in ipairs(sat_diag.warnings) do
  if w:find("conflict") and w:find("vibrant") then sat_conflict = true; break end
end
T.ok("conflict: vibrant + desaturated detected", sat_conflict)

-- === Style conflicts ===
local style_subj = vdsl.subject("1girl")
  :with(C.style.anime)
  :with(C.style.photo)
local style_diag = vdsl.check({
  world = vdsl.world { model = "m.safetensors" },
  cast  = { vdsl.cast { subject = style_subj } },
})
local style_conflict = false
for _, w in ipairs(style_diag.warnings) do
  if w:find("conflict") and (w:find("anime") or w:find("photorealistic")) then style_conflict = true; break end
end
T.ok("conflict: anime + photo detected", style_conflict)

-- === Time conflicts ===
local time_subj = vdsl.subject("1girl")
  :with(C.environment.time.night)
  :with(C.environment.time.midday)
local time_diag = vdsl.check({
  world = vdsl.world { model = "m.safetensors" },
  cast  = { vdsl.cast { subject = time_subj } },
})
local time_conflict = false
for _, w in ipairs(time_diag.warnings) do
  if w:find("conflict") and w:find("midday") then time_conflict = true; break end
end
T.ok("conflict: night + midday detected", time_conflict)

-- === Weather conflicts ===
local wx_subj = vdsl.subject("1girl")
  :with(C.environment.weather.clear_sky)
  :with(C.environment.weather.storm)
local wx_diag = vdsl.check({
  world = vdsl.world { model = "m.safetensors" },
  cast  = { vdsl.cast { subject = wx_subj } },
})
local wx_conflict = false
for _, w in ipairs(wx_diag.warnings) do
  if w:find("conflict") and w:find("storm") then wx_conflict = true; break end
end
T.ok("conflict: clear_sky + storm detected", wx_conflict)

-- === Expression conflicts ===
local expr_subj = vdsl.subject("1girl")
  :with(C.figure.expression.smile)
  :with(C.figure.expression.angry)
local expr_diag = vdsl.check({
  world = vdsl.world { model = "m.safetensors" },
  cast  = { vdsl.cast { subject = expr_subj } },
})
local expr_conflict = false
for _, w in ipairs(expr_diag.warnings) do
  if w:find("conflict") and w:find("angry") then expr_conflict = true; break end
end
T.ok("conflict: smile + angry detected (warning, not block)", expr_conflict)

local eye_subj = vdsl.subject("1girl")
  :with(C.figure.expression.closed_eyes)
  :with(C.figure.expression.wide_eyes)
local eye_diag = vdsl.check({
  world = vdsl.world { model = "m.safetensors" },
  cast  = { vdsl.cast { subject = eye_subj } },
})
local eye_conflict = false
for _, w in ipairs(eye_diag.warnings) do
  if w:find("conflict") and w:find("eyes") then eye_conflict = true; break end
end
T.ok("conflict: closed_eyes + wide_eyes detected", eye_conflict)

-- === No false positive: compatible lighting ===
local compat_subj = vdsl.subject("1girl")
  :with(C.lighting.golden_hour)
  :with(C.lighting.rim_light)
local compat_diag = vdsl.check({
  world = vdsl.world { model = "m.safetensors" },
  cast  = { vdsl.cast { subject = compat_subj } },
})
local compat_conflict = false
for _, w in ipairs(compat_diag.warnings) do
  if w:find("conflict") then compat_conflict = true; break end
end
T.ok("no conflict: golden_hour + rim_light compatible", not compat_conflict)

do -- on_conflict strategy tests (scoped to avoid local var limit)
local strat_subj = vdsl.subject("1girl")
  :with(C.figure.expression.smile)
  :with(C.figure.expression.crying)
local strat_neg = vdsl.trait("bad")
local strat_world = vdsl.world { model = "m.safetensors" }

local function extract_pos_prompt(result)
  for _, node in pairs(result.prompt) do
    if node.class_type == "CLIPTextEncode" then
      local t = node.inputs.text
      if t and not t:find("bad") then return t end
    end
  end
  return ""
end

-- warn (default): both traits present, conflicts reported
local r_warn = vdsl.render({
  world = strat_world,
  cast  = { vdsl.cast { subject = strat_subj, negative = strat_neg } },
})
local wp = extract_pos_prompt(r_warn)
T.ok("on_conflict=warn: smile present", wp:find("smile") ~= nil)
T.ok("on_conflict=warn: crying present", wp:find("crying") ~= nil)
T.ok("on_conflict=warn: conflicts returned", #r_warn.conflicts > 0)

-- downweight: later trait emphasis reduced
local r_dw = vdsl.render({
  world = strat_world,
  cast  = { vdsl.cast { subject = strat_subj, negative = strat_neg } },
  on_conflict = "downweight",
})
local dp = extract_pos_prompt(r_dw)
T.ok("on_conflict=downweight: smile present", dp:find("smile") ~= nil)
T.ok("on_conflict=downweight: crying present (reduced)", dp:find("crying") ~= nil)
T.ok("on_conflict=downweight: emphasis reduced (0.9)", dp:find("0.9") ~= nil)
T.ok("on_conflict=downweight: original emphasis gone", not dp:find("1.2"))

-- drop: later trait removed
local r_drop = vdsl.render({
  world = strat_world,
  cast  = { vdsl.cast { subject = strat_subj, negative = strat_neg } },
  on_conflict = "drop",
})
local drp = extract_pos_prompt(r_drop)
T.ok("on_conflict=drop: smile present", drp:find("smile") ~= nil)
T.ok("on_conflict=drop: crying removed", drp:find("crying") == nil)
T.ok("on_conflict=drop: tears removed", drp:find("tears") == nil)

-- ignore: no detection at all
local r_ign = vdsl.render({
  world = strat_world,
  cast  = { vdsl.cast { subject = strat_subj, negative = strat_neg } },
  on_conflict = "ignore",
})
local ip = extract_pos_prompt(r_ign)
T.ok("on_conflict=ignore: smile present", ip:find("smile") ~= nil)
T.ok("on_conflict=ignore: crying present", ip:find("crying") ~= nil)
T.ok("on_conflict=ignore: no conflicts returned", #r_ign.conflicts == 0)

-- check() with strategy shows action info
local chk_dw = vdsl.check({
  world = strat_world,
  cast  = { vdsl.cast { subject = strat_subj } },
  on_conflict = "downweight",
})
local has_action_msg = false
for _, w in ipairs(chk_dw.warnings) do
  if w:find("downweight") and w:find("emphasis") then has_action_msg = true; break end
end
T.ok("check(on_conflict=downweight): action info in warning", has_action_msg)

local chk_drop = vdsl.check({
  world = strat_world,
  cast  = { vdsl.cast { subject = strat_subj } },
  on_conflict = "drop",
})
local has_drop_msg = false
for _, w in ipairs(chk_drop.warnings) do
  if w:find("drop") and w:find("removed") then has_drop_msg = true; break end
end
T.ok("check(on_conflict=drop): action info in warning", has_drop_msg)

-- check() returns structured conflicts
T.ok("check: conflicts field exists", chk_dw.conflicts ~= nil)
T.ok("check: conflicts has entries", #chk_dw.conflicts > 0)
T.ok("check: conflict has source_text", chk_dw.conflicts[1].source_text ~= nil)
T.ok("check: conflict has target_text", chk_dw.conflicts[1].target_text ~= nil)
T.ok("check: conflict has matched", chk_dw.conflicts[1].matched ~= nil)
end -- on_conflict strategy tests

-- === No false positive: compatible style + expression ===
local compat2_subj = vdsl.subject("1girl")
  :with(C.style.anime)
  :with(C.figure.expression.smile)
  :with(C.lighting.soft_studio)
local compat2_diag = vdsl.check({
  world = vdsl.world { model = "m.safetensors" },
  cast  = { vdsl.cast { subject = compat2_subj } },
})
local compat2_conflict = false
for _, w in ipairs(compat2_diag.warnings) do
  if w:find("conflict") then compat2_conflict = true; break end
end
T.ok("no conflict: anime + smile + soft_studio compatible", not compat2_conflict)
end -- catalog conflict tests

T.summary()
