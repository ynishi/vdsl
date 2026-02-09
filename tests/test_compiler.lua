--- test_compiler.lua: Verify DSL compilation and JSON output
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;tests/?.lua;'..package.path" tests/test_compiler.lua

local vdsl = require("vdsl")
local json = require("vdsl.json")
local T    = require("harness")

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
T.ok("full: ControlNetApply",  types2["ControlNetApply"] == 1)
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

T.err("render: bad theme", function()
  vdsl.render {
    world = vdsl.world { model = "m" },
    cast  = { vdsl.cast { subject = "x" } },
    theme = { name = "fake" },  -- plain table, not a Theme entity
  }
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
    T.eq("color: brightness", node.inputs.brightness, 1.1)
    T.eq("color: contrast",   node.inputs.contrast, 1.2)
    T.eq("color: saturation", node.inputs.saturation, 0.9)
    T.eq("color: gamma",      node.inputs.gamma, 0.95)
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
-- Theme: creation and metadata
-- ============================================================
local my_theme = vdsl.theme {
  name     = "test_cinema",
  category = "photography",
  tags     = { "film", "lighting" },
  traits   = {
    golden = vdsl.trait("golden hour"):hint("color", { gamma = 0.9 }),
    noir   = vdsl.trait("film noir"):hint("color", { contrast = 1.3 }),
  },
}
T.ok("theme: is entity",     Entity.is_entity(my_theme))
T.ok("theme: is theme",     Entity.is(my_theme, "theme"))
T.eq("theme: type_of",      Entity.type_of(my_theme), "theme")
T.ok("theme: not trait",    not Entity.is(my_theme, "trait"))
T.eq("theme: name",         my_theme.name, "test_cinema")
T.eq("theme: category",     my_theme.category, "photography")
T.eq("theme: tags[1]",      my_theme.tags[1], "film")
T.ok("theme: golden trait",  Entity.is(my_theme.traits.golden, "trait"))
T.ok("theme: noir trait",    Entity.is(my_theme.traits.noir, "trait"))
T.ok("theme: has_tag film",  my_theme:has_tag("film"))
T.ok("theme: no_tag anime",  not my_theme:has_tag("anime"))

local names = my_theme:trait_names()
T.eq("theme: names[1]",     names[1], "golden")
T.eq("theme: names[2]",     names[2], "noir")

T.err("theme: no name", function()
  vdsl.theme { traits = { x = vdsl.trait("x") } }
end)
T.err("theme: no traits", function()
  vdsl.theme { name = "bad" }
end)
T.err("theme: bad trait value", function()
  vdsl.theme { name = "bad", traits = { x = "not a trait" } }
end)

-- Theme traits work with Subject
local theme_subj = vdsl.subject("warrior"):with(my_theme.traits.golden)
local ts_hints = theme_subj:hints()
T.ok("theme+subj: has color hint", ts_hints ~= nil and ts_hints.color ~= nil)
T.eq("theme+subj: gamma",         ts_hints.color.gamma, 0.9)

-- ============================================================
-- Built-in themes (lazy load)
-- ============================================================
local cinema_theme = vdsl.themes.cinema
T.ok("builtin: cinema loaded",      cinema_theme ~= nil)
T.eq("builtin: cinema name",        cinema_theme.name, "cinema")
T.ok("builtin: cinema golden_hour", Entity.is(cinema_theme.traits.golden_hour, "trait"))
T.ok("builtin: cinema has film",    cinema_theme:has_tag("film"))

local anime_theme = vdsl.themes.anime
T.ok("builtin: anime loaded",       anime_theme ~= nil)
T.eq("builtin: anime name",         anime_theme.name, "anime")
T.ok("builtin: anime cel_shade",    Entity.is(anime_theme.traits.cel_shade, "trait"))

local arch_theme = vdsl.themes.architecture
T.ok("builtin: arch loaded",        arch_theme ~= nil)
T.eq("builtin: arch name",          arch_theme.name, "architecture")
T.ok("builtin: arch exterior",      Entity.is(arch_theme.traits.exterior, "trait"))

-- Non-existent theme returns nil
T.eq("builtin: unknown nil", vdsl.themes.nonexistent, nil)

-- ============================================================
-- Cast with Trait subject (Trait auto-coerced to Subject)
-- ============================================================
local mood_trait = vdsl.themes.cinema.traits.golden_hour
local cast_from_trait = vdsl.cast { subject = mood_trait }
T.ok("cast+trait: is cast",    Entity.is(cast_from_trait, "cast"))
T.ok("cast+trait: subject ok", Entity.is(cast_from_trait.subject, "subject"))

-- Hints preserved through Trait → Subject coercion
local cft_hints = cast_from_trait.subject:hints()
T.ok("cast+trait: hints preserved", cft_hints ~= nil and cft_hints.color ~= nil)
T.eq("cast+trait: gamma",          cft_hints.color.gamma, 0.9)

-- Mood/lighting as Cast in render (replaces Atmosphere)
local r_mood_cast = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast  = {
    vdsl.cast { subject = "warrior woman", negative = "ugly" },
    vdsl.cast {
      subject = vdsl.themes.cinema.traits.golden_hour,
      lora = { vdsl.lora("ic-light.safetensors", 0.5) },
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

-- Verify color params from golden_hour hint
for _, node in pairs(r_mood_cast.prompt) do
  if node.class_type == "ColorCorrect" then
    T.eq("mood cast: gamma", node.inputs.gamma, 0.9)
  end
end

-- ============================================================
-- Theme negatives: creation and validation
-- ============================================================
local neg_theme = vdsl.theme {
  name   = "test_neg",
  traits = { x = vdsl.trait("x style") },
  negatives = {
    default = vdsl.trait("ugly, blurry"),
    quality = vdsl.trait("low quality"),
  },
}
T.ok("theme neg: default is trait", Entity.is(neg_theme.negatives.default, "trait"))
T.eq("theme neg: quality text",    neg_theme.negatives.quality.text, "low quality")

-- Theme with no negatives: defaults to empty table
local no_neg_theme = vdsl.theme {
  name   = "no_neg",
  traits = { y = vdsl.trait("y style") },
}
T.ok("theme no neg: empty table", type(no_neg_theme.negatives) == "table")

-- Built-in themes have negatives
local cinema_neg = vdsl.themes.cinema
T.ok("cinema neg: has default", Entity.is(cinema_neg.negatives.default, "trait"))
T.ok("cinema neg: has quality", Entity.is(cinema_neg.negatives.quality, "trait"))

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
-- Global negative via theme (automatic)
-- ============================================================
local r_theme_neg = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "portrait woman" } },
  theme = vdsl.themes.cinema,
  seed  = 42,
}

local tn_types = {}
local tn_texts = {}
for _, node in pairs(r_theme_neg.prompt) do
  tn_types[node.class_type] = (tn_types[node.class_type] or 0) + 1
  if node.class_type == "CLIPTextEncode" then
    tn_texts[#tn_texts + 1] = node.inputs.text
  end
end
-- Theme negative adds: 1 CLIPTextEncode + 1 ConditioningCombine
T.eq("theme neg: CLIPEncode x3", tn_types["CLIPTextEncode"], 3)
T.eq("theme neg: CondCombine x1", tn_types["ConditioningCombine"], 1)
-- Cinema default negative text appears
T.ok("theme neg: cinema neg in graph", find_text(tn_texts, "cartoon"))

-- ============================================================
-- opts.negative overrides theme negatives
-- ============================================================
local r_neg_override = vdsl.render {
  world    = vdsl.world { model = "model.safetensors" },
  cast     = { vdsl.cast { subject = "cat" } },
  theme    = vdsl.themes.cinema,
  negative = "my custom negative",
  seed     = 42,
}

local no_texts = {}
for _, node in pairs(r_neg_override.prompt) do
  if node.class_type == "CLIPTextEncode" then
    no_texts[#no_texts + 1] = node.inputs.text
  end
end
-- Custom negative appears instead of theme default
T.ok("neg override: custom in graph",    find_text(no_texts, "my custom negative"))
T.ok("neg override: no cinema default",  not find_text(no_texts, "cartoon"))

-- ============================================================
-- No negative, no theme = no global negative (clean pipeline)
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
-- Full pipeline: Theme + mood-as-Cast + hints
-- ============================================================
local full_theme = vdsl.themes.cinema
local full_subj = vdsl.subject("portrait woman")
  :with(full_theme.traits.bokeh)
  :with(vdsl.trait("detailed face"):hint("face", { fidelity = 0.6 }))

local r_full = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  theme = full_theme,
  cast  = {
    vdsl.cast { subject = full_subj },
    vdsl.cast {
      subject = full_theme.traits.golden_hour,
      lora = { vdsl.lora("ic-light.safetensors", 0.5) },
    },
  },
  seed = 42,
}

local full_types = {}
for _, node in pairs(r_full.prompt) do
  full_types[node.class_type] = (full_types[node.class_type] or 0) + 1
end
-- LoRA from mood cast
T.eq("full: LoraLoader x1",     full_types["LoraLoader"], 1)
-- 2 casts + theme neg → ConditioningCombine present
T.ok("full: CondCombine",       full_types["ConditioningCombine"] ~= nil)
-- Face hint from portrait cast
T.eq("full: FaceRestore",       full_types["FaceRestoreWithModel"], 1)
-- Color hint from golden_hour cast
T.eq("full: ColorCorrect",      full_types["ColorCorrect"], 1)

-- Verify color params came from golden_hour theme trait
for _, node in pairs(r_full.prompt) do
  if node.class_type == "ColorCorrect" then
    T.eq("full: gamma from theme", node.inputs.gamma, 0.9)
  end
end

-- ============================================================
-- Theme defaults: render params from theme
-- ============================================================
local r_theme_defaults = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  theme = vdsl.themes.cinema,
  cast  = { vdsl.cast { subject = "test" } },
  seed  = 42,
}

-- Cinema defaults: steps=30, cfg=7.5, sampler=euler, size=1024x1024
for _, node in pairs(r_theme_defaults.prompt) do
  if node.class_type == "KSampler" then
    T.eq("theme defaults: steps",     node.inputs.steps, 30)
    T.eq("theme defaults: cfg",       node.inputs.cfg, 7.5)
    T.eq("theme defaults: sampler",   node.inputs.sampler_name, "euler")
    T.eq("theme defaults: scheduler", node.inputs.scheduler, "normal")
  end
  if node.class_type == "EmptyLatentImage" then
    T.eq("theme defaults: width",  node.inputs.width, 1024)
    T.eq("theme defaults: height", node.inputs.height, 1024)
  end
end

-- Anime theme: size=832x1216, steps=28
local r_anime_defaults = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  theme = vdsl.themes.anime,
  cast  = { vdsl.cast { subject = "test" } },
  seed  = 42,
}

for _, node in pairs(r_anime_defaults.prompt) do
  if node.class_type == "KSampler" then
    T.eq("anime defaults: steps", node.inputs.steps, 28)
    T.eq("anime defaults: cfg",   node.inputs.cfg, 7.0)
  end
  if node.class_type == "EmptyLatentImage" then
    T.eq("anime defaults: width",  node.inputs.width, 832)
    T.eq("anime defaults: height", node.inputs.height, 1216)
  end
end

-- ============================================================
-- Theme defaults: opts override theme
-- ============================================================
local r_override_defaults = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  theme = vdsl.themes.cinema,
  cast  = { vdsl.cast { subject = "test" } },
  seed  = 42,
  steps = 15,
  cfg   = 4.0,
  size  = { 768, 768 },
}

for _, node in pairs(r_override_defaults.prompt) do
  if node.class_type == "KSampler" then
    T.eq("defaults override: steps", node.inputs.steps, 15)
    T.eq("defaults override: cfg",   node.inputs.cfg, 4.0)
  end
  if node.class_type == "EmptyLatentImage" then
    T.eq("defaults override: width",  node.inputs.width, 768)
    T.eq("defaults override: height", node.inputs.height, 768)
  end
end

-- ============================================================
-- No theme: hard-coded fallback (steps=20, cfg=7.0, 512x512)
-- ============================================================
local r_no_theme = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "test" } },
  seed  = 42,
}

for _, node in pairs(r_no_theme.prompt) do
  if node.class_type == "KSampler" then
    T.eq("no theme: steps", node.inputs.steps, 20)
    T.eq("no theme: cfg",   node.inputs.cfg, 7.0)
  end
  if node.class_type == "EmptyLatentImage" then
    T.eq("no theme: width",  node.inputs.width, 512)
    T.eq("no theme: height", node.inputs.height, 512)
  end
end

-- ============================================================
-- JSON structure check
-- ============================================================
T.ok("json: starts {",        r1.json:sub(1, 1) == "{")
T.ok("json: has class_type",  r1.json:find("class_type") ~= nil)
T.ok("json: has KSampler",    r1.json:find("KSampler") ~= nil)

T.summary()
