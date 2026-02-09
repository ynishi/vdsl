--- import_remix.lua: Import a ComfyUI image → analyze → remix with DSL
-- Demonstrates: import_png, Trait composition, Theme, multi-cast, Post, parametric sweep
--
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;'..package.path" examples/import_remix.lua

local vdsl = require("vdsl")
local json  = require("vdsl.json")

-- ============================================================
-- 1. Import: PNG → decode
-- ============================================================

local source = arg[1] or "input.png"  -- pass source PNG as argument
local info, err = vdsl.import_png(source)

if not info then
  print("Import failed: " .. tostring(err))
  return
end

print("=== Imported ===")
print("  model:    " .. info.world.model)
print("  prompt:   " .. info.casts[1].prompt)
print("  negative: " .. info.casts[1].negative)
print("  steps:    " .. info.sampler.steps .. "  cfg: " .. info.sampler.cfg)
print("  size:     " .. info.size[1] .. "x" .. info.size[2])

-- ============================================================
-- 2. DSLで再構築: 元画像をセマンティックに分解
-- ============================================================

-- World: 元画像と同じモデル
local w = vdsl.world { model = info.world.model }

-- キャラクター要素を Trait に分解
local girl      = vdsl.trait("1girl, solo")
local red_hair  = vdsl.trait("long flowing red hair, vibrant", 1.2)
local smile     = vdsl.trait("smiling, happy, expressive eyes")
local dress     = vdsl.trait("elegant white dress, flowing fabric")
local jewel     = vdsl.trait("crystal necklace, earrings")

-- 背景・雰囲気を Trait に分解
local sakura    = vdsl.trait("cherry blossoms, petals falling, spring")
local sunset    = vdsl.trait("sunset, golden hour, warm light", 1.1)
local park      = vdsl.trait("park path, trees, natural setting")

-- ネガティブ
local neg = vdsl.trait("worst quality, bad quality, simple background")
  + vdsl.trait("text, watermark, signature, username", 1.5)
  + vdsl.trait("monochrome")

-- Subject を合成
local heroine = vdsl.subject("masterpiece, best quality")
  :with(girl):with(red_hair):with(smile)
  :with(dress):with(jewel)
  :quality("high")

print("\n=== Reconstructed Subject ===")
print("  " .. heroine:resolve())

-- 忠実再現
local faithful = vdsl.render {
  world = w,
  cast  = { vdsl.cast { subject = heroine:with(sakura):with(sunset):with(park), negative = neg } },
  seed  = info.sampler.seed,
  steps = info.sampler.steps,
  cfg   = info.sampler.cfg,
  size  = info.size,
}
print("\n=== Faithful Rebuild: " .. faithful.graph:size() .. " nodes ===")

-- ============================================================
-- 3. 季節バリエーション: Trait 差し替えだけで世界が変わる
-- ============================================================

local seasons = {
  spring = sakura + vdsl.trait("bright green leaves, warm breeze"),
  summer = vdsl.trait("sunflowers, blue sky, hot summer day, cicadas, vivid green")
    + vdsl.trait("straw hat, sundress", 0.8),
  autumn = vdsl.trait("autumn leaves, red and gold, falling maple, cool breeze")
    + vdsl.trait("cozy sweater, scarf", 0.8),
  winter = vdsl.trait("snow, winter landscape, bare trees, cold breath, soft light")
    + vdsl.trait("fur coat, warm mittens", 0.8),
}

print("\n=== Seasonal Variations ===")
for name, season_trait in pairs(seasons) do
  local subj = heroine:with(season_trait)
  local r = vdsl.render {
    world = w,
    cast  = { vdsl.cast { subject = subj, negative = neg } },
    seed  = 42,
    steps = 25,
    cfg   = 5.5,
    size  = { 1024, 1024 },
    output = "season_" .. name,
  }
  print(string.format("  %-8s %d nodes  prompt: ...%s",
    name, r.graph:size(), subj:resolve():sub(-60)))
end

-- ============================================================
-- 4. スタイルバリエーション: anime theme の traits 活用
-- ============================================================

local anime = vdsl.themes.anime
local base_subj = heroine:with(sakura):with(sunset)

local style_variations = {
  { name = "cel",        trait = anime.traits.cel_shade },
  { name = "watercolor", trait = anime.traits.watercolor },
  { name = "ghibli",     trait = anime.traits.ghibli },
  { name = "retro90s",   trait = anime.traits.retro },
}

print("\n=== Style Variations (anime theme) ===")
for _, sv in ipairs(style_variations) do
  local subj = base_subj:with(sv.trait)
  local r = vdsl.render {
    world = w,
    theme = anime,
    cast  = { vdsl.cast { subject = subj, negative = neg } },
    seed  = 42,
    output = "style_" .. sv.name,
  }
  -- auto-post が hint から生成されたか確認
  local post_types = {}
  for _, node in pairs(r.prompt) do
    if node.class_type == "ColorCorrect" then post_types[#post_types + 1] = "color" end
    if node.class_type == "ImageSharpen" then post_types[#post_types + 1] = "sharpen" end
  end
  local auto = #post_types > 0 and table.concat(post_types, "+") or "none"
  print(string.format("  %-12s %d nodes  auto-post: %s",
    sv.name, r.graph:size(), auto))
end

-- ============================================================
-- 5. ムードバリエーション: cinema theme で照明演出
-- ============================================================

local cinema = vdsl.themes.cinema

print("\n=== Mood Variations (cinema theme as Cast) ===")
local moods = {
  { name = "golden",   trait = cinema.traits.golden_hour },
  { name = "blue",     trait = cinema.traits.blue_hour },
  { name = "dramatic", trait = cinema.traits.dramatic },
  { name = "neon",     trait = cinema.traits.neon },
}

for _, mood in ipairs(moods) do
  -- Multi-cast: キャラ + ムードを別Castに分離
  local r = vdsl.render {
    world = w,
    cast  = {
      vdsl.cast { subject = heroine:with(sakura), negative = neg },
      vdsl.cast { subject = mood.trait },  -- ムードCast
    },
    seed  = 42,
    steps = 28,
    cfg   = 6.0,
    size  = { 1024, 1024 },
    output = "mood_" .. mood.name,
  }
  local color_node = nil
  for _, node in pairs(r.prompt) do
    if node.class_type == "ColorCorrect" then color_node = node end
  end
  local grading = color_node
    and string.format("gamma=%.1f sat=%.1f", color_node.inputs.gamma or 1, color_node.inputs.saturation or 1)
    or "none"
  print(string.format("  %-10s %d nodes  grading: %s",
    mood.name, r.graph:size(), grading))
end

-- ============================================================
-- 6. ポスプロ品質パイプライン: hires + face + sharpen
-- ============================================================

local hq_portrait = vdsl.trait("portrait, face closeup, detailed eyes")
  :hint("face", { fidelity = 0.6 })
  :hint("hires", { scale = 1.5, denoise = 0.35 })

local subj_hq = vdsl.subject("masterpiece, best quality")
  :with(girl):with(red_hair):with(smile):with(dress)
  :with(hq_portrait)

-- auto_post=true (default): hints が自動で hires + face を生成
-- さらに明示 post は使わず hints に任せる → 全部 auto
local r_hq = vdsl.render {
  world = w,
  cast  = { vdsl.cast { subject = subj_hq, negative = neg } },
  seed  = 42,
  steps = 25,
  cfg   = 5.5,
  size  = { 1024, 1024 },
  output = "hq_portrait",
}

local hq_types = {}
for _, node in pairs(r_hq.prompt) do
  hq_types[node.class_type] = (hq_types[node.class_type] or 0) + 1
end
print("\n=== HQ Portrait Pipeline ===")
print("  nodes:          " .. r_hq.graph:size())
print("  KSampler:       " .. (hq_types["KSampler"] or 0) .. " (1st pass + hires)")
print("  LatentUpscale:  " .. (hq_types["LatentUpscaleBy"] or 0))
print("  FaceRestore:    " .. (hq_types["FaceRestoreWithModel"] or 0))
print("  Sharpen:        " .. (hq_types["ImageSharpen"] or 0))

-- ============================================================
-- 7. CFG スイープ: 同じシードで CFG だけ変える
-- ============================================================

print("\n=== CFG Sweep (same seed) ===")
local subj_sweep = heroine:with(sakura):with(sunset)
for _, cfg_val in ipairs({ 3.0, 5.5, 7.0, 9.0, 12.0 }) do
  local r = vdsl.render {
    world = w,
    cast  = { vdsl.cast { subject = subj_sweep, negative = neg } },
    seed  = 42,
    steps = 25,
    cfg   = cfg_val,
    size  = { 1024, 1024 },
    output = string.format("cfg_%.1f", cfg_val),
  }
  -- decode して確認
  local decoded = vdsl.decode(r.prompt)
  print(string.format("  cfg=%-5.1f  decoded_cfg=%.1f  nodes=%d",
    cfg_val, decoded.sampler.cfg, r.graph:size()))
end

-- ============================================================
-- 8. 髪色バリエーション: Trait 差し替え
-- ============================================================

local hair_colors = {
  red    = vdsl.trait("long flowing red hair, vibrant", 1.2),
  silver = vdsl.trait("long flowing silver hair, platinum, ethereal", 1.2),
  black  = vdsl.trait("long flowing black hair, glossy, raven", 1.2),
  blue   = vdsl.trait("long flowing blue hair, ocean blue, vivid", 1.2),
  pink   = vdsl.trait("long flowing pink hair, pastel, soft", 1.2),
}

print("\n=== Hair Color Sweep ===")
for color, hair_trait in pairs(hair_colors) do
  local subj = vdsl.subject("masterpiece, best quality")
    :with(girl):with(hair_trait):with(smile)
    :with(dress):with(sakura):with(sunset)
  local r = vdsl.render {
    world = w,
    cast  = { vdsl.cast { subject = subj, negative = neg } },
    seed  = 42, steps = 25, cfg = 5.5,
    size  = { 1024, 1024 },
    output = "hair_" .. color,
  }
  -- prompt text 確認
  local decoded = vdsl.decode(r.prompt)
  local prompt_snip = decoded.casts[1].prompt:sub(1, 70) .. "..."
  print(string.format("  %-8s %s", color, prompt_snip))
end

print("\n=== Done: all workflows generated ===")
