--- Catalog: Atmosphere presets.
-- Curated emotional tone Traits for Atmosphere construction.
-- Each entry is a raw Trait; init.lua wraps them in Atmosphere.new() on access.
--
-- IMPORTANT DISTINCTION:
--   atmosphere != lighting. Lighting describes physical light placement
--   (Rembrandt, rim light). Atmosphere describes the emotional feel
--   (serene, ominous). They are independent axes that compose.
--
-- Target: SDXL 1.0 Base and above.
--
-- Sources:
--   Segmind SDXL Prompt Guide (mood layer analysis),
--   NeuroCanvas Prompting Guide (atmosphere vs lighting distinction),
--   PromptHero atmosphere prompts, DiffusionDB analysis.

local Trait   = require("vdsl.trait")
local Catalog = require("vdsl.catalog")

return Catalog.new {
  -- === Calm / Peaceful ===
  serene = Trait.new("serene atmosphere, tranquil, calm and still"),

  peaceful = Trait.new("peaceful atmosphere, gentle, soothing"),

  tranquil = Trait.new("tranquil atmosphere, quiet stillness, undisturbed"),

  -- === Dramatic / Intense ===
  dramatic = Trait.new("dramatic atmosphere", 1.1)
    + Trait.new("intense, powerful presence, heightened emotion"),

  epic = Trait.new("epic atmosphere", 1.1)
    + Trait.new("grandiose, awe-inspiring, monumental scale"),

  intense = Trait.new("intense atmosphere, raw energy, visceral"),

  -- === Dark / Ominous ===
  ominous = Trait.new("ominous atmosphere", 1.1)
    + Trait.new("foreboding, sense of dread, impending danger"),

  sinister = Trait.new("sinister atmosphere, dark and menacing, unsettling"),

  -- === Ethereal / Dream ===
  ethereal = Trait.new("ethereal atmosphere", 1.1)
    + Trait.new("otherworldly, delicate, luminous and airy"),

  dreamlike = Trait.new("dreamlike atmosphere, surreal, soft and hazy, fantasy"),

  surreal = Trait.new("surreal atmosphere, bizarre, impossible, mind-bending"),

  -- === Nostalgic / Emotional ===
  nostalgic = Trait.new("nostalgic atmosphere", 1.1)
    + Trait.new("wistful, longing, memories of the past"),

  melancholic = Trait.new("melancholic atmosphere, sorrowful, bittersweet, poignant"),

  -- === Cozy / Intimate ===
  cozy = Trait.new("cozy atmosphere, warm and inviting, comfortable, homely"),

  intimate = Trait.new("intimate atmosphere, close and personal, quiet moment"),

  -- === Mysterious ===
  mysterious = Trait.new("mysterious atmosphere", 1.1)
    + Trait.new("enigmatic, unknown, hidden secrets"),

  enigmatic = Trait.new("enigmatic atmosphere, cryptic, puzzling, inscrutable"),

  -- === Whimsical / Playful ===
  whimsical = Trait.new("whimsical atmosphere, playful, lighthearted, fanciful"),

  -- === Tense / Suspenseful ===
  tense = Trait.new("tense atmosphere", 1.1)
    + Trait.new("suspenseful, anxiety, on edge"),

  -- === Majestic ===
  majestic = Trait.new("majestic atmosphere, regal, grand, magnificent"),
}
