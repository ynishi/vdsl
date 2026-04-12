--- Catalog: Weather / Atmospheric conditions.
-- Meteorological Traits. SDXL-effective tags only.
-- Target: SDXL 1.0 Base and above.
--
-- Note on lighting overlap:
--   lighting.overcast exists for "light quality" control.
--   weather.overcast here focuses on "sky/atmosphere" visuals.
--   They can be combined but may produce redundant prompt tokens.
--
-- Sources:
--   Avaray/stable-diffusion-simple-wildcards weather (61 entries),
--   wolfden/ComfyUi_PromptStylers environment JSON,
--   PromptHero weather prompts, community A/B testing.

local Trait   = require("vdsl.trait")
local Catalog = require("vdsl.catalog")
local K       = Trait  -- tag key constants

return Catalog.new {
  clear_sky = Trait.new("clear sky, blue sky, sunny")
    :hint("color", { brightness = 1.05 })
    :tag(K.CONFLICTS, "storm, heavy rain, blizzard, thick fog")
    :desc("clear blue sunny sky"),

  cloudy = Trait.new("cloudy sky, clouds, partly cloudy")
    :desc("partly cloudy sky with scattered clouds"),

  overcast = Trait.new("overcast sky, gray sky, cloud cover")
    :hint("color", { contrast = 0.9 })
    :desc("overcast gray sky with heavy cloud cover"),

  rain = Trait.new("rain, rainy", 1.1)
    + Trait.new("rain drops, wet surfaces")
    :hint("color", { saturation = 0.9, contrast = 1.05 })
    :desc("rain falling with raindrops and wet glistening surfaces"),

  heavy_rain = Trait.new("heavy rain, downpour", 1.2)
    + Trait.new("torrential rain, water streaming")
    :hint("color", { saturation = 0.85, brightness = 0.9, contrast = 1.1 })
    :tag(K.CONFLICTS, "clear sky")
    :desc("torrential downpour of heavy rain with water streaming everywhere"),

  snow = Trait.new("snow, snowy, snowflakes, white landscape")
    :hint("color", { brightness = 1.1, saturation = 0.8 })
    :desc("snow falling with snowflakes covering the landscape in white"),

  blizzard = Trait.new("blizzard, heavy snow", 1.2)
    + Trait.new("strong winds, whiteout")
    :hint("color", { brightness = 1.15, saturation = 0.7, contrast = 0.85 })
    :tag(K.CONFLICTS, "clear sky")
    :desc("fierce blizzard with heavy snow and strong winds in near whiteout conditions"),

  fog = Trait.new("fog, thick fog", 1.1)
    + Trait.new("low visibility, foggy atmosphere")
    :hint("color", { contrast = 0.8, saturation = 0.85 })
    :tag(K.CONFLICTS, "clear sky")
    :desc("thick fog with low visibility and a hazy foggy atmosphere"),

  mist = Trait.new("mist, light mist, soft haze, misty")
    :hint("color", { contrast = 0.9 })
    :desc("light mist with a soft haze in the air"),

  storm = Trait.new("storm, stormy sky", 1.1)
    + Trait.new("dark clouds, dramatic weather")
    :hint("color", { brightness = 0.85, contrast = 1.2 })
    :tag(K.CONFLICTS, "clear sky")
    :desc("stormy sky with dark dramatic clouds"),

  thunder = Trait.new("thunderstorm, lightning bolts", 1.2)
    + Trait.new("dark sky, thunder")
    :hint("color", { brightness = 0.8, contrast = 1.3 })
    :desc("thunderstorm with lightning bolts flashing across a dark sky"),

  wind = Trait.new("windy, strong wind", 1.1)
    + Trait.new("windswept, hair blowing")
    :desc("strong wind blowing with windswept hair and movement"),

  aurora = Trait.new("aurora borealis, northern lights", 1.1)
    + Trait.new("green and purple sky")
    :hint("color", { saturation = 1.3 })
    :desc("aurora borealis northern lights shimmering in green and purple across the sky"),

  rainbow = Trait.new("rainbow, rainbow in the sky", 1.1)
    + Trait.new("colorful arc")
    :desc("a colorful rainbow arching across the sky"),
}
