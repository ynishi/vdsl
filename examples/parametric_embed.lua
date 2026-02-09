--- parametric_embed.lua: Import → Parametric variations → Embed recipes into PNG copies
-- Each output PNG carries its own vdsl recipe for full semantic round-trip.
--
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;'..package.path" examples/parametric_embed.lua

local vdsl = require("vdsl")
local json  = require("vdsl.json")

-- ============================================================
-- 1. Import: 元画像から情報抽出
-- ============================================================

local source = arg[1] or "input.png"  -- pass source PNG as argument
local info, err, has_recipe = vdsl.import_png(source)

if not info then
  print("Import failed: " .. tostring(err))
  return
end

print("=== Source Image ===")
if has_recipe then
  print("  (vdsl recipe found - full semantic)")
else
  print("  (structural decode - best effort)")
end
print("  model:    " .. (info.world and info.world.model or info.casts[1].prompt:sub(1, 40)))
if info.casts then
  print("  prompt:   " .. info.casts[1].prompt:sub(1, 60) .. "...")
end
if info.sampler then
  print("  steps:    " .. info.sampler.steps .. "  cfg: " .. info.sampler.cfg)
end

-- ============================================================
-- 2. Semantic decomposition: Trait に分解
-- ============================================================

local w = vdsl.world { model = info.world.model }

-- Character
local girl      = vdsl.trait("1girl, solo")
local red_hair  = vdsl.trait("long flowing red hair, vibrant", 1.2)
local smile     = vdsl.trait("smiling, happy, expressive eyes")
local dress     = vdsl.trait("elegant white dress, flowing fabric")
local jewel     = vdsl.trait("crystal necklace, earrings")

-- Atmosphere
local sakura    = vdsl.trait("cherry blossoms, petals falling, spring")
local sunset    = vdsl.trait("sunset, golden hour, warm light", 1.1)
local park      = vdsl.trait("park path, trees, natural setting")

-- Negative
local neg = vdsl.trait("worst quality, bad quality, simple background")
  + vdsl.trait("text, watermark, signature, username", 1.5)
  + vdsl.trait("monochrome")

-- Base subject
local heroine = vdsl.subject("masterpiece, best quality")
  :with(girl):with(red_hair):with(smile)
  :with(dress):with(jewel)
  :quality("high")

-- ============================================================
-- 3. Output directory
-- ============================================================

local out_dir = "/tmp/vdsl_parametric"
os.execute("mkdir -p " .. out_dir)

-- ============================================================
-- 4. Parametric grid: Season × Style
-- ============================================================

local seasons = {
  { name = "spring", trait = sakura + vdsl.trait("bright green leaves, warm breeze") },
  { name = "summer", trait = vdsl.trait("sunflowers, blue sky, hot summer day, vivid green")
      + vdsl.trait("straw hat, sundress", 0.8) },
  { name = "autumn", trait = vdsl.trait("autumn leaves, red and gold, falling maple, cool breeze")
      + vdsl.trait("cozy sweater, scarf", 0.8) },
  { name = "winter", trait = vdsl.trait("snow, winter landscape, bare trees, soft light")
      + vdsl.trait("fur coat, warm mittens", 0.8) },
}

local styles = {
  { name = "anime",  theme = vdsl.themes.anime,  trait = nil },
  { name = "cinema", theme = vdsl.themes.cinema,  trait = nil },
  { name = "photo",  theme = nil, trait = vdsl.trait("photorealistic, 8k, raw photo, film grain") },
}

print(string.format("\n=== Parametric Grid: %d seasons × %d styles = %d variants ===",
  #seasons, #styles, #seasons * #styles))

local results = {}

for _, season in ipairs(seasons) do
  for _, style in ipairs(styles) do
    local tag = season.name .. "_" .. style.name
    local subj = heroine:with(season.trait):with(sunset)

    -- Style trait を追加 (theme が無い場合)
    if style.trait then
      subj = subj:with(style.trait)
    end

    -- Render opts (recipe の素)
    local render_opts = {
      world = w,
      theme = style.theme,
      cast  = { vdsl.cast { subject = subj, negative = neg } },
      seed  = 42,
      steps = 25,
      cfg   = 5.5,
      size  = { 1024, 1024 },
      output = tag,
    }

    -- Compile
    local result = vdsl.render(render_opts)

    -- Embed recipe into PNG copy
    local dst = out_dir .. "/" .. tag .. ".png"
    local ok, embed_err = vdsl.embed_to(source, dst, render_opts)

    results[#results + 1] = {
      tag    = tag,
      nodes  = result.graph:size(),
      dst    = dst,
      ok     = ok,
      err    = embed_err,
    }

    if ok then
      print(string.format("  %-20s %2d nodes  -> %s", tag, result.graph:size(), dst))
    else
      print(string.format("  %-20s FAILED: %s", tag, embed_err or "unknown"))
    end
  end
end

-- ============================================================
-- 5. Verify: 全コピーから recipe を読み戻し
-- ============================================================

print(string.format("\n=== Verification: reading back %d recipes ===", #results))
local pass, fail = 0, 0

for _, r in ipairs(results) do
  if not r.ok then
    fail = fail + 1
    goto continue
  end

  local imported, ierr, is_recipe = vdsl.import_png(r.dst)
  if imported and is_recipe then
    -- Recipe round-trip check
    local rt_world = imported.world and imported.world.model or "?"
    local rt_seed  = imported.seed or "?"
    local rt_cast  = imported.cast and #imported.cast or 0
    print(string.format("  %-20s recipe OK  model=%s seed=%s casts=%d",
      r.tag, rt_world, tostring(rt_seed), rt_cast))
    pass = pass + 1
  else
    print(string.format("  %-20s FAIL: recipe=%s err=%s",
      r.tag, tostring(is_recipe), tostring(ierr)))
    fail = fail + 1
  end

  ::continue::
end

print(string.format("\n  Result: %d/%d passed", pass, pass + fail))

-- ============================================================
-- 6. Bonus: LoRA weight sweep + embed
-- ============================================================

print("\n=== LoRA Weight Sweep (detail) ===")
local sweep_results = {}

for w_val = 0.2, 1.0, 0.2 do
  local tag = string.format("lora_%.1f", w_val)
  local subj = heroine:with(sakura):with(sunset)

  local render_opts = {
    world = w,
    cast  = { vdsl.cast {
      subject = subj,
      negative = neg,
      lora = { vdsl.lora("add_detail.safetensors", w_val) },
    }},
    seed  = 42,
    steps = 25,
    cfg   = 5.5,
    size  = { 1024, 1024 },
    output = tag,
  }

  local result = vdsl.render(render_opts)
  local dst = out_dir .. "/" .. tag .. ".png"
  local ok, embed_err = vdsl.embed_to(source, dst, render_opts)

  -- Verify lora weight in compiled graph
  local compiled_weight = nil
  for _, node in pairs(result.prompt) do
    if node.class_type == "LoraLoader" then
      compiled_weight = node.inputs.strength_model
    end
  end

  -- Verify round-trip
  local rt_lora_weight = nil
  if ok then
    local imported = vdsl.import_png(dst)
    if imported and imported.cast and imported.cast[1] then
      local c = imported.cast[1]
      if c.lora and c.lora[1] then
        rt_lora_weight = c.lora[1].weight
      end
    end
  end

  print(string.format("  weight=%.1f  compiled=%.1f  roundtrip=%s  -> %s",
    w_val,
    compiled_weight or -1,
    rt_lora_weight and string.format("%.1f", rt_lora_weight) or "FAIL",
    ok and dst or "EMBED_FAIL"))

  sweep_results[#sweep_results + 1] = {
    tag = tag, weight = w_val,
    compiled = compiled_weight, roundtrip = rt_lora_weight,
  }
end

-- ============================================================
-- 7. Summary
-- ============================================================

local total_files = #results + #sweep_results
print(string.format("\n=== Summary ==="))
print(string.format("  Source:  %s", source))
print(string.format("  Output:  %s/", out_dir))
print(string.format("  Files:   %d PNG copies with embedded recipes", total_files))
print(string.format("  Grid:    %d seasons × %d styles", #seasons, #styles))
print(string.format("  Sweep:   %d LoRA weight steps", #sweep_results))
print(string.format("\n  Each PNG is self-contained: image + vdsl recipe."))
print(string.format("  Re-import with: vdsl.import_png(path) → full semantic entities"))
