--- Catalog: Body type modifiers.
-- Adjective Traits for character physique and age appearance.
-- These compose with any subject as modifier traits.
-- Target: SDXL 1.0 Base and above.
--
-- Usage:
--   Subject.new("1girl"):with(catalogs.figure.body.slim)
--   catalogs.figure.body.muscular + "warrior"
--
-- Note:
--   Body type tags are more stable than occupation tags (e.g. "athlete")
--   which also change clothing and background.
--   "old" alone risks being interpreted as "old object" on base SDXL —
--   use "elderly" instead.
--
-- Real-model note:
--   muscular, curvy, chubby are effective on photo-realistic models.
--   toned, slim, skinny, petite produce subtle differences — anime models
--   reflect these more clearly than RealVisXL Lightning and similar.
--
-- Sources:
--   dav.one SDXL body modification guide, Civitai Pony XL body tags,
--   StableDiffusionWeb body type prompts, PixAI Danbooru tag cheat sheet.

local Trait   = require("vdsl.trait")
local Catalog = require("vdsl.catalog")

return Catalog.new {
  -- === Build ===
  muscular = Trait.new("muscular", 1.1)
    + Trait.new("muscles, athletic build")
    :desc("muscular athletic build with visible muscles"),

  toned = Trait.new("toned, lean body")
    :desc("toned lean body"),

  slim = Trait.new("slim, slender")
    :desc("slim slender build"),

  skinny = Trait.new("skinny, very thin")
    :desc("very thin skinny build"),

  petite = Trait.new("petite, small frame")
    :desc("petite small frame"),

  curvy = Trait.new("curvy, hourglass figure")
    :desc("curvy hourglass figure"),

  chubby = Trait.new("chubby, plump")
    :desc("chubby plump build"),

  -- === Feature ===
  abs = Trait.new("abs", 1.1)
    :desc("visible abdominal muscles"),

  -- === Proportion (independent of build) ===
  tall             = Trait.new("tall"):desc("tall stature"),
  long_legs        = Trait.new("long legs"):desc("long legs"),

  -- === Age ===
  elderly = Trait.new("elderly", 1.1)
    + Trait.new("wrinkles, aged")
    :desc("elderly with wrinkles and aged features"),
}
