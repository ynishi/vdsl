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
  -- Experimental: anime finetunes may interpret as armor; photorealistic styles work better.
  metallic = Trait.new("shiny clothes, metallic", 1.1),

  glossy = Trait.new("glossy, shiny surface"),

  matte = Trait.new("matte, matte finish"),

  translucent = Trait.new("translucent, semi-transparent"),

  -- === Fabric / organic ===
  leather = Trait.new("leather", 1.1),

  silk = Trait.new("silk, silky"),

  lace = Trait.new("lace, lace trim"),

  denim = Trait.new("denim"),

  fur = Trait.new("fur trim"),

  -- === Hard materials ===
  -- Experimental: character context works well; scene context may generate objects.
  glass = Trait.new("glass, transparent glass"),

  -- Experimental: character context works well; scene context may generate objects.
  crystal = Trait.new("crystal, frozen, translucent, reflective surface", 1.1),

  wood = Trait.new("wood, wooden"),
}
