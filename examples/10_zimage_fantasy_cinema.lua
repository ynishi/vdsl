--- 10_zimage_fantasy_cinema.lua: Z-Image Turbo — Fantasy Journey + Cinematic Duel
--
-- Part 1: 「幻想紀行」 — 4 epic fantasy landscapes
--   Sky City, Underwater Temple, Ice Throne, Volcano Forge
--
-- Part 2: 「龍殺しの侍」 — Cinematic storyboard (6 frames)
--   A lone samurai confronts an ancient dragon. Told in movie frames.
--
-- Run (compile only):
--   lua -e "package.path='lua/?.lua;lua/?/init.lua;'..package.path" examples/10_zimage_fantasy_cinema.lua
--
-- Run (compile + generate via vdsl_run MCP):
--   vdsl_run(script_file="examples/10_zimage_fantasy_cinema.lua", working_dir=".")

local vdsl   = require("vdsl")
local zimage = require("vdsl.compilers.zimage")
local C      = require("vdsl.catalogs")

-- ============================================================
-- World: Z-Image Turbo
-- ============================================================

local w = vdsl.world {
  model = "z_image_turbo_fp16.safetensors",
  vae   = "ae.safetensors",
}

local text_encoder = "qwen_3_4b_bf16.safetensors"

local scenes = {}

-- ============================================================
-- Part 1: 幻想紀行 — Fantasy Journey
-- ============================================================

-- 1-1: Sky City (空中都市)
scenes[#scenes + 1] = {
  name   = "fj_sky_city",
  prompt = "Vast floating city suspended among clouds at golden hour, massive stone islands connected by ancient bridges draped in hanging gardens, waterfalls cascading into the void below, airships with silk sails drifting between towers, warm light breaking through cloud layers, birds circling ornate spires, epic fantasy concept art, ultra detailed, matte painting quality",
  size   = { 1568, 672 },  -- ultra-wide panorama
  seed   = 10001,
}

-- 1-2: Underwater Temple (水中神殿)
scenes[#scenes + 1] = {
  name   = "fj_underwater_temple",
  prompt = "Ancient underwater temple submerged in crystalline turquoise ocean, massive stone columns covered in bioluminescent coral and sea anemones, shafts of sunlight piercing through the water surface above, a giant stone deity face half-buried in white sand, schools of tropical fish swirling around crumbling archways, god rays through water, ethereal blue-green color palette, cinematic wide shot",
  size   = { 1344, 768 },
  seed   = 10002,
}

-- 1-3: Ice Throne (氷の王座)
scenes[#scenes + 1] = {
  name   = "fj_ice_throne",
  prompt = vdsl.subject("colossal throne carved from a single glacier inside a vast ice cavern, aurora borealis visible through a crack in the ceiling, frozen waterfall behind the throne, intricate frost crystal patterns on every surface, a tiny cloaked figure standing before the throne emphasizing the impossible scale")
    :with(C.lighting.volumetric)
    :with(C.atmosphere.majestic),
  size   = { 832, 1248 },  -- vertical for towering scale
  seed   = 10003,
}

-- 1-4: Volcano Forge (溶岩の鍛冶場)
scenes[#scenes + 1] = {
  name   = "fj_volcano_forge",
  prompt = "Enormous dwarven forge built inside an active volcano caldera, rivers of molten lava flowing through stone channels, massive chain-driven hammers and anvils silhouetted against the orange glow, sparks flying from a white-hot blade being forged, stone bridges spanning over lava pools, smoke and embers rising into a red-lit cavern ceiling, dark fantasy industrial concept art, dramatic chiaroscuro lighting",
  size   = { 1344, 768 },
  seed   = 10004,
}

-- ============================================================
-- Part 2: 龍殺しの侍 — Cinematic Storyboard
-- A lone ronin samurai tracks and confronts an ancient dragon
-- in a ruined mountain temple. Six frames, one story.
-- ============================================================

-- 2-1: The Approach — 侍、霧の山道を登る
scenes[#scenes + 1] = {
  name   = "cs_01_approach",
  prompt = "Cinematic establishing shot, a lone samurai in weathered dark armor walking up a misty mountain path, ancient stone torii gates half-swallowed by fog and twisted pine trees, his katana on his back catching faint moonlight, distant rumble of thunder, muted earth tones with cold blue mist, 35mm anamorphic lens, film grain, Akira Kurosawa atmosphere",
  size   = { 1568, 672 },  -- 21:9 cinematic
  seed   = 20001,
}

-- 2-2: The Ruins — 崩壊した山頂の神殿
scenes[#scenes + 1] = {
  name   = "cs_02_ruins",
  prompt = "Wide shot of a massive ruined mountain temple at the peak, shattered stone pillars and crumbling walls, deep claw marks gouged into ancient stonework, scattered bones and broken weapons from previous challengers, ominous red glow emanating from deep within the ruins, storm clouds gathering above, foreboding atmosphere, dark fantasy cinematography, desaturated tones with selective red accent",
  size   = { 1344, 768 },
  seed   = 20002,
}

-- 2-3: The Awakening — 龍、目を開く
scenes[#scenes + 1] = {
  name   = "cs_03_awakening",
  prompt = "Extreme close-up of a massive dragon's eye slowly opening in darkness, the iris a molten gold with vertical slit pupil, ancient scarred scales surrounding the eye like cracked obsidian, a faint orange glow reflecting in the pupil — the silhouette of a man holding a sword, smoke curling from the dragon's nostril at the edge of frame, macro detail, cinematic shallow depth of field, terrifying and beautiful",
  size   = { 1344, 768 },
  seed   = 20003,
}

-- 2-4: The Confrontation — 対峙
scenes[#scenes + 1] = {
  name   = "cs_04_confrontation",
  prompt = vdsl.subject("samurai in dark lacquered armor standing motionless before an enormous ancient dragon in a destroyed temple courtyard, the dragon rearing up with wings spread wide blocking out the stormy sky, rain falling between them, the samurai's hand resting on his sheathed katana in iai-draw stance, tension before the first move")
    :with(C.camera.low_angle)
    :with(C.lighting.volumetric)
    :with(C.atmosphere.epic),
  size   = { 832, 1248 },  -- vertical to show dragon's height
  seed   = 20004,
}

-- 2-5: The Clash — 一閃
scenes[#scenes + 1] = {
  name   = "cs_05_clash",
  prompt = "Explosive action frame, the samurai mid-leap slashing his glowing katana in an arc of white-blue light, the dragon breathing a torrent of golden fire, the two forces colliding in the center of the frame sending shockwaves of sparks and flame, rain droplets frozen in the air, debris and stone fragments suspended mid-flight, speed lines implied by motion blur, dynamic diagonal composition, peak action moment, anime-influenced concept art with cinematic realism",
  size   = { 1344, 768 },
  seed   = 20005,
}

-- 2-6: The Aftermath — 静寂
scenes[#scenes + 1] = {
  name   = "cs_06_aftermath",
  prompt = "The samurai kneeling on one knee in the rain, katana planted in the ground before him, the massive dragon collapsed behind him with its head resting on broken pillars, a single beam of moonlight breaking through the parting storm clouds illuminating the scene, cherry blossom petals drifting impossibly through the rain, blood mixing with rainwater on ancient stone, quiet after the storm, melancholic beauty, wide shot, muted palette with silver moonlight accent",
  size   = { 1568, 672 },  -- ultra-wide for the quiet ending
  seed   = 20006,
}

-- ============================================================
-- Compile & emit
-- ============================================================

print("=== Z-Image Turbo: Fantasy Journey + Cinematic Duel ===")
print(string.format("  model: %s", w.model))
print(string.format("  scenes: %d\n", #scenes))

print("--- Part 1: 幻想紀行 ---")
for i = 1, 4 do
  local scene = scenes[i]
  local cast = vdsl.cast { subject = scene.prompt }
  local result = zimage.compile {
    world        = w,
    cast         = { cast },
    seed         = scene.seed,
    size         = scene.size,
    text_encoder = text_encoder,
    auto_post    = false,
  }
  vdsl.emit(scene.name, result)
  print(string.format("  %-24s %dx%d  seed=%d", scene.name, scene.size[1], scene.size[2], scene.seed))
end

print("\n--- Part 2: 龍殺しの侍 ---")
for i = 5, #scenes do
  local scene = scenes[i]
  local cast = vdsl.cast { subject = scene.prompt }
  local result = zimage.compile {
    world        = w,
    cast         = { cast },
    seed         = scene.seed,
    size         = scene.size,
    text_encoder = text_encoder,
    auto_post    = false,
  }
  vdsl.emit(scene.name, result)
  print(string.format("  %-24s %dx%d  seed=%d", scene.name, scene.size[1], scene.size[2], scene.seed))
end

print(string.format("\nDone. %d scenes compiled.", #scenes))
