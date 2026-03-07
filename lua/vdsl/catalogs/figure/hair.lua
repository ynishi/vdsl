--- Catalog: Hair attributes.
-- Hair color, length, and style Traits for character description.
-- Compose freely: hair.blonde + hair.long + hair.ponytail
-- Target: SDXL 1.0 Base and above.
--
-- Fantasy colors (blue, pink, green) work on base SDXL but are
-- significantly more stable on anime finetunes (Illustrious, Pony).
--
-- Sources:
--   Civitai 320+ Pony XL hairstyles, OpenArt hair color guide,
--   Aiarty hairstyle prompts, Danbooru hair tag taxonomy.

local Trait   = require("vdsl.trait")
local Catalog = require("vdsl.catalog")

return Catalog.new {
  -- === Color ===
  black   = Trait.new("black hair"),
  brown   = Trait.new("brown hair"),
  blonde  = Trait.new("blonde hair"),
  red     = Trait.new("red hair"),
  white   = Trait.new("white hair"),
  silver  = Trait.new("silver hair"),
  grey    = Trait.new("grey hair"),
  blue    = Trait.new("blue hair"),
  pink    = Trait.new("pink hair"),
  green   = Trait.new("green hair"),
  purple  = Trait.new("purple hair"),

  -- === Length ===
  short      = Trait.new("short hair"),
  medium     = Trait.new("medium hair"),
  long       = Trait.new("long hair"),
  very_long  = Trait.new("very long hair"),

  -- === Style ===
  ponytail   = Trait.new("ponytail"),
  twintails  = Trait.new("twintails"),
  braid      = Trait.new("braid"),
  bob_cut    = Trait.new("bob cut"),
  straight   = Trait.new("straight hair"),
  wavy       = Trait.new("wavy hair"),
  curly      = Trait.new("curly hair"),
  messy      = Trait.new("messy hair"),
  hair_bun   = Trait.new("hair bun"),
  bangs      = Trait.new("bangs"),
  side_ponytail = Trait.new("side ponytail"),
  hime_cut   = Trait.new("hime cut"),
  ahoge      = Trait.new("ahoge"),

  -- === Face-framing (portrait composition control) ===
  -- Bangs variants control forehead/eye visibility.
  -- Sidelocks/hair_over_one_eye control facial outline framing.
  -- Source: closeup_portrait_research.md Section 7.
  blunt_bangs       = Trait.new("blunt bangs"),
  swept_bangs       = Trait.new("swept bangs"),
  parted_bangs      = Trait.new("parted bangs"),
  sidelocks         = Trait.new("sidelocks"),
  hair_over_one_eye = Trait.new("hair over one eye"),
  hair_between_eyes = Trait.new("hair between eyes"),

  -- === Texture / motion ===
  shiny_hair    = Trait.new("shiny hair"),
  floating_hair = Trait.new("floating hair"),
}
