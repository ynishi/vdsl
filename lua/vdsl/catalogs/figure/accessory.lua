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
  -- glasses: may be ignored on long prompts in SDXL base.
  -- Place early or use (glasses:1.2).
  -- Source: SDXL 1.0 Prompt Guide (yeschat.ai).
  glasses    = Trait.new("glasses"),
  sunglasses = Trait.new("sunglasses"),
  eyepatch   = Trait.new("eyepatch"),
  goggles    = Trait.new("goggles"),

  -- === Head / Hair ===
  -- hat: generic. Use specific types for better results.
  headband      = Trait.new("headband"),
  hair_ribbon   = Trait.new("hair ribbon"),
  hair_bow      = Trait.new("hair bow"),
  hair_ornament = Trait.new("hair ornament"),
  beret         = Trait.new("beret"),
  crown         = Trait.new("crown"),
  hood          = Trait.new("hood"),
  witch_hat     = Trait.new("witch hat"),

  -- === Neck ===
  choker   = Trait.new("choker"),
  necklace = Trait.new("necklace"),
  scarf    = Trait.new("scarf"),

  -- === Hands / Arms ===
  -- gloves: also reduces hand-drawing artifacts.
  -- Color specification recommended.
  gloves            = Trait.new("gloves"),
  fingerless_gloves = Trait.new("fingerless gloves"),
  elbow_gloves      = Trait.new("elbow gloves"),

  -- === Ears ===
  earrings = Trait.new("earrings"),

  -- === Face ===
  mask = Trait.new("mask"),
}
