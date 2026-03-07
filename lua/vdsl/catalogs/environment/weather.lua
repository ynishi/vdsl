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

return Catalog.new {
  clear_sky = Trait.new("clear sky, blue sky, sunny")
    :hint("color", { brightness = 1.05 }),

  cloudy = Trait.new("cloudy sky, clouds, partly cloudy"),

  overcast = Trait.new("overcast sky, gray sky, cloud cover")
    :hint("color", { contrast = 0.9 }),

  rain = Trait.new("rain, rainy", 1.1)
    + Trait.new("rain drops, wet surfaces")
    :hint("color", { saturation = 0.9, contrast = 1.05 }),

  heavy_rain = Trait.new("heavy rain, downpour", 1.2)
    + Trait.new("torrential rain, water streaming")
    :hint("color", { saturation = 0.85, brightness = 0.9, contrast = 1.1 }),

  snow = Trait.new("snow, snowy, snowflakes, white landscape")
    :hint("color", { brightness = 1.1, saturation = 0.8 }),

  blizzard = Trait.new("blizzard, heavy snow", 1.2)
    + Trait.new("strong winds, whiteout")
    :hint("color", { brightness = 1.15, saturation = 0.7, contrast = 0.85 }),

  fog = Trait.new("fog, thick fog", 1.1)
    + Trait.new("low visibility, foggy atmosphere")
    :hint("color", { contrast = 0.8, saturation = 0.85 }),

  mist = Trait.new("mist, light mist, soft haze, misty")
    :hint("color", { contrast = 0.9 }),

  storm = Trait.new("storm, stormy sky", 1.1)
    + Trait.new("dark clouds, dramatic weather")
    :hint("color", { brightness = 0.85, contrast = 1.2 }),

  thunder = Trait.new("thunderstorm, lightning bolts", 1.2)
    + Trait.new("dark sky, thunder")
    :hint("color", { brightness = 0.8, contrast = 1.3 }),

  wind = Trait.new("windy, strong wind", 1.1)
    + Trait.new("windswept, hair blowing"),

  aurora = Trait.new("aurora borealis, northern lights", 1.1)
    + Trait.new("green and purple sky")
    :hint("color", { saturation = 1.3 }),

  rainbow = Trait.new("rainbow, rainbow in the sky", 1.1)
    + Trait.new("colorful arc"),
}
