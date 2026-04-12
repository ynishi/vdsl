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
  shirt          = Trait.new("shirt"):desc("wearing a shirt"),
  t_shirt        = Trait.new("t-shirt"):desc("wearing a t-shirt"),
  blouse         = Trait.new("blouse"):desc("wearing a blouse"),
  tank_top       = Trait.new("tank top"):desc("wearing a tank top"),
  hoodie         = Trait.new("hoodie"):desc("wearing a hoodie"),
  sweater        = Trait.new("sweater"):desc("wearing a sweater"),
  cardigan       = Trait.new("cardigan"):desc("wearing a cardigan"),
  crop_top       = Trait.new("crop top"):desc("wearing a crop top"),

  -- === Bottoms ===
  skirt          = Trait.new("skirt"):desc("wearing a skirt"),
  pleated_skirt  = Trait.new("pleated skirt"):desc("wearing a pleated skirt"),
  miniskirt      = Trait.new("miniskirt"):desc("wearing a miniskirt"),
  pants          = Trait.new("pants"):desc("wearing pants"),
  jeans          = Trait.new("jeans"):desc("wearing jeans"),
  shorts         = Trait.new("shorts"):desc("wearing shorts"),

  -- === Dress / One-piece ===
  dress          = Trait.new("dress"):desc("wearing a dress"),
  sundress       = Trait.new("sundress"):desc("wearing a sundress"),
  evening_gown   = Trait.new("evening gown"):desc("wearing an elegant evening gown"),
  wedding_dress  = Trait.new("wedding dress"):desc("wearing a wedding dress"),

  -- === Outerwear ===
  jacket         = Trait.new("jacket"):desc("wearing a jacket"),
  blazer         = Trait.new("blazer"):desc("wearing a blazer"),
  coat           = Trait.new("coat"):desc("wearing a coat"),

  -- === Uniforms ===
  -- school_uniform: 830K posts. Most stable uniform tag.
  school_uniform   = Trait.new("school uniform"):desc("wearing a school uniform"),
  -- serafuku: Danbooru standalone tag. Implies sailor_collar etc.
  serafuku         = Trait.new("serafuku"):desc("wearing a Japanese sailor-style school uniform"),
  military_uniform = Trait.new("military uniform"):desc("wearing a military uniform"),
  maid             = Trait.new("maid"):desc("wearing a maid outfit"),
  suit             = Trait.new("business suit"):desc("wearing a business suit"),

  -- === Traditional ===
  kimono        = Trait.new("kimono"):desc("wearing a traditional Japanese kimono"),
  yukata        = Trait.new("yukata"):desc("wearing a Japanese yukata"),
  chinese_dress = Trait.new("chinese dress"):desc("wearing a Chinese dress"),

  -- === Swimwear / Bodysuit ===
  swimsuit   = Trait.new("swimsuit"):desc("wearing a swimsuit"),
  bikini     = Trait.new("bikini"):desc("wearing a bikini"),
  leotard    = Trait.new("leotard"):desc("wearing a leotard"),

  -- === Armor ===
  -- full_armor causes joint distortion. Use part-based tags with ControlNet.
  armor          = Trait.new("armor"):desc("wearing armor"),
  shoulder_armor = Trait.new("shoulder armor"):desc("wearing shoulder armor"),
}
