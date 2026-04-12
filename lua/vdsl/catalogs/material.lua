--- Catalog: Material / Texture modifiers.
-- Surface material adjectives that compose with any subject or object.
-- These are modifier Traits — combine with clothing, environment, or props.
-- Target: SDXL 1.0 Base and above.
--
-- Usage:
--   catalogs.material.metallic          → metallic surface
--   catalogs.material.leather + "jacket" → leather jacket context
--
-- Note: material tags are more stable when paired with a concrete noun
-- (e.g. "silk dress" > "silk" alone).
--
-- Sources:
--   Segmind SDXL Prompt Guide, Civitai material tag analysis,
--   Danbooru tag taxonomy (general tags → materials).

local Trait   = require("vdsl.trait")
local Catalog = require("vdsl.catalog")

return Catalog.new {
  -- === Surface finish ===
  metallic = Trait.new("shiny clothes, metallic", 1.1)
    :desc("metallic shiny surface"),

  glossy = Trait.new("glossy, shiny surface")
    :desc("glossy shiny surface finish"),

  matte = Trait.new("matte, matte finish")
    :desc("matte non-reflective finish"),

  translucent = Trait.new("translucent, semi-transparent")
    :desc("translucent semi-transparent material"),

  -- === Fabric / organic ===
  leather = Trait.new("leather", 1.1)
    :desc("leather material"),

  silk = Trait.new("silk, silky")
    :desc("smooth silky fabric"),

  lace = Trait.new("lace, lace trim")
    :desc("delicate lace with lace trim"),

  denim = Trait.new("denim")
    :desc("denim fabric"),

  fur = Trait.new("fur trim")
    :desc("soft fur trim"),

  -- === Hard materials ===
  glass = Trait.new("glass, transparent glass")
    :desc("transparent glass material"),

  crystal = Trait.new("crystal, frozen, translucent, reflective surface", 1.1)
    :desc("translucent reflective crystal material"),

  wood = Trait.new("wood, wooden")
    :desc("wooden material with wood grain"),
}
