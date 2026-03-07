--- Catalog: Palette / Color scheme / Temperature / Saturation.
-- Cross-cutting color Traits. SDXL-effective tags only.
-- Target: SDXL 1.0 Base and above.
--
-- These are independent of lighting/camera/subject. They control
-- the overall color impression of the generated image.
--
-- Note on lighting overlap:
--   Lighting catalog entries (golden_hour, neon, chiaroscuro) carry
--   color hints for light-specific corrections. Palette entries here
--   control "scene-level color intent" independent of lighting.
--   When both are present, the compiler merges hints (later wins).
--   This means palette hints may be overridden by lighting hints
--   or vice versa — the user controls ordering via :with() chains.
--
-- Sources:
--   onceuponanalgorithm.org color palette experiments,
--   artsmart.ai color theory guide, Segmind SDXL prompt guide,
--   PromptHero/Civitai community-tested prompts.

local Trait   = require("vdsl.trait")
local Catalog = require("vdsl.catalog")
local K       = Trait  -- tag key constants

return Catalog.new {
  -- === Temperature ===
  warm_tones = Trait.new("warm tones, warm color palette", 1.1)
    :hint("color", { gamma = 0.9, saturation = 1.1 })
    :tag(K.CONFLICTS, "cool tones"),

  cool_tones = Trait.new("cool tones, cool color palette", 1.1)
    :hint("color", { gamma = 1.1 })
    :tag(K.CONFLICTS, "warm tones"),

  -- === Saturation ===
  vibrant = Trait.new("vibrant colors", 1.1)
    :hint("color", { saturation = 1.2 })
    :tag(K.CONFLICTS, "desaturated, muted colors, monochrome, black and white"),

  muted = Trait.new("muted colors, muted tones")
    :hint("color", { saturation = 0.8 })
    :tag(K.CONFLICTS, "vibrant colors"),

  desaturated = Trait.new("desaturated, faded colors")
    :hint("color", { saturation = 0.6 })
    :tag(K.CONFLICTS, "vibrant colors"),

  pastel = Trait.new("pastel colors", 1.1)
    + Trait.new("soft tones, light palette")
    :hint("color", { saturation = 0.7, brightness = 1.05 }),

  -- === Monochrome / Special Schemes ===
  monochrome = Trait.new("monochrome", 1.1)
    :hint("color", { saturation = 0.0 })
    :tag(K.CONFLICTS, "vibrant colors"),

  black_and_white = Trait.new("black and white", 1.1)
    + Trait.new("high contrast monochrome")
    :hint("color", { saturation = 0.0, contrast = 1.1 })
    :tag(K.CONFLICTS, "vibrant colors"),

  sepia = Trait.new("sepia tones, rendered in sepia")
    :hint("color", { saturation = 0.15, gamma = 0.9 }),

  -- === Contrast ===
  high_contrast = Trait.new("high contrast")
    :hint("color", { contrast = 1.2 }),

  -- === Named Palettes ===
  earth_tones = Trait.new("earth tones, natural colors")
    + Trait.new("brown, beige, olive, warm neutrals")
    :hint("color", { saturation = 0.85, gamma = 0.95 }),

  jewel_tones = Trait.new("jewel tones")
    + Trait.new("rich deep colors, ruby, sapphire, emerald")
    :hint("color", { saturation = 1.25 }),

  -- === Color Theory ===
  limited_palette = Trait.new("limited color palette, restricted colors")
    :hint("color", { saturation = 0.9 }),

  complementary = Trait.new("complementary colors, color contrast")
    :hint("color", { saturation = 1.1, contrast = 1.1 }),
}
