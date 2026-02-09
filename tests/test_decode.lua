--- test_decode.lua: Verify decode (ComfyUI prompt → vdsl info) and PNG reader
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;tests/?.lua;'..package.path" tests/test_decode.lua

local vdsl   = require("vdsl")
local decode = require("vdsl.decode")
local png    = require("vdsl.png")
local json   = require("vdsl.json")
local T      = require("harness")

-- ============================================================
-- Helper: render then decode (round-trip)
-- ============================================================
local function roundtrip(opts)
  local r = vdsl.render(opts)
  return decode.decode(r.prompt), r
end

-- ============================================================
-- Minimal txt2img round-trip
-- ============================================================
local info1 = roundtrip {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "a cat", negative = "bad" } },
  seed  = 1,
  steps = 10,
  cfg   = 5.0,
  size  = { 512, 512 },
}

T.eq("minimal: world.model",    info1.world.model,      "model.safetensors")
T.eq("minimal: world.clip_skip", info1.world.clip_skip,  1)
T.eq("minimal: world.vae",      info1.world.vae,        nil)
T.eq("minimal: cast count",     #info1.casts,           1)
T.eq("minimal: cast prompt",    info1.casts[1].prompt,  "a cat")
T.eq("minimal: cast negative",  info1.casts[1].negative, "bad")
T.eq("minimal: sampler.seed",   info1.sampler.seed,     1)
T.eq("minimal: sampler.steps",  info1.sampler.steps,    10)
T.eq("minimal: sampler.cfg",    info1.sampler.cfg,      5.0)
T.eq("minimal: sampler.sampler", info1.sampler.sampler,  "euler")
T.eq("minimal: size[1]",        info1.size[1],          512)
T.eq("minimal: size[2]",        info1.size[2],          512)
T.eq("minimal: stage nil",      info1.stage,            nil)
T.eq("minimal: post nil",       info1.post,             nil)
T.eq("minimal: output",         info1.output,           "vdsl")

-- ============================================================
-- Full render: VAE, clip_skip, LoRA, ControlNet
-- ============================================================
local info2 = roundtrip {
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

T.eq("full: world.model",     info2.world.model,     "xl.safetensors")
T.eq("full: world.vae",       info2.world.vae,       "custom_vae.safetensors")
T.eq("full: world.clip_skip", info2.world.clip_skip, 2)
T.eq("full: cast count",      #info2.casts,          1)
T.eq("full: cast prompt",     info2.casts[1].prompt,  "warrior")
T.eq("full: cast negative",   info2.casts[1].negative, "ugly")
T.ok("full: loras present",   info2.casts[1].loras ~= nil)
T.eq("full: lora count",      #info2.casts[1].loras, 1)
T.eq("full: lora name",       info2.casts[1].loras[1].name, "detail.safetensors")
T.eq("full: lora weight",     info2.casts[1].loras[1].weight, 0.6)
T.ok("full: stage present",   info2.stage ~= nil)
T.ok("full: stage cn",        info2.stage.controlnet ~= nil)
T.eq("full: cn count",        #info2.stage.controlnet, 1)
T.eq("full: cn type",         info2.stage.controlnet[1].type, "depth_model.pth")
T.eq("full: cn image",        info2.stage.controlnet[1].image, "depth.png")
T.eq("full: cn strength",     info2.stage.controlnet[1].strength, 0.7)
T.eq("full: sampler.steps",   info2.sampler.steps, 30)

-- ============================================================
-- Multi-cast
-- ============================================================
local info3 = roundtrip {
  world = vdsl.world { model = "model.safetensors" },
  cast = {
    vdsl.cast { subject = "warrior woman", negative = "ugly" },
    vdsl.cast { subject = "dragon", negative = "blurry" },
    vdsl.cast { subject = "castle background", negative = "low quality" },
  },
  seed = 42,
}

T.eq("multi: cast count", #info3.casts, 3)
T.eq("multi: cast1 prompt", info3.casts[1].prompt, "warrior woman")
T.eq("multi: cast2 prompt", info3.casts[2].prompt, "dragon")
T.eq("multi: cast3 prompt", info3.casts[3].prompt, "castle background")
T.eq("multi: cast1 neg",    info3.casts[1].negative, "ugly")
T.eq("multi: cast2 neg",    info3.casts[2].negative, "blurry")
T.eq("multi: cast3 neg",    info3.casts[3].negative, "low quality")

-- ============================================================
-- Post: hires fix
-- ============================================================
local info4 = roundtrip {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "landscape" } },
  post  = vdsl.post("hires", { scale = 1.5, steps = 10, denoise = 0.4 }),
  seed  = 42,
  steps = 20,
}

T.ok("hires: post present",    info4.post ~= nil)
T.eq("hires: post count",      #info4.post, 1)
T.eq("hires: op type",         info4.post[1].type, "hires")
T.eq("hires: scale",           info4.post[1].params.scale, 1.5)
T.eq("hires: denoise",         info4.post[1].params.denoise, 0.4)
T.eq("hires: steps",           info4.post[1].params.steps, 10)
-- Primary sampler is the first pass
T.eq("hires: primary steps",   info4.sampler.steps, 20)

-- ============================================================
-- Post: refine
-- ============================================================
local info5 = roundtrip {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "portrait" } },
  post  = vdsl.post("refine", { steps = 8, denoise = 0.25, sampler = "dpmpp_2m" }),
  seed  = 42,
}

T.ok("refine: post present",   info5.post ~= nil)
T.eq("refine: op type",        info5.post[1].type, "refine")
T.eq("refine: denoise",        info5.post[1].params.denoise, 0.25)
T.eq("refine: sampler",        info5.post[1].params.sampler, "dpmpp_2m")

-- ============================================================
-- Post: pixel upscale
-- ============================================================
local info6 = roundtrip {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "portrait" } },
  post  = vdsl.post("upscale", { model = "4x-UltraSharp.pth" }),
  seed  = 42,
}

T.ok("upscale: post present",  info6.post ~= nil)
T.eq("upscale: op type",       info6.post[1].type, "upscale")
T.eq("upscale: model",         info6.post[1].params.model, "4x-UltraSharp.pth")

-- ============================================================
-- Post: face restoration
-- ============================================================
local info7 = roundtrip {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "portrait woman" } },
  post  = vdsl.post("face", { model = "codeformer-v0.1.0.pth", fidelity = 0.7 }),
  seed  = 42,
}

T.ok("face: post present",  info7.post ~= nil)
T.eq("face: op type",       info7.post[1].type, "face")
T.eq("face: fidelity",      info7.post[1].params.fidelity, 0.7)
T.eq("face: model",         info7.post[1].params.model, "codeformer-v0.1.0.pth")

-- ============================================================
-- Post: color correction
-- ============================================================
local info8 = roundtrip {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "sunset" } },
  post  = vdsl.post("color", {
    brightness = 1.1, contrast = 1.2, saturation = 0.9, gamma = 0.95,
  }),
  seed  = 42,
}

T.ok("color: post present",   info8.post ~= nil)
T.eq("color: brightness",     info8.post[1].params.brightness, 1.1)
T.eq("color: contrast",       info8.post[1].params.contrast, 1.2)
T.eq("color: saturation",     info8.post[1].params.saturation, 0.9)
T.eq("color: gamma",          info8.post[1].params.gamma, 0.95)

-- ============================================================
-- Post: sharpen
-- ============================================================
local info9 = roundtrip {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "detail shot" } },
  post  = vdsl.post("sharpen", { radius = 2, sigma = 1.5, alpha = 0.8 }),
  seed  = 42,
}

T.ok("sharpen: post present",  info9.post ~= nil)
T.eq("sharpen: radius",        info9.post[1].params.radius, 2)
T.eq("sharpen: sigma",         info9.post[1].params.sigma, 1.5)
T.eq("sharpen: alpha",         info9.post[1].params.alpha, 0.8)

-- ============================================================
-- Post: resize by scale
-- ============================================================
local info10 = roundtrip {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "thumb" } },
  post  = vdsl.post("resize", { scale = 0.5, method = "bilinear" }),
  seed  = 42,
}

T.ok("resize scale: post",    info10.post ~= nil)
T.eq("resize scale: type",    info10.post[1].type, "resize")
T.eq("resize scale: scale",   info10.post[1].params.scale, 0.5)
T.eq("resize scale: method",  info10.post[1].params.method, "bilinear")

-- ============================================================
-- Post: resize by dimensions
-- ============================================================
local info11 = roundtrip {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "wallpaper" } },
  post  = vdsl.post("resize", { width = 1920, height = 1080 }),
  seed  = 42,
}

T.ok("resize dims: post",    info11.post ~= nil)
T.eq("resize dims: width",   info11.post[1].params.width, 1920)
T.eq("resize dims: height",  info11.post[1].params.height, 1080)

-- ============================================================
-- Full pipeline chain (hires + upscale + face + color + sharpen)
-- ============================================================
local info12 = roundtrip {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "detailed portrait" } },
  post  = vdsl.post("hires", { scale = 1.5, denoise = 0.4 })
        + vdsl.post("upscale", { model = "4x-UltraSharp.pth" })
        + vdsl.post("face", { fidelity = 0.6 })
        + vdsl.post("color", { contrast = 1.1 })
        + vdsl.post("sharpen", { radius = 1 }),
  seed  = 42,
}

T.ok("full post: present",     info12.post ~= nil)
T.eq("full post: count",       #info12.post, 5)
T.eq("full post: [1] hires",   info12.post[1].type, "hires")
T.eq("full post: [2] upscale", info12.post[2].type, "upscale")
T.eq("full post: [3] face",    info12.post[3].type, "face")
T.eq("full post: [4] color",   info12.post[4].type, "color")
T.eq("full post: [5] sharpen", info12.post[5].type, "sharpen")

-- ============================================================
-- Global negative detection
-- ============================================================
local info13 = roundtrip {
  world    = vdsl.world { model = "model.safetensors" },
  cast     = { vdsl.cast { subject = "cat", negative = "bad" } },
  negative = "ugly, blurry, deformed",
  seed     = 42,
}

T.eq("global neg: cast count", #info13.casts, 1)
T.eq("global neg: cast neg",   info13.casts[1].negative, "bad")
T.ok("global neg: detected",   info13.global_negatives ~= nil)
T.eq("global neg: count",      #info13.global_negatives, 1)
T.eq("global neg: text",       info13.global_negatives[1], "ugly, blurry, deformed")

-- ============================================================
-- img2img (Stage with latent_image)
-- ============================================================
local info14 = roundtrip {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "enhanced photo" } },
  stage = vdsl.stage { latent_image = "init.png" },
  seed  = 42,
}

T.ok("img2img: stage present",    info14.stage ~= nil)
T.eq("img2img: latent_image",     info14.stage.latent_image, "init.png")
T.eq("img2img: no size",          info14.size, nil)  -- no EmptyLatentImage

-- ============================================================
-- Multiple LoRAs
-- ============================================================
local info15 = roundtrip {
  world = vdsl.world { model = "model.safetensors" },
  cast = {
    vdsl.cast {
      subject  = "warrior",
      lora     = {
        { name = "detail.safetensors", weight = 0.6 },
        { name = "style.safetensors", weight = 0.8 },
      },
    },
  },
  seed = 42,
}

T.ok("multi lora: present",  info15.casts[1].loras ~= nil)
T.eq("multi lora: count",    #info15.casts[1].loras, 2)
T.eq("multi lora: [1] name", info15.casts[1].loras[1].name, "detail.safetensors")
T.eq("multi lora: [1] wt",   info15.casts[1].loras[1].weight, 0.6)
T.eq("multi lora: [2] name", info15.casts[1].loras[2].name, "style.safetensors")
T.eq("multi lora: [2] wt",   info15.casts[1].loras[2].weight, 0.8)

-- ============================================================
-- Decode from JSON string (simulating file load)
-- ============================================================
local r_for_json = vdsl.render {
  world = vdsl.world { model = "test.safetensors" },
  cast  = { vdsl.cast { subject = "cat", negative = "ugly" } },
  seed  = 99,
  steps = 15,
  cfg   = 6.0,
}
local json_str = r_for_json.json
local parsed = json.decode(json_str)
local info16 = decode.decode(parsed)

T.eq("from json: world.model",   info16.world.model,     "test.safetensors")
T.eq("from json: cast prompt",   info16.casts[1].prompt, "cat")
T.eq("from json: steps",         info16.sampler.steps,   15)
T.eq("from json: cfg",           info16.sampler.cfg,     6.0)

-- ============================================================
-- Custom output prefix
-- ============================================================
local info17 = roundtrip {
  world  = vdsl.world { model = "model.safetensors" },
  cast   = { vdsl.cast { subject = "test" } },
  seed   = 42,
  output = "my_prefix.png",
}

T.eq("output: prefix", info17.output, "my_prefix")

-- ============================================================
-- vdsl.decode convenience API
-- ============================================================
local r_api = vdsl.render {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = "api test" } },
  seed  = 42,
}
local info_api = vdsl.decode(r_api.prompt)
T.eq("api: world.model",  info_api.world.model, "model.safetensors")
T.eq("api: cast prompt",  info_api.casts[1].prompt, "api test")

-- ============================================================
-- Error handling
-- ============================================================
T.err("decode: nil input", function() decode.decode(nil) end)
T.err("decode: string input", function() decode.decode("bad") end)

-- Empty prompt: no crash, nil world
local info_empty = decode.decode({})
T.eq("empty: world nil", info_empty.world, nil)
T.eq("empty: casts",     #info_empty.casts, 0)

-- ============================================================
-- PNG reader: error cases
-- ============================================================
local _, png_err1 = png.read_text("")
T.ok("png: empty path error", png_err1 ~= nil)

local _, png_err2 = png.read_text("/nonexistent/file.png")
T.ok("png: missing file error", png_err2 ~= nil)

-- ============================================================
-- PNG reader: synthetic PNG with tEXt chunk
-- ============================================================

--- Build a minimal PNG file with a tEXt chunk for testing.
local function build_test_png(text_chunks)
  local parts = {}
  -- PNG signature
  parts[#parts + 1] = "\137PNG\r\n\26\n"

  -- Minimal IHDR (13 bytes data)
  local ihdr_data = string.char(
    0, 0, 0, 1,  -- width = 1
    0, 0, 0, 1,  -- height = 1
    8,            -- bit depth
    2,            -- color type (RGB)
    0, 0, 0      -- compression, filter, interlace
  )
  -- Chunk: length(4) + "IHDR"(4) + data(13) + crc(4)
  local function uint32_be(n)
    return string.char(
      math.floor(n / 0x1000000) % 256,
      math.floor(n / 0x10000) % 256,
      math.floor(n / 0x100) % 256,
      n % 256
    )
  end
  parts[#parts + 1] = uint32_be(#ihdr_data) .. "IHDR" .. ihdr_data .. "\0\0\0\0"

  -- tEXt chunks
  for keyword, text in pairs(text_chunks) do
    local chunk_data = keyword .. "\0" .. text
    parts[#parts + 1] = uint32_be(#chunk_data) .. "tEXt" .. chunk_data .. "\0\0\0\0"
  end

  -- Minimal IDAT (empty, just for structure)
  parts[#parts + 1] = uint32_be(0) .. "IDAT" .. "\0\0\0\0"

  -- IEND
  parts[#parts + 1] = uint32_be(0) .. "IEND" .. "\0\0\0\0"

  return table.concat(parts)
end

-- Write test PNG to temp file
local test_prompt = json.encode({
  ["1"] = { class_type = "CheckpointLoaderSimple", inputs = { ckpt_name = "test_from_png.safetensors" } },
  ["2"] = { class_type = "CLIPTextEncode", inputs = { clip = { "1", 1 }, text = "cat from png" } },
  ["3"] = { class_type = "CLIPTextEncode", inputs = { clip = { "1", 1 }, text = "bad" } },
  ["4"] = { class_type = "EmptyLatentImage", inputs = { width = 768, height = 768, batch_size = 1 } },
  ["5"] = { class_type = "KSampler", inputs = {
    model = { "1", 0 }, positive = { "2", 0 }, negative = { "3", 0 },
    latent_image = { "4", 0 }, seed = 123, steps = 25, cfg = 7.5,
    sampler_name = "euler", scheduler = "normal", denoise = 1.0,
  } },
  ["6"] = { class_type = "VAEDecode", inputs = { samples = { "5", 0 }, vae = { "1", 2 } } },
  ["7"] = { class_type = "SaveImage", inputs = { images = { "6", 0 }, filename_prefix = "test" } },
})

local png_data = build_test_png({ prompt = test_prompt })
local tmp_path = os.tmpname() .. ".png"
local f = io.open(tmp_path, "wb")
f:write(png_data)
f:close()

-- Read back
local chunks, chunk_err = png.read_text(tmp_path)
T.ok("synth png: no error",      chunk_err == nil)
T.ok("synth png: has prompt",     chunks ~= nil and chunks["prompt"] ~= nil)

-- Full read_comfy
local comfy_meta = png.read_comfy(tmp_path)
T.ok("synth comfy: has prompt",   comfy_meta ~= nil and comfy_meta.prompt ~= nil)

-- Full import_png
local import_info = vdsl.import_png(tmp_path)
T.ok("import: not nil",          import_info ~= nil)
T.eq("import: world.model",      import_info.world.model, "test_from_png.safetensors")
T.eq("import: cast prompt",      import_info.casts[1].prompt, "cat from png")
T.eq("import: size[1]",          import_info.size[1], 768)
T.eq("import: size[2]",          import_info.size[2], 768)
T.eq("import: seed",             import_info.sampler.seed, 123)
T.eq("import: steps",            import_info.sampler.steps, 25)

-- Cleanup
os.remove(tmp_path)

-- ============================================================
-- PNG: not a PNG file
-- ============================================================
local bad_path = os.tmpname()
local bf = io.open(bad_path, "wb")
bf:write("not a png file")
bf:close()
local _, bad_err = png.read_text(bad_path)
T.ok("bad png: error", bad_err ~= nil and bad_err:find("not a valid PNG") ~= nil)
os.remove(bad_path)

T.summary()
