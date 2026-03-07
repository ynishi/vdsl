--- Catalog: Lighting setups.
-- Natural, studio, and atmospheric lighting Traits.
-- Color hints drive auto-Post grading to match the lighting mood.
-- Target: SDXL and above.
--
-- Lighting is one of SDXL's strongest domains. Studio technique names
-- (Rembrandt, butterfly) work best paired with descriptive supplements.

local Trait   = require("vdsl.trait")
local Catalog = require("vdsl.catalog")

return Catalog.new {
  -- === Natural light ===
  golden_hour = Trait.new("golden hour", 1.1)
    + Trait.new("warm sunlight, long shadows, sunset glow")
    :hint("color", { brightness = 1.05, saturation = 1.1, gamma = 0.9 }),

  blue_hour = Trait.new("blue hour", 1.1)
    + Trait.new("twilight, cool ambient light, dusk")
    :hint("color", { saturation = 1.15, gamma = 1.1 }),

  overcast = Trait.new("overcast, soft diffused light, even illumination")
    :hint("color", { contrast = 0.9 }),

  harsh_sun = Trait.new("harsh sunlight", 1.1)
    + Trait.new("strong shadows, high contrast, midday")
    :hint("color", { contrast = 1.15 }),

  backlit = Trait.new("backlit", 1.1)
    + Trait.new("rim light, silhouette edge, lens flare"),

  dappled = Trait.new("sunlight filtering through leaves, dappled light, natural shadow patterns"),

  -- === Studio setups ===
  soft_studio = Trait.new("studio lighting", 1.1)
    + Trait.new("soft key light, fill light, diffused")
    :hint("color", { brightness = 1.02 }),

  rembrandt = Trait.new("Rembrandt lighting", 1.1)
    + Trait.new("triangle shadow on cheek, side key light, dramatic")
    :hint("color", { contrast = 1.1 }),

  butterfly = Trait.new("butterfly lighting", 1.1)
    + Trait.new("overhead key light, shadow under nose, glamour"),

  split = Trait.new("split lighting, half face illuminated, half face in shadow, dramatic"),

  loop = Trait.new("loop lighting", 1.1)
    + Trait.new("small shadow beside nose, soft directional light"),

  rim_light = Trait.new("rim lighting", 1.1)
    + Trait.new("edge light, glowing outline, backlit")
    :hint("color", { contrast = 1.05 }),

  ring_light = Trait.new("ring light, even facial illumination, catch light in eyes"),

  -- === Atmospheric ===
  volumetric = Trait.new("volumetric lighting", 1.1)
    + Trait.new("god rays, light shafts, atmospheric haze"),

  neon = Trait.new("neon lighting", 1.1)
    + Trait.new("vivid colored light, cyberpunk, night scene")
    :hint("color", { saturation = 1.3, contrast = 1.1 }),

  candlelight = Trait.new("candlelight, warm glow, low light, intimate")
    :hint("color", { saturation = 1.1, gamma = 0.85 }),

  chiaroscuro = Trait.new("chiaroscuro", 1.2)
    + Trait.new("dramatic contrast, deep shadows, dark background")
    :hint("color", { contrast = 1.3, saturation = 0.7 }),

  high_key = Trait.new("high key lighting, bright, minimal shadows, clean")
    :hint("color", { brightness = 1.1, contrast = 0.85 }),

  low_key = Trait.new("low key lighting", 1.1)
    + Trait.new("dark, moody, deep blacks")
    :hint("color", { brightness = 0.9, contrast = 1.2 }),

  spotlight = Trait.new("spotlight", 1.1)
    + Trait.new("single beam of light, isolated illumination, dark surroundings")
    :hint("color", { contrast = 1.2, brightness = 0.9 }),
}
