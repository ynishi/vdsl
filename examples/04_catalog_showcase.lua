--- 04_catalog_showcase.lua: Built-in catalog walkthrough
-- Demonstrates every catalog category with a unified character base.
-- No server required.
--
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;'..package.path" examples/04_catalog_showcase.lua

local vdsl = require("vdsl")
local C = vdsl.catalogs

local w = vdsl.world { clip_skip = 2 }

local neg = C.quality.neg_default + C.quality.neg_anatomy + C.quality.neg_face

local base = vdsl.subject("1girl, solo")
  :with(vdsl.trait("black hair, long hair, wavy hair, purple eyes"))
  :with(C.quality.high)

-- ============================================================
-- Helper
-- ============================================================

local total = 0

local function section(title, tests, size)
  size = size or { 832, 1216 }
  print(string.format("\n--- %s (%d shots) ---", title, #tests))
  for _, t in ipairs(tests) do
    local subject = base:with(t.trait)
    local result = vdsl.render {
      world = w,
      cast  = { vdsl.cast { subject = subject, negative = neg } },
      seed  = 9000 + total,
      steps = 20,
      cfg   = 6.0,
      size  = size,
    }
    vdsl.emit(t.name, result)
    total = total + 1

    local tokens = #subject:resolve():gsub("[^,]", "") + 1
    print(string.format("  [%2d] %-25s %2d nodes  ~%d tokens",
      total, t.name, result.graph:size(), tokens))
  end
end

-- ============================================================
-- Catalog sections
-- ============================================================

print("=== Catalog Showcase ===")
print(string.format("  model: %s", w.model))

section("Style", {
  { name = "style_anime",      trait = C.style.anime + C.camera.bust_shot },
  { name = "style_cinematic",  trait = C.style.cinematic + C.camera.medium_shot },
  { name = "style_oil",        trait = C.style.oil + C.camera.bust_shot },
  { name = "style_watercolor", trait = C.style.watercolor + C.camera.bust_shot },
  { name = "style_photo",      trait = C.style.photo + C.camera.portrait_lens },
})

section("Camera", {
  { name = "cam_closeup",    trait = C.camera.closeup },
  { name = "cam_bust",       trait = C.camera.bust_shot },
  { name = "cam_cowboy",     trait = C.camera.cowboy_shot },
  { name = "cam_full_body",  trait = C.camera.full_body + C.figure.pose.standing },
  { name = "cam_low_angle",  trait = C.camera.low_angle + C.camera.full_body },
  { name = "cam_dutch",      trait = C.camera.dutch_angle + C.camera.cowboy_shot },
})

section("Lighting", {
  { name = "light_golden",     trait = C.lighting.golden_hour + C.camera.bust_shot },
  { name = "light_blue_hour",  trait = C.lighting.blue_hour + C.camera.bust_shot },
  { name = "light_neon",       trait = C.lighting.neon + C.camera.bust_shot },
  { name = "light_rembrandt",  trait = C.lighting.rembrandt + C.camera.bust_shot },
  { name = "light_chiaroscuro",trait = C.lighting.chiaroscuro + C.camera.bust_shot },
  { name = "light_volumetric", trait = C.lighting.volumetric + C.camera.cowboy_shot },
})

section("Effect", {
  { name = "fx_bloom",       trait = C.effect.bloom + C.lighting.backlit + C.camera.bust_shot },
  { name = "fx_film_grain",  trait = C.effect.film_grain + C.lighting.golden_hour + C.camera.bust_shot },
  { name = "fx_lens_flare",  trait = C.effect.lens_flare + C.lighting.backlit + C.camera.cowboy_shot },
  { name = "fx_motion_blur", trait = C.effect.motion_blur + C.figure.pose.running + C.camera.full_body },
})

section("Pose + Expression", {
  { name = "pose_standing_smile",  trait = C.figure.pose.standing + C.figure.expression.smile + C.camera.full_body },
  { name = "pose_sitting_gentle",  trait = C.figure.pose.sitting + C.figure.expression.gentle_smile + C.camera.medium_shot },
  { name = "pose_fighting_angry",  trait = C.figure.pose.fighting_stance + C.figure.expression.angry + C.camera.full_body },
  { name = "pose_dancing_happy",   trait = C.figure.pose.dancing + C.figure.expression.happy + C.camera.full_body },
})

section("Environment + Weather", {
  { name = "env_forest_fog",     trait = C.environment.setting.forest + C.environment.weather.fog + C.camera.wide_shot },
  { name = "env_city_rain_night", trait = C.environment.setting.city_street + C.environment.weather.rain + C.environment.time.night + C.camera.full_body },
  { name = "env_beach_sunset",    trait = C.environment.setting.beach + C.environment.time.sunset + C.camera.wide_shot },
  { name = "env_cyberpunk_neon",  trait = C.environment.setting.cyberpunk_city + C.lighting.neon + C.environment.time.night + C.camera.full_body },
}, { 1216, 832 })

section("Color Palette", {
  { name = "color_warm",      trait = C.color.palette.warm_tones + C.camera.bust_shot },
  { name = "color_cool",      trait = C.color.palette.cool_tones + C.camera.bust_shot },
  { name = "color_pastel",    trait = C.color.palette.pastel + C.camera.bust_shot },
  { name = "color_monochrome",trait = C.color.palette.monochrome + C.camera.bust_shot },
})

-- ============================================================
-- Summary
-- ============================================================

print(string.format("\n=== Summary: %d shots compiled across all catalog categories ===", total))
