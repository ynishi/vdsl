--- Catalog: Lighting setups.
-- Natural, studio, and atmospheric lighting Traits.
-- Color hints drive auto-Post grading to match the lighting mood.
-- Target: SDXL and above.
--
-- Lighting is one of SDXL's strongest domains. Studio technique names
-- (Rembrandt, butterfly) work best paired with descriptive supplements.

local Trait   = require("vdsl.trait")
local Catalog = require("vdsl.catalog")
local K       = Trait  -- tag key constants

return Catalog.new {
  -- === Natural light ===
  golden_hour = Trait.new("golden hour", 1.1)
    + Trait.new("warm sunlight, long shadows, sunset glow")
    :hint("color", { brightness = 1.05, saturation = 1.1, gamma = 0.9 })
    :tag(K.CONFLICTS, "blue hour")
    :desc("golden hour warm sunlight with long shadows and a soft sunset glow"),

  blue_hour = Trait.new("blue hour", 1.1)
    + Trait.new("twilight, cool ambient light, dusk")
    :hint("color", { saturation = 1.15, gamma = 1.1 })
    :tag(K.CONFLICTS, "golden hour")
    :desc("blue hour twilight with cool ambient light and dusky atmosphere"),

  overcast = Trait.new("overcast, soft diffused light, even illumination")
    :hint("color", { contrast = 0.9 })
    :tag(K.CONFLICTS, "harsh sunlight")
    :desc("overcast sky with soft diffused light and even illumination"),

  harsh_sun = Trait.new("harsh sunlight", 1.1)
    + Trait.new("strong shadows, high contrast, midday")
    :hint("color", { contrast = 1.15 })
    :tag(K.CONFLICTS, "overcast")
    :desc("harsh midday sunlight casting strong shadows with high contrast"),

  backlit = Trait.new("backlit", 1.1)
    + Trait.new("rim light, silhouette edge, lens flare")
    :desc("backlit subject with rim light outlining the silhouette and subtle lens flare"),

  dappled = Trait.new("sunlight filtering through leaves, dappled light, natural shadow patterns")
    :desc("dappled sunlight filtering through tree leaves creating natural shadow patterns"),

  -- === Studio setups ===
  soft_studio = Trait.new("studio lighting", 1.1)
    + Trait.new("soft key light, fill light, diffused")
    :hint("color", { brightness = 1.02 })
    :desc("soft diffused studio lighting with balanced key and fill lights"),

  rembrandt = Trait.new("Rembrandt lighting", 1.1)
    + Trait.new("triangle shadow on cheek, side key light, dramatic")
    :hint("color", { contrast = 1.1 })
    :desc("Rembrandt-style lighting with a triangle shadow on one cheek from a dramatic side key light"),

  butterfly = Trait.new("butterfly lighting", 1.1)
    + Trait.new("overhead key light, shadow under nose, glamour")
    :desc("butterfly glamour lighting from above casting a small shadow under the nose"),

  split = Trait.new("split lighting, half face illuminated, half face in shadow, dramatic")
    :desc("dramatic split lighting with one half of the face illuminated and the other in deep shadow"),

  loop = Trait.new("loop lighting", 1.1)
    + Trait.new("small shadow beside nose, soft directional light")
    :desc("loop lighting with a soft directional light casting a small shadow beside the nose"),

  rim_light = Trait.new("rim lighting", 1.1)
    + Trait.new("edge light, glowing outline, backlit")
    :hint("color", { contrast = 1.05 })
    :desc("rim lighting creating a glowing outline around the subject's edges"),

  ring_light = Trait.new("ring light, even facial illumination, catch light in eyes")
    :desc("ring light providing even facial illumination with circular catchlights in the eyes"),

  -- === Atmospheric ===
  volumetric = Trait.new("volumetric lighting", 1.1)
    + Trait.new("god rays, light shafts, atmospheric haze")
    :desc("volumetric god rays and light shafts piercing through atmospheric haze"),

  neon = Trait.new("neon lighting", 1.1)
    + Trait.new("vivid colored light, cyberpunk, night scene")
    :hint("color", { saturation = 1.3, contrast = 1.1 })
    :desc("vivid neon lighting casting colorful reflections in a night scene"),

  candlelight = Trait.new("candlelight, warm glow, low light, intimate")
    :hint("color", { saturation = 1.1, gamma = 0.85 })
    :desc("warm candlelight glow in an intimate low-light setting"),

  chiaroscuro = Trait.new("chiaroscuro", 1.2)
    + Trait.new("dramatic contrast, deep shadows, dark background")
    :hint("color", { contrast = 1.3, saturation = 0.7 })
    :tag(K.CONFLICTS, "high key lighting")
    :desc("dramatic chiaroscuro with deep shadows against a dark background and strong contrast"),

  high_key = Trait.new("high key lighting, bright, minimal shadows, clean")
    :hint("color", { brightness = 1.1, contrast = 0.85 })
    :tag(K.CONFLICTS, "low key lighting, chiaroscuro")
    :desc("bright high-key lighting with minimal shadows and a clean airy look"),

  low_key = Trait.new("low key lighting", 1.1)
    + Trait.new("dark, moody, deep blacks")
    :hint("color", { brightness = 0.9, contrast = 1.2 })
    :tag(K.CONFLICTS, "high key lighting")
    :desc("dark moody low-key lighting with deep blacks and selective illumination"),

  spotlight = Trait.new("spotlight", 1.1)
    + Trait.new("single beam of light, isolated illumination, dark surroundings")
    :hint("color", { contrast = 1.2, brightness = 0.9 })
    :desc("single spotlight beam isolating the subject against dark surroundings"),
}
