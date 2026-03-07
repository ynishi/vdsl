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
  -- elf: pointy_ears is auto-implied by elf tag.
  elf = Trait.new("elf", 1.1)
    + Trait.new("pointy ears"),

  -- dark_elf: elf → pointy_ears chain, no need to repeat.
  dark_elf = Trait.new("dark elf", 1.1)
    + Trait.new("dark skin, white hair"),

  fairy = Trait.new("fairy", 1.1)
    + Trait.new("fairy wings, minigirl"),

  angel = Trait.new("angel", 1.1)
    + Trait.new("angel wings, halo"),

  -- demon: demon_horns implies horns. Wings and tail added.
  demon = Trait.new("demon", 1.1)
    + Trait.new("demon horns, demon wings, demon tail"),

  vampire = Trait.new("vampire", 1.1)
    + Trait.new("pale skin, red eyes, fangs"),

  oni = Trait.new("oni", 1.1)
    + Trait.new("horns"),

  succubus = Trait.new("succubus", 1.1)
    + Trait.new("demon wings, demon tail, demon horns"),

  -- === Animal-eared (kemonomimi) ===
  -- Danbooru: cat_ears is the correct tag. "animal ears, cat" does NOT exist.
  catgirl = Trait.new("cat ears, cat tail", 1.1),

  foxgirl = Trait.new("fox ears, fox tail", 1.1),

  -- kitsune: distinct from foxgirl. Mythological fox spirit with multiple tails.
  kitsune = Trait.new("kitsune", 1.1)
    + Trait.new("fox ears, fox tail, multiple tails"),

  wolfgirl = Trait.new("wolf ears, wolf tail", 1.1),

  -- bunnygirl: rabbit_ears is the canonical tag. bunny_ears is an alias (redundant).
  bunnygirl = Trait.new("rabbit ears, rabbit tail", 1.1),

  -- === Monster / mythical ===
  -- mermaid: underwater is a scene tag, not a species attribute.
  mermaid = Trait.new("mermaid", 1.1)
    + Trait.new("fish tail, scales"),

  -- dragon: part-based tags to keep humanoid form.
  dragon = Trait.new("dragon horns, dragon tail, dragon wings", 1.1)
    + Trait.new("scales"),

  lamia = Trait.new("lamia", 1.1)
    + Trait.new("snake tail, scales"),

  harpy = Trait.new("harpy", 1.1)
    + Trait.new("wings, talons, bird legs"),

  ghost = Trait.new("ghost", 1.1)
    + Trait.new("ghost tail, pale skin, glowing"),

  -- Experimental: complex body composition often causes pose/perspective distortion.
  centaur = Trait.new("centaur", 1.1)
    + Trait.new("horse body, hooves"),

  -- === Mechanical ===
  -- robot is too broad (pulls mecha/gundam). Split into android and cyborg.
  android = Trait.new("android", 1.1)
    + Trait.new("robot joints, robot ears"),

  cyborg = Trait.new("cyborg", 1.1)
    + Trait.new("mechanical parts, robot joints"),
}
