--- Catalog: Hue / Individual colors.
-- Specific color dominance Traits. SDXL-effective tags only.
-- Target: SDXL 1.0 Base and above.
--
-- Note on color control:
--   SDXL understands color names but placement control is imprecise.
--   "{color} color scheme" and "{color} tones" formats are most effective
--   for shifting overall image color. Single color names tend to be
--   interpreted as object colors rather than scene-wide tones.
--
--   Hex codes (#FF0000 etc.) do NOT work on SDXL.
--   Emphasis beyond 1.2 risks color artifacts.
--
-- Note on palette catalog:
--   color.palette covers schemes (monochrome, pastel, warm/cool).
--   color.hue covers specific color dominance/accents.
--   They are complementary: palette sets the "mode", hue sets the "key color".
--
-- Sources:
--   onceuponanalgorithm.org color experiments, artsmart.ai color theory,
--   HuggingFace SDXL latent space analysis, ColorPeel paper,
--   Civitai/PromptHero community-tested prompts.

local Trait   = require("vdsl.trait")
local Catalog = require("vdsl.catalog")

return Catalog.new {
  -- === Reds ===
  red = Trait.new("red color scheme, red tones", 1.1),

  crimson = Trait.new("crimson, deep crimson tones", 1.1),

  scarlet = Trait.new("scarlet, bright scarlet tones"),

  burgundy = Trait.new("burgundy, dark wine red", 1.1),

  -- === Blues ===
  blue = Trait.new("blue color scheme, blue tones", 1.1),

  navy = Trait.new("navy blue, dark navy tones", 1.1),

  azure = Trait.new("azure, sky blue, light azure"),

  teal = Trait.new("teal, blue-green, teal tones", 1.1),

  indigo = Trait.new("indigo, deep blue-violet"),

  -- === Greens ===
  green = Trait.new("green color scheme, green tones", 1.1),

  emerald = Trait.new("emerald green, rich emerald tones", 1.1),

  olive = Trait.new("olive green, muted olive tones"),

  mint = Trait.new("mint green, light green tones"),

  forest_green = Trait.new("forest green, deep green, dark green", 1.1),

  -- === Yellows / Golds ===
  yellow = Trait.new("yellow color scheme, bright yellow tones", 1.1),

  gold = Trait.new("golden, gold tones, warm gold", 1.1),

  amber = Trait.new("amber, warm amber tones", 1.1),

  -- === Purples ===
  purple = Trait.new("purple color scheme, purple tones", 1.1),

  violet = Trait.new("violet, deep violet tones"),

  lavender = Trait.new("light purple, soft lavender tones", 1.1),

  magenta = Trait.new("magenta, vivid magenta, pink-purple", 1.1),

  -- === Oranges / Pinks ===
  orange = Trait.new("orange color scheme, warm orange tones", 1.1),

  coral = Trait.new("coral pink, warm pinkish-orange tones"),

  pink = Trait.new("pink color scheme, soft pink tones", 1.1),

  peach = Trait.new("soft pink-orange, warm peach tones"),

  -- === Neutrals ===
  white = Trait.new("white, clean white, bright white"),

  black = Trait.new("black, deep black, dark"),

  silver = Trait.new("silver, silvery, metallic silver tones"),

  gray = Trait.new("gray tones, neutral gray, subdued"),

  ivory = Trait.new("ivory, warm white, cream white"),

  -- === Metallics ===
  gold_metallic = Trait.new("metallic gold, gold metallic surface", 1.1)
    + Trait.new("shiny gold"),

  silver_metallic = Trait.new("metallic silver, chrome", 1.1)
    + Trait.new("shiny silver surface"),

  copper = Trait.new("copper, copper metallic, warm metallic", 1.1),

  bronze = Trait.new("bronze, bronze metallic, aged metal"),
}
