--- Catalog: Clothing / Outfit.
-- Core clothing Traits for character description.
-- Target: SDXL 1.0 Base and above.
--
-- IMPORTANT (Illustrious/NoobAI):
--   Compound tags must be decomposed into individual tags.
--   "striped collared shirt" does NOT work.
--   Use "striped shirt, collared shirt" instead.
--   Source: Illustrious prompting guide v0.1 (Civitai).
--
-- Color specification improves accuracy: "white dress" > "dress".
--
-- Reliability tiers (by Danbooru post count):
--   S (>500K): shirt, skirt, dress, jacket, school_uniform, swimsuit
--   A (verified stable): kimono, armor, maid, hoodie, sweater, blazer, etc.
--
-- Sources:
--   280+ Pony XL Clothing List (Civitai),
--   Tips for Illustrious XL Prompting (Civitai),
--   Danbooru2025 tag counts (HuggingFace dataproc5),
--   Crody's Illustrious/NoobAI Tips (Civitai).

local Trait   = require("vdsl.trait")
local Catalog = require("vdsl.catalog")

return Catalog.new {
  -- === Tops ===
  shirt          = Trait.new("shirt"),
  t_shirt        = Trait.new("t-shirt"),
  blouse         = Trait.new("blouse"),
  tank_top       = Trait.new("tank top"),
  hoodie         = Trait.new("hoodie"),
  sweater        = Trait.new("sweater"),
  cardigan       = Trait.new("cardigan"),
  crop_top       = Trait.new("crop top"),

  -- === Bottoms ===
  skirt          = Trait.new("skirt"),
  pleated_skirt  = Trait.new("pleated skirt"),
  miniskirt      = Trait.new("miniskirt"),
  pants          = Trait.new("pants"),
  jeans          = Trait.new("jeans"),
  shorts         = Trait.new("shorts"),

  -- === Dress / One-piece ===
  dress          = Trait.new("dress"),
  sundress       = Trait.new("sundress"),
  evening_gown   = Trait.new("evening gown"),
  wedding_dress  = Trait.new("wedding dress"),

  -- === Outerwear ===
  jacket         = Trait.new("jacket"),
  blazer         = Trait.new("blazer"),
  coat           = Trait.new("coat"),

  -- === Uniforms ===
  -- school_uniform: 830K posts. Most stable uniform tag.
  school_uniform   = Trait.new("school uniform"),
  -- serafuku: Danbooru standalone tag. Implies sailor_collar etc.
  serafuku         = Trait.new("serafuku"),
  military_uniform = Trait.new("military uniform"),
  maid             = Trait.new("maid"),
  suit             = Trait.new("business suit"),

  -- === Traditional ===
  kimono        = Trait.new("kimono"),
  yukata        = Trait.new("yukata"),
  chinese_dress = Trait.new("chinese dress"),

  -- === Swimwear / Bodysuit ===
  swimsuit   = Trait.new("swimsuit"),
  bikini     = Trait.new("bikini"),
  leotard    = Trait.new("leotard"),

  -- === Armor ===
  -- full_armor causes joint distortion. Use part-based tags with ControlNet.
  armor          = Trait.new("armor"),
  shoulder_armor = Trait.new("shoulder armor"),
}
