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
local K       = Trait  -- tag key constants

return Catalog.new {
  -- === Color ===
  -- Color bleeding: hair color may leak into eyes/clothing on SDXL base.
  -- Mitigation: place hair color BEFORE eye/clothing color in prompt.
  -- Source: Fooocus issue #2205, Civitai Illustrious/NoobAI Tips.
  black   = Trait.new("black hair"),
  brown   = Trait.new("brown hair"),
  blonde  = Trait.new("blonde hair")
    :tag(K.CONFLICTS, "blue eyes"),  -- strong blonde bias with blue_eyes on SDXL base
  red     = Trait.new("red hair")
    :tag(K.CONFLICTS, "red eyes"),  -- color bleeding between hair and eyes
  white   = Trait.new("white hair")
    :tag(K.CONFLICTS, "silver hair"),  -- visually indistinguishable on many seeds
  silver  = Trait.new("silver hair")
    :tag(K.CONFLICTS, "white hair"),
  grey    = Trait.new("grey hair"),
  blue    = Trait.new("blue hair")
    :tag(K.CONFLICTS, "blue eyes"),  -- color bleeding
  pink    = Trait.new("pink hair")
    :tag(K.CONFLICTS, "pink eyes"),
  green   = Trait.new("green hair")
    :tag(K.CONFLICTS, "green eyes"),
  purple  = Trait.new("purple hair")
    :tag(K.CONFLICTS, "purple eyes"),  -- poor color separation

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
