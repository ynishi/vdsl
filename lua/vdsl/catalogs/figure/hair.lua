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
  black   = Trait.new("black hair"):desc("black hair"),
  brown   = Trait.new("brown hair"):desc("brown hair"),
  blonde  = Trait.new("blonde hair")
    :tag(K.CONFLICTS, "blue eyes")
    :desc("blonde hair"),
  red     = Trait.new("red hair")
    :tag(K.CONFLICTS, "red eyes")
    :desc("red hair"),
  white   = Trait.new("white hair")
    :tag(K.CONFLICTS, "silver hair")
    :desc("white hair"),
  silver  = Trait.new("silver hair")
    :tag(K.CONFLICTS, "white hair")
    :desc("silver hair"),
  grey    = Trait.new("grey hair"):desc("grey hair"),
  blue    = Trait.new("blue hair")
    :tag(K.CONFLICTS, "blue eyes")
    :desc("blue hair"),
  pink    = Trait.new("pink hair")
    :tag(K.CONFLICTS, "pink eyes")
    :desc("pink hair"),
  green   = Trait.new("green hair")
    :tag(K.CONFLICTS, "green eyes")
    :desc("green hair"),
  purple  = Trait.new("purple hair")
    :tag(K.CONFLICTS, "purple eyes")
    :desc("purple hair"),

  -- === Length ===
  short      = Trait.new("short hair"):desc("short hair"),
  medium     = Trait.new("medium hair"):desc("medium-length hair"),
  long       = Trait.new("long hair"):desc("long hair"),
  very_long  = Trait.new("very long hair"):desc("very long hair reaching past the waist"),

  -- === Style ===
  ponytail   = Trait.new("ponytail"):desc("hair tied in a ponytail"),
  twintails  = Trait.new("twintails"):desc("hair styled in twintails"),
  braid      = Trait.new("braid"):desc("hair in a braid"),
  bob_cut    = Trait.new("bob cut"):desc("bob cut hairstyle"),
  straight   = Trait.new("straight hair"):desc("straight hair"),
  wavy       = Trait.new("wavy hair"):desc("wavy hair"),
  curly      = Trait.new("curly hair"):desc("curly hair"),
  messy      = Trait.new("messy hair"):desc("messy tousled hair"),
  hair_bun   = Trait.new("hair bun"):desc("hair tied in a bun"),
  bangs      = Trait.new("bangs"):desc("hair with bangs"),
  side_ponytail = Trait.new("side ponytail"):desc("hair in a side ponytail"),
  hime_cut   = Trait.new("hime cut"):desc("traditional hime cut hairstyle with straight bangs and sidelocks"),
  ahoge      = Trait.new("ahoge"):desc("a single stray strand of hair sticking up"),

  -- === Face-framing (portrait composition control) ===
  -- Bangs variants control forehead/eye visibility.
  -- Sidelocks/hair_over_one_eye control facial outline framing.
  -- Source: closeup_portrait_research.md Section 7.
  blunt_bangs       = Trait.new("blunt bangs"):desc("blunt-cut straight bangs"),
  swept_bangs       = Trait.new("swept bangs"):desc("bangs swept to one side"),
  parted_bangs      = Trait.new("parted bangs"):desc("bangs parted in the center"),
  sidelocks         = Trait.new("sidelocks"):desc("long sidelocks framing the face"),
  hair_over_one_eye = Trait.new("hair over one eye"):desc("hair falling over one eye"),
  hair_between_eyes = Trait.new("hair between eyes"):desc("strands of hair falling between the eyes"),

  -- === Texture / motion ===
  shiny_hair    = Trait.new("shiny hair"):desc("glossy shiny hair with light reflections"),
  floating_hair = Trait.new("floating hair"):desc("hair floating weightlessly in the air"),
}
