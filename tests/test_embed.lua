--- test_embed.lua: Verify PNG inject, recipe serialize/deserialize, embed round-trip
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;tests/?.lua;'..package.path" tests/test_embed.lua

local vdsl   = require("vdsl")
local png    = require("vdsl.png")
local json   = require("vdsl.json")
local recipe = require("vdsl.recipe")
local Entity = require("vdsl.entity")
local T      = require("harness")

-- ============================================================
-- Helper: build a minimal valid PNG for testing
-- ============================================================

local function uint32_be(n)
  return string.char(
    math.floor(n / 0x1000000) % 256,
    math.floor(n / 0x10000) % 256,
    math.floor(n / 0x100) % 256,
    n % 256
  )
end

local function build_test_png(text_chunks)
  local parts = {}
  parts[#parts + 1] = "\137PNG\r\n\26\n"

  -- IHDR
  local ihdr_data = string.char(0,0,0,1, 0,0,0,1, 8, 2, 0,0,0)
  parts[#parts + 1] = uint32_be(#ihdr_data) .. "IHDR" .. ihdr_data .. "\0\0\0\0"

  -- tEXt chunks (with dummy CRC - will be rewritten by inject)
  if text_chunks then
    for keyword, text in pairs(text_chunks) do
      local chunk_data = keyword .. "\0" .. text
      parts[#parts + 1] = uint32_be(#chunk_data) .. "tEXt" .. chunk_data .. "\0\0\0\0"
    end
  end

  -- IDAT
  parts[#parts + 1] = uint32_be(0) .. "IDAT" .. "\0\0\0\0"
  -- IEND
  parts[#parts + 1] = uint32_be(0) .. "IEND" .. "\0\0\0\0"

  return table.concat(parts)
end

local function write_tmp_png(text_chunks)
  local path = os.tmpname() .. ".png"
  local f = io.open(path, "wb")
  f:write(build_test_png(text_chunks))
  f:close()
  return path
end

--- Build a valid 1x1 black PNG with correct CRCs and proper IDAT.
-- Unlike build_test_png (dummy CRC/empty IDAT), this produces a spec-compliant PNG.
local function build_valid_png(text_chunks)
  local crc32 = png._crc32

  local function make_chunk(chunk_type, data)
    local payload = chunk_type .. data
    return uint32_be(#data) .. payload .. uint32_be(crc32(payload))
  end

  local parts = {}
  parts[#parts + 1] = "\137PNG\r\n\26\n"

  -- IHDR: 1x1, 8-bit RGB, no interlace
  parts[#parts + 1] = make_chunk("IHDR",
    string.char(0,0,0,1, 0,0,0,1, 8, 2, 0,0,0))

  -- tEXt chunks
  if text_chunks then
    for keyword, text in pairs(text_chunks) do
      parts[#parts + 1] = make_chunk("tEXt", keyword .. "\0" .. text)
    end
  end

  -- IDAT: zlib-wrapped deflate stored block for 1x1 RGB black pixel
  -- Raw data: filter_byte(0x00) + R(0x00) G(0x00) B(0x00) = 4 bytes of 0x00
  -- Zlib header: CMF=0x78 FLG=0x01
  -- Deflate stored: BFINAL=1 BTYPE=00 → 0x01, LEN=4(LE), NLEN=0xFFFB(LE), data
  -- Adler32 of [0,0,0,0]: A=1 B=4 → 0x00040001 (BE)
  local idat_data = string.char(
    0x78, 0x01,                         -- zlib header
    0x01,                               -- BFINAL=1, BTYPE=00 (stored)
    0x04, 0x00,                         -- LEN=4 (little-endian)
    0xFB, 0xFF,                         -- NLEN=~4 (little-endian)
    0x00, 0x00, 0x00, 0x00,            -- pixel data: filter(0) + RGB(0,0,0)
    0x00, 0x04, 0x00, 0x01             -- Adler-32 (big-endian)
  )
  parts[#parts + 1] = make_chunk("IDAT", idat_data)

  -- IEND
  parts[#parts + 1] = make_chunk("IEND", "")

  return table.concat(parts)
end

local function write_valid_tmp_png(text_chunks)
  local path = os.tmpname() .. ".png"
  local f = io.open(path, "wb")
  f:write(build_valid_png(text_chunks))
  f:close()
  return path
end

-- ============================================================
-- CRC32 basic test
-- ============================================================

-- Known CRC32 of "IEND" (empty IEND chunk type+data) = 0xAE426082
local crc = png._crc32("IEND")
T.eq("crc32: IEND", crc, 0xAE426082)

-- RFC 3720 check value: CRC32("123456789") = 0xCBF43926
T.eq("crc32: RFC3720", png._crc32("123456789"), 0xCBF43926)

-- Empty string CRC32 = 0x00000000
T.eq("crc32: empty", png._crc32(""), 0x00000000)

-- ============================================================
-- PNG inject_text: basic
-- ============================================================

local path1 = write_tmp_png(nil)
local ok1, err1 = png.inject_text(path1, { hello = "world", foo = "bar" })
T.ok("inject: success", ok1)
T.eq("inject: no error", err1, nil)

-- Read back
local chunks1 = png.read_text(path1)
T.ok("inject: read back", chunks1 ~= nil)
T.eq("inject: hello", chunks1["hello"], "world")
T.eq("inject: foo", chunks1["foo"], "bar")
os.remove(path1)

-- ============================================================
-- PNG inject_text: overwrites existing chunk with same keyword
-- ============================================================

local path2 = write_tmp_png({ existing = "old_value" })
local chunks2a = png.read_text(path2)
T.eq("overwrite: before", chunks2a["existing"], "old_value")

png.inject_text(path2, { existing = "new_value" })
local chunks2b = png.read_text(path2)
T.eq("overwrite: after", chunks2b["existing"], "new_value")
os.remove(path2)

-- ============================================================
-- PNG inject_text: preserves non-conflicting chunks
-- ============================================================

local path3 = write_tmp_png({ keep_me = "preserved" })
png.inject_text(path3, { added = "new" })
local chunks3 = png.read_text(path3)
T.eq("preserve: keep_me", chunks3["keep_me"], "preserved")
T.eq("preserve: added", chunks3["added"], "new")
os.remove(path3)

-- ============================================================
-- PNG inject_text_to: non-destructive copy
-- ============================================================

local src4 = write_tmp_png({ original = "data" })
local dst4 = os.tmpname() .. ".png"
local ok4 = png.inject_text_to(src4, dst4, { injected = "new" })
T.ok("inject_to: success", ok4)

-- Source unchanged
local chunks4a = png.read_text(src4)
T.eq("inject_to: src unchanged", chunks4a["injected"], nil)
T.eq("inject_to: src original", chunks4a["original"], "data")

-- Dest has both
local chunks4b = png.read_text(dst4)
T.eq("inject_to: dst original", chunks4b["original"], "data")
T.eq("inject_to: dst injected", chunks4b["injected"], "new")
os.remove(src4)
os.remove(dst4)

-- ============================================================
-- PNG inject: error cases
-- ============================================================

local ok_e1, err_e1 = png.inject_text("", { x = "y" })
T.ok("inject err: empty path", not ok_e1 and err_e1 ~= nil)

local ok_e2, err_e2 = png.inject_text("/nonexistent/path.png", { x = "y" })
T.ok("inject err: missing file", not ok_e2 and err_e2 ~= nil)

-- ============================================================
-- Recipe serialize: basic round-trip
-- ============================================================

local render_opts = {
  world = vdsl.world { model = "test.safetensors", vae = "my_vae.safetensors", clip_skip = 2 },
  cast = {
    vdsl.cast {
      subject  = vdsl.subject("warrior"):with(vdsl.trait("detailed face", 1.3)):quality("high"),
      negative = vdsl.trait("ugly, blurry"),
      lora     = { vdsl.lora("detail.safetensors", 0.6) },
    },
  },
  seed  = 42,
  steps = 25,
  cfg   = 5.5,
  size  = { 1024, 1024 },
}

local serialized = recipe.serialize(render_opts)
T.ok("recipe ser: is string", type(serialized) == "string")
T.ok("recipe ser: has content", #serialized > 10)

local restored = recipe.deserialize(serialized)
T.ok("recipe deser: is table", type(restored) == "table")
T.ok("recipe deser: has world", restored.world ~= nil)
T.ok("recipe deser: world is entity", Entity.is(restored.world, "world"))
T.eq("recipe deser: model", restored.world.model, "test.safetensors")
T.eq("recipe deser: vae", restored.world.vae, "my_vae.safetensors")
T.eq("recipe deser: clip_skip", restored.world.clip_skip, 2)

T.ok("recipe deser: has cast", restored.cast ~= nil)
T.eq("recipe deser: cast count", #restored.cast, 1)
T.ok("recipe deser: cast[1] is entity", Entity.is(restored.cast[1], "cast"))
T.ok("recipe deser: subject is entity", Entity.is(restored.cast[1].subject, "subject"))
T.ok("recipe deser: negative is entity", Entity.is(restored.cast[1].negative, "trait"))

-- Prompt text preserved
local prompt_text = restored.cast[1].subject:resolve()
T.ok("recipe deser: has warrior", prompt_text:find("warrior") ~= nil)
T.ok("recipe deser: has detailed face", prompt_text:find("detailed face") ~= nil)

-- Emphasis preserved
T.ok("recipe deser: emphasis 1.3", prompt_text:find("1.3") ~= nil)

-- LoRA preserved
T.ok("recipe deser: has lora", restored.cast[1].lora ~= nil)
T.eq("recipe deser: lora name", restored.cast[1].lora[1].name, "detail.safetensors")
T.eq("recipe deser: lora weight", restored.cast[1].lora[1].weight, 0.6)

-- Render params preserved
T.eq("recipe deser: seed", restored.seed, 42)
T.eq("recipe deser: steps", restored.steps, 25)
T.eq("recipe deser: cfg", restored.cfg, 5.5)
T.eq("recipe deser: size[1]", restored.size[1], 1024)

-- ============================================================
-- Recipe with hints (semantic info that compile loses)
-- ============================================================

local hinted_opts = {
  world = vdsl.world { model = "test.safetensors" },
  cast = {
    vdsl.cast {
      subject = vdsl.subject("portrait")
        :with(vdsl.trait("face closeup"):hint("face", { fidelity = 0.7 }))
        :with(vdsl.trait("high res"):hint("hires", { scale = 1.5 })),
    },
  },
  seed = 42,
}

local hint_ser = recipe.serialize(hinted_opts)
local hint_deser = recipe.deserialize(hint_ser)

-- Hints survive round-trip
local hint_subj = hint_deser.cast[1].subject
local hints = hint_subj:hints()
T.ok("hint rt: has hints", hints ~= nil)
T.ok("hint rt: face",      hints.face ~= nil)
T.eq("hint rt: fidelity",  hints.face.fidelity, 0.7)
T.ok("hint rt: hires",     hints.hires ~= nil)
T.eq("hint rt: scale",     hints.hires.scale, 1.5)

-- ============================================================
-- Recipe with theme reference
-- ============================================================

local theme_opts = {
  world = vdsl.world { model = "test.safetensors" },
  cast  = { vdsl.cast { subject = "cat" } },
  theme = vdsl.themes.cinema,
  seed  = 42,
}

local theme_ser = recipe.serialize(theme_opts)
local theme_deser = recipe.deserialize(theme_ser)
T.ok("theme rt: loaded",   theme_deser.theme ~= nil)
T.eq("theme rt: name",     theme_deser.theme.name, "cinema")

-- ============================================================
-- Recipe with Stage
-- ============================================================

local stage_opts = {
  world = vdsl.world { model = "test.safetensors" },
  cast  = { vdsl.cast { subject = "cat" } },
  stage = vdsl.stage {
    controlnet = { { type = "depth.pth", image = "depth.png", strength = 0.8 } },
    latent_image = "init.png",
  },
  seed = 42,
}

local stage_ser = recipe.serialize(stage_opts)
local stage_deser = recipe.deserialize(stage_ser)
T.ok("stage rt: present", stage_deser.stage ~= nil)
T.ok("stage rt: is entity", Entity.is(stage_deser.stage, "stage"))
T.eq("stage rt: cn type", stage_deser.stage.controlnet[1].type, "depth.pth")
T.eq("stage rt: cn image", stage_deser.stage.controlnet[1].image, "depth.png")
T.eq("stage rt: latent", stage_deser.stage.latent_image, "init.png")

-- ============================================================
-- Recipe with Post chain
-- ============================================================

local post_opts = {
  world = vdsl.world { model = "test.safetensors" },
  cast  = { vdsl.cast { subject = "cat" } },
  post  = vdsl.post("hires", { scale = 1.5 })
        + vdsl.post("upscale", { model = "4x.pth" })
        + vdsl.post("face", { fidelity = 0.6 }),
  seed = 42,
}

local post_ser = recipe.serialize(post_opts)
local post_deser = recipe.deserialize(post_ser)
T.ok("post rt: present", post_deser.post ~= nil)
T.ok("post rt: is entity", Entity.is(post_deser.post, "post"))
local ops = post_deser.post:ops()
T.eq("post rt: count", #ops, 3)
T.eq("post rt: [1]", ops[1].type, "hires")
T.eq("post rt: [2]", ops[2].type, "upscale")
T.eq("post rt: [3]", ops[3].type, "face")

-- ============================================================
-- Recipe with global negative (Trait)
-- ============================================================

local gneg_opts = {
  world    = vdsl.world { model = "test.safetensors" },
  cast     = { vdsl.cast { subject = "cat" } },
  negative = vdsl.trait("ugly") + vdsl.trait("blurry", 1.5),
  seed     = 42,
}

local gneg_ser = recipe.serialize(gneg_opts)
local gneg_deser = recipe.deserialize(gneg_ser)
T.ok("gneg rt: present", gneg_deser.negative ~= nil)
local gneg_text = Entity.resolve_text(gneg_deser.negative)
T.ok("gneg rt: ugly", gneg_text:find("ugly") ~= nil)
T.ok("gneg rt: blurry", gneg_text:find("blurry") ~= nil)
T.ok("gneg rt: emphasis", gneg_text:find("1.5") ~= nil)

-- ============================================================
-- Recipe serialize error
-- ============================================================

T.err("recipe ser: nil", function() recipe.serialize(nil) end)
T.err("recipe deser: nil", function() recipe.deserialize(nil) end)

-- ============================================================
-- Full embed round-trip: render → embed → import_png
-- ============================================================

-- Step 1: Create a test PNG
local embed_path = write_tmp_png({
  prompt = json.encode({
    ["1"] = { class_type = "CheckpointLoaderSimple", inputs = { ckpt_name = "test.safetensors" } },
    ["2"] = { class_type = "CLIPTextEncode", inputs = { clip = {"1", 1}, text = "a cat" } },
    ["3"] = { class_type = "CLIPTextEncode", inputs = { clip = {"1", 1}, text = "bad" } },
    ["4"] = { class_type = "EmptyLatentImage", inputs = { width = 512, height = 512, batch_size = 1 } },
    ["5"] = { class_type = "KSampler", inputs = {
      model = {"1", 0}, positive = {"2", 0}, negative = {"3", 0},
      latent_image = {"4", 0}, seed = 42, steps = 20, cfg = 7.0,
      sampler_name = "euler", scheduler = "normal", denoise = 1.0,
    }},
    ["6"] = { class_type = "VAEDecode", inputs = { samples = {"5", 0}, vae = {"1", 2} } },
    ["7"] = { class_type = "SaveImage", inputs = { images = {"6", 0}, filename_prefix = "test" } },
  }),
})

-- Step 2: Embed vdsl recipe
local embed_opts = {
  world = vdsl.world { model = "test.safetensors" },
  cast = {
    vdsl.cast {
      subject  = vdsl.subject("a cat"):with(vdsl.trait("fluffy"):hint("sharpen", { radius = 1 })):quality("high"),
      negative = vdsl.trait("bad quality"),
    },
  },
  seed  = 42,
  steps = 20,
  cfg   = 7.0,
  size  = { 512, 512 },
}

local embed_ok, embed_err = vdsl.embed(embed_path, embed_opts)
T.ok("embed: success", embed_ok)
T.eq("embed: no error", embed_err, nil)

-- Step 3: Import — should find vdsl recipe (not structural decode)
local imported, imp_err, has_recipe = vdsl.import_png(embed_path)
T.ok("embed rt: imported", imported ~= nil)
T.eq("embed rt: no error", imp_err, nil)
T.ok("embed rt: has recipe", has_recipe)

-- Step 4: Verify semantic info survived
T.ok("embed rt: world", Entity.is(imported.world, "world"))
T.eq("embed rt: model", imported.world.model, "test.safetensors")
T.ok("embed rt: cast", Entity.is(imported.cast[1], "cast"))

-- Subject with full trait composition
local subj_text = imported.cast[1].subject:resolve()
T.ok("embed rt: has cat", subj_text:find("a cat") ~= nil)
T.ok("embed rt: has fluffy", subj_text:find("fluffy") ~= nil)

-- Hints preserved (this is what structural decode CANNOT recover!)
local subj_hints = imported.cast[1].subject:hints()
T.ok("embed rt: hints present", subj_hints ~= nil)
T.ok("embed rt: sharpen hint", subj_hints.sharpen ~= nil)
T.eq("embed rt: sharpen radius", subj_hints.sharpen.radius, 1)

-- Params preserved
T.eq("embed rt: seed", imported.seed, 42)
T.eq("embed rt: steps", imported.steps, 20)
T.eq("embed rt: cfg", imported.cfg, 7.0)

-- Step 5: Original ComfyUI prompt chunk still readable
local chunks_check = png.read_text(embed_path)
T.ok("embed rt: prompt preserved", chunks_check["prompt"] ~= nil)
T.ok("embed rt: vdsl added", chunks_check["vdsl"] ~= nil)

os.remove(embed_path)

-- ============================================================
-- Import fallback: PNG without vdsl chunk → structural decode
-- ============================================================

local fallback_path = write_tmp_png({
  prompt = json.encode({
    ["1"] = { class_type = "CheckpointLoaderSimple", inputs = { ckpt_name = "fallback.safetensors" } },
    ["2"] = { class_type = "CLIPTextEncode", inputs = { clip = {"1", 1}, text = "hello" } },
    ["3"] = { class_type = "CLIPTextEncode", inputs = { clip = {"1", 1}, text = "bad" } },
    ["4"] = { class_type = "EmptyLatentImage", inputs = { width = 768, height = 768, batch_size = 1 } },
    ["5"] = { class_type = "KSampler", inputs = {
      model = {"1", 0}, positive = {"2", 0}, negative = {"3", 0},
      latent_image = {"4", 0}, seed = 99, steps = 15, cfg = 6.0,
      sampler_name = "euler", scheduler = "normal", denoise = 1.0,
    }},
    ["6"] = { class_type = "VAEDecode", inputs = { samples = {"5", 0}, vae = {"1", 2} } },
    ["7"] = { class_type = "SaveImage", inputs = { images = {"6", 0}, filename_prefix = "fb" } },
  }),
})

local fb_info, fb_err, fb_has_recipe = vdsl.import_png(fallback_path)
T.ok("fallback: imported", fb_info ~= nil)
T.ok("fallback: no recipe", not fb_has_recipe)
T.eq("fallback: model", fb_info.world.model, "fallback.safetensors")
T.eq("fallback: cast prompt", fb_info.casts[1].prompt, "hello")
os.remove(fallback_path)

-- ============================================================
-- render_with_recipe: convenience
-- ============================================================

local rwr_opts = {
  world = vdsl.world { model = "test.safetensors" },
  cast  = { vdsl.cast { subject = "test" } },
  seed  = 42,
}
local rwr = vdsl.render_with_recipe(rwr_opts)
T.ok("rwr: has prompt", rwr.prompt ~= nil)
T.ok("rwr: has json",   rwr.json ~= nil)
T.ok("rwr: has recipe", type(rwr.recipe) == "string")

-- Recipe can be deserialized
local rwr_restored = recipe.deserialize(rwr.recipe)
T.eq("rwr: model", rwr_restored.world.model, "test.safetensors")

-- ============================================================
-- embed_to: non-destructive embed
-- ============================================================

local src_et = write_tmp_png({ prompt = '{"1":{"class_type":"x","inputs":{}}}' })
local dst_et = os.tmpname() .. ".png"

local et_ok = vdsl.embed_to(src_et, dst_et, {
  world = vdsl.world { model = "m.safetensors" },
  cast  = { vdsl.cast { subject = "y" } },
  seed  = 1,
})
T.ok("embed_to: success", et_ok)

-- Source has no vdsl chunk
local src_chunks = png.read_text(src_et)
T.eq("embed_to: src no vdsl", src_chunks["vdsl"], nil)

-- Dest has vdsl chunk
local dst_chunks = png.read_text(dst_et)
T.ok("embed_to: dst has vdsl", dst_chunks["vdsl"] ~= nil)
os.remove(src_et)
os.remove(dst_et)

-- ============================================================
-- Valid PNG test: embed into a spec-compliant generated PNG
-- ============================================================

local valid_png_path = write_valid_tmp_png({
  prompt = json.encode({
    ["1"] = { class_type = "CheckpointLoaderSimple", inputs = { ckpt_name = "sd_v15.safetensors" } },
    ["2"] = { class_type = "CLIPTextEncode", inputs = { clip = {"1", 1}, text = "portrait, detailed" } },
    ["3"] = { class_type = "CLIPTextEncode", inputs = { clip = {"1", 1}, text = "low quality" } },
    ["4"] = { class_type = "EmptyLatentImage", inputs = { width = 512, height = 512, batch_size = 1 } },
    ["5"] = { class_type = "KSampler", inputs = {
      model = {"1", 0}, positive = {"2", 0}, negative = {"3", 0},
      latent_image = {"4", 0}, seed = 100, steps = 20, cfg = 7.0,
      sampler_name = "euler", scheduler = "normal", denoise = 1.0,
    }},
    ["6"] = { class_type = "VAEDecode", inputs = { samples = {"5", 0}, vae = {"1", 2} } },
    ["7"] = { class_type = "SaveImage", inputs = { images = {"6", 0}, filename_prefix = "test" } },
  }),
})

local valid_opts = {
  world = vdsl.world { model = "sd_v15.safetensors" },
  cast = {
    vdsl.cast {
      subject = vdsl.subject("portrait, detailed")
        :with(vdsl.trait("warm lighting"))
        :with(vdsl.trait("soft focus", 1.2))
        :with(vdsl.trait("natural pose")),
      negative = vdsl.trait("low quality, blurry")
        + vdsl.trait("text, watermark", 1.5),
    },
  },
  seed  = 100,
  steps = 20,
  cfg   = 7.0,
  size  = { 512, 512 },
}

local valid_ok = vdsl.embed(valid_png_path, valid_opts)
T.ok("valid png: embed ok", valid_ok)

-- Import back
local valid_imported, _, valid_has_recipe = vdsl.import_png(valid_png_path)
T.ok("valid png: has recipe", valid_has_recipe)
T.eq("valid png: model", valid_imported.world.model, "sd_v15.safetensors")

-- Emphasis preserved
local valid_text = valid_imported.cast[1].subject:resolve()
T.ok("valid png: has portrait", valid_text:find("portrait") ~= nil)
T.ok("valid png: emphasis 1.2", valid_text:find("1.2") ~= nil)

-- Negative emphasis preserved
local valid_neg = Entity.resolve_text(valid_imported.cast[1].negative)
T.ok("valid png: neg emphasis 1.5", valid_neg:find("1.5") ~= nil)

-- Original prompt chunk still intact
local valid_chunks = png.read_text(valid_png_path)
T.ok("valid png: prompt intact", valid_chunks["prompt"] ~= nil)
T.ok("valid png: vdsl added", valid_chunks["vdsl"] ~= nil)

os.remove(valid_png_path)

T.summary()
