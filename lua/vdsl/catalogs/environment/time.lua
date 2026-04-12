--- Catalog: Time / Time of Day / Season.
-- Temporal context Traits. SDXL-effective tags only.
-- Target: SDXL 1.0 Base and above.
--
-- Note on lighting overlap:
--   lighting.golden_hour and lighting.blue_hour exist for "light quality".
--   time.sunrise/sunset/dusk here set "temporal context" (sky color, sun position).
--   They are complementary: time sets WHEN, lighting sets HOW the light behaves.
--   Combining them (e.g., time.sunset + lighting.golden_hour) is valid and
--   produces additive effects.
--
-- Sources:
--   wolfden/ComfyUi_PromptStylers time-of-day JSON,
--   Civitai lighting-in-photographic-prompts article,
--   Aiarty SD lighting prompts, community consensus.

local Trait   = require("vdsl.trait")
local Catalog = require("vdsl.catalog")
local K       = Trait  -- tag key constants

return Catalog.new {
  -- === Time of Day ===
  dawn = Trait.new("dawn, early morning light", 1.1)
    + Trait.new("pre-sunrise, soft pastels")
    :hint("color", { brightness = 0.95, saturation = 1.05 })
    :tag(K.CONFLICTS, "midnight, deep night")
    :desc("dawn with soft pastel early morning light before sunrise"),

  sunrise = Trait.new("sunrise, rising sun", 1.1)
    + Trait.new("warm horizon, morning glow")
    :hint("color", { brightness = 1.05, saturation = 1.1 })
    :desc("sunrise with the sun rising over a warm glowing horizon"),

  morning = Trait.new("morning, morning light, daylight")
    :desc("morning daylight"),

  midday = Trait.new("midday, noon, bright sunlight, overhead sun")
    :hint("color", { brightness = 1.1, contrast = 1.1 })
    :tag(K.CONFLICTS, "nighttime, midnight")
    :desc("bright midday sunlight with the sun directly overhead"),

  afternoon = Trait.new("afternoon, warm daylight")
    :desc("warm afternoon daylight"),

  sunset = Trait.new("sunset, setting sun", 1.1)
    + Trait.new("orange sky, warm horizon")
    :hint("color", { saturation = 1.15 })
    :desc("sunset with the sun setting in an orange sky along the warm horizon"),

  dusk = Trait.new("dusk, fading light", 1.1)
    + Trait.new("evening sky, dimming")
    :hint("color", { brightness = 0.9, saturation = 1.05 })
    :desc("dusk with fading light and a dimming evening sky"),

  twilight = Trait.new("twilight, between day and night", 1.1)
    + Trait.new("purple sky, fading light")
    :hint("color", { saturation = 1.1 })
    :desc("twilight between day and night with a purple fading sky"),

  night = Trait.new("night, nighttime, dark sky")
    :hint("color", { brightness = 0.75, contrast = 1.1 })
    :tag(K.CONFLICTS, "midday, bright sunlight")
    :desc("nighttime under a dark sky"),

  midnight = Trait.new("midnight, deep night", 1.1)
    + Trait.new("pitch dark, starless")
    :hint("color", { brightness = 0.65, contrast = 1.15 })
    :tag(K.CONFLICTS, "midday, dawn")
    :desc("deep midnight darkness, pitch dark and starless"),

  moonlight = Trait.new("moonlit, moonlight", 1.1)
    + Trait.new("silvery light, moon in sky")
    :hint("color", { brightness = 0.8, saturation = 0.85 })
    :desc("moonlit scene bathed in silvery moonlight with the moon in the sky"),

  -- === Season (basic) ===
  spring = Trait.new("spring, cherry blossoms, fresh green, blooming flowers")
    :hint("color", { saturation = 1.1 })
    :desc("springtime with cherry blossoms, fresh green growth, and blooming flowers"),

  summer = Trait.new("summer, bright sunlight, lush greenery, warm")
    :hint("color", { brightness = 1.05, saturation = 1.05 })
    :desc("bright warm summer with lush greenery and sunlight"),

  autumn = Trait.new("autumn, fall foliage, orange and red leaves, golden")
    :hint("color", { saturation = 1.15 })
    :desc("autumn with golden fall foliage and orange and red leaves"),

  winter = Trait.new("winter, snow covered, bare trees, cold atmosphere")
    :hint("color", { brightness = 1.05, saturation = 0.8 })
    :desc("cold winter with snow-covered ground and bare trees"),

  -- === Season (detailed phenomena) ===
  cherry_blossom = Trait.new("cherry blossoms, sakura", 1.1)
    + Trait.new("pink petals, blooming cherry trees")
    :hint("color", { saturation = 1.1 })
    :desc("cherry blossom sakura trees in full bloom with pink petals"),

  wisteria = Trait.new("wisteria", 1.1)
    + Trait.new("hanging purple flowers, wisteria tunnel")
    :desc("wisteria with cascading hanging purple flowers"),

  sunflower_field = Trait.new("sunflower field", 1.1)
    + Trait.new("vast field of sunflowers, bright yellow")
    :desc("a vast field of bright yellow sunflowers"),

  fireflies = Trait.new("fireflies, glowing fireflies", 1.1)
    + Trait.new("bioluminescent, night insects")
    :desc("glowing fireflies floating in the night air"),

  fallen_leaves = Trait.new("fallen leaves, leaves on ground, autumn ground cover")
    :desc("fallen autumn leaves covering the ground"),

  maple_leaves = Trait.new("maple leaves, red maple", 1.1)
    + Trait.new("autumn maple tree")
    :hint("color", { saturation = 1.15 })
    :desc("vivid red maple leaves on autumn maple trees"),

  first_snow = Trait.new("first snow, light snowfall", 1.1)
    + Trait.new("snow on autumn leaves")
    :desc("the first light snowfall dusting autumn leaves"),

  winter_frost = Trait.new("frost, frosted surface", 1.1)
    + Trait.new("icy crystals, hoarfrost")
    :desc("frost and hoarfrost with delicate icy crystals on surfaces"),

  frozen_lake = Trait.new("frozen lake, ice covered lake", 1.1)
    + Trait.new("winter lake, ice surface")
    :desc("a frozen lake with a smooth ice surface"),

  -- === Season (weather crossover) ===
  spring_rain = Trait.new("spring rain, gentle rain", 1.1)
    + Trait.new("wet cherry blossoms, rain on flowers")
    :desc("gentle spring rain falling on cherry blossoms and flowers"),

  summer_thunder = Trait.new("summer thunderstorm", 1.2)
    + Trait.new("dark cumulonimbus, lightning, hot humid")
    :desc("a hot humid summer thunderstorm with dark cumulonimbus clouds and lightning"),

  autumn_wind = Trait.new("autumn wind, windswept leaves", 1.1)
    + Trait.new("swirling fallen leaves")
    :desc("autumn wind swirling fallen leaves through the air"),

  harvest_moon = Trait.new("harvest moon, large full moon", 1.1)
    + Trait.new("orange moon, moonlit night")
    :hint("color", { brightness = 0.85, saturation = 1.1 })
    :desc("a large orange harvest moon illuminating the night"),
}
