--- Catalog: Species / Race modifiers.
-- Non-human or fantasy race Traits for character generation.
-- These add species-defining features (ears, tails, wings, horns)
-- to a base subject. Compose with any character description.
-- Target: SDXL 1.0 Base and above.
--
-- Tag selection follows Danbooru implication chains:
--   elf → pointy_ears (auto-implied, no need to double-specify)
--   cat_ears → animal_ears (auto-implied)
--   demon_horns → horns (auto-implied)
-- Redundant tags are removed to save tokens.
--
-- Usage:
--   Subject.new("1girl"):with(catalogs.figure.species.elf)
--   catalogs.figure.species.catgirl + catalogs.figure.hair.black
--
-- Anime finetunes (Illustrious, Pony) have stronger recognition
-- for mid-frequency species tags (oni, kitsune, lamia).
--
-- Sources:
--   Danbooru tag wiki (elf, cat_ears, demon_girl, monster_girl),
--   Civitai character generation guides,
--   Pony XL 320+ ears/wings/tails tag list.

local Trait   = require("vdsl.trait")
local Catalog = require("vdsl.catalog")

return Catalog.new {
  -- === Fantasy humanoid ===
  elf = Trait.new("elf", 1.1)
    + Trait.new("pointy ears")
    :desc("an elf with pointed ears"),

  dark_elf = Trait.new("dark elf", 1.1)
    + Trait.new("dark skin, white hair")
    :desc("a dark elf with dark skin and white hair"),

  fairy = Trait.new("fairy", 1.1)
    + Trait.new("fairy wings, minigirl")
    :desc("a tiny fairy with delicate wings"),

  angel = Trait.new("angel", 1.1)
    + Trait.new("angel wings, halo")
    :desc("an angel with feathered wings and a halo"),

  demon = Trait.new("demon", 1.1)
    + Trait.new("demon horns, demon wings, demon tail")
    :desc("a demon with horns, bat-like wings, and a tail"),

  vampire = Trait.new("vampire", 1.1)
    + Trait.new("pale skin, red eyes, fangs")
    :desc("a vampire with pale skin, red eyes, and fangs"),

  oni = Trait.new("oni", 1.1)
    + Trait.new("horns")
    :desc("a Japanese oni with horns"),

  succubus = Trait.new("succubus", 1.1)
    + Trait.new("demon wings, demon tail, demon horns")
    :desc("a succubus with demon wings, tail, and horns"),

  -- === Animal-eared (kemonomimi) ===
  catgirl = Trait.new("cat ears, cat tail", 1.1)
    :desc("cat ears and a cat tail"),

  foxgirl = Trait.new("fox ears, fox tail", 1.1)
    :desc("fox ears and a fluffy fox tail"),

  kitsune = Trait.new("kitsune", 1.1)
    + Trait.new("fox ears, fox tail, multiple tails")
    :desc("a kitsune fox spirit with fox ears and multiple tails"),

  wolfgirl = Trait.new("wolf ears, wolf tail", 1.1)
    :desc("wolf ears and a wolf tail"),

  bunnygirl = Trait.new("rabbit ears, rabbit tail", 1.1)
    :desc("rabbit ears and a fluffy rabbit tail"),

  -- === Monster / mythical ===
  mermaid = Trait.new("mermaid", 1.1)
    + Trait.new("fish tail, scales")
    :desc("a mermaid with a scaled fish tail"),

  dragon = Trait.new("dragon horns, dragon tail, dragon wings", 1.1)
    + Trait.new("scales")
    :desc("dragon features with horns, scaled tail, and wings"),

  lamia = Trait.new("lamia", 1.1)
    + Trait.new("snake tail, scales")
    :desc("a lamia with a long serpentine lower body"),

  harpy = Trait.new("harpy", 1.1)
    + Trait.new("wings, talons, bird legs")
    :desc("a harpy with feathered wings and bird-like talons"),

  ghost = Trait.new("ghost", 1.1)
    + Trait.new("ghost tail, pale skin, glowing")
    :desc("a ghostly figure with pale glowing translucent skin"),

  centaur = Trait.new("centaur", 1.1)
    + Trait.new("horse body, hooves")
    :desc("a centaur with a human upper body and horse lower body"),

  -- === Mechanical ===
  android = Trait.new("android", 1.1)
    + Trait.new("robot joints, robot ears")
    :desc("an android with visible mechanical joints"),

  cyborg = Trait.new("cyborg", 1.1)
    + Trait.new("mechanical parts, robot joints")
    :desc("a cyborg with mechanical prosthetic parts"),
}
