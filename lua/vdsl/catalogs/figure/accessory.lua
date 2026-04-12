--- Catalog: Accessories.
-- Wearable accessory Traits for character description.
-- Target: SDXL 1.0 Base and above.
--
-- Color specification improves accuracy: "black gloves" > "gloves".
-- Specific types beat generic: "elbow gloves" > "gloves".
-- Place accessory tags early in prompt to avoid being ignored.
--
-- Reliability tiers (by Danbooru post count):
--   S (>500K): gloves, hat, hair_ribbon, hair_bow, earrings, hair_ornament
--   A (>100K): glasses, sunglasses, choker, necklace, headband, scarf, mask
--   B (mid freq): crown, eyepatch, goggles, beret (Illustrious/NoobAI stable)
--
-- Sources:
--   480+ Pony XL Hats/Masks/Props List (Civitai),
--   280+ Pony XL Clothing List (Civitai),
--   Danbooru2025 tag counts (HuggingFace dataproc5),
--   Crody's Illustrious/NoobAI Tips (Civitai).

local Trait   = require("vdsl.trait")
local Catalog = require("vdsl.catalog")

return Catalog.new {
  -- === Eyewear ===
  glasses    = Trait.new("glasses"):desc("wearing glasses"),
  sunglasses = Trait.new("sunglasses"):desc("wearing sunglasses"),
  eyepatch   = Trait.new("eyepatch"):desc("wearing an eyepatch"),
  goggles    = Trait.new("goggles"):desc("wearing goggles"),

  -- === Head / Hair ===
  headband      = Trait.new("headband"):desc("wearing a headband"),
  hair_ribbon   = Trait.new("hair ribbon"):desc("a ribbon tied in the hair"),
  hair_bow      = Trait.new("hair bow"):desc("a bow in the hair"),
  hair_ornament = Trait.new("hair ornament"):desc("a decorative hair ornament"),
  beret         = Trait.new("beret"):desc("wearing a beret"),
  crown         = Trait.new("crown"):desc("wearing a crown"),
  hood          = Trait.new("hood"):desc("wearing a hood"),
  witch_hat     = Trait.new("witch hat"):desc("wearing a pointed witch hat"),

  -- === Neck ===
  choker   = Trait.new("choker"):desc("wearing a choker around the neck"),
  necklace = Trait.new("necklace"):desc("wearing a necklace"),
  scarf    = Trait.new("scarf"):desc("wearing a scarf"),

  -- === Hands / Arms ===
  gloves            = Trait.new("gloves"):desc("wearing gloves"),
  fingerless_gloves = Trait.new("fingerless gloves"):desc("wearing fingerless gloves"),
  elbow_gloves      = Trait.new("elbow gloves"):desc("wearing long elbow-length gloves"),

  -- === Ears ===
  earrings = Trait.new("earrings"):desc("wearing earrings"),

  -- === Face ===
  mask = Trait.new("mask"):desc("wearing a mask"),
}
