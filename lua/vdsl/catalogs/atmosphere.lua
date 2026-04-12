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
  serene = Trait.new("serene atmosphere, tranquil, calm and still")
    :desc("serene and tranquil atmosphere, calm and perfectly still"),

  peaceful = Trait.new("peaceful atmosphere, gentle, soothing")
    :desc("peaceful atmosphere with a gentle, soothing quality"),

  tranquil = Trait.new("tranquil atmosphere, quiet stillness, undisturbed")
    :desc("tranquil atmosphere of quiet undisturbed stillness"),

  -- === Dramatic / Intense ===
  dramatic = Trait.new("dramatic atmosphere", 1.1)
    + Trait.new("intense, powerful presence, heightened emotion")
    :desc("dramatic and intense atmosphere with powerful presence and heightened emotion"),

  epic = Trait.new("epic atmosphere", 1.1)
    + Trait.new("grandiose, awe-inspiring, monumental scale")
    :desc("epic grandiose atmosphere of awe-inspiring monumental scale"),

  intense = Trait.new("intense atmosphere, raw energy, visceral")
    :desc("intense visceral atmosphere charged with raw energy"),

  -- === Dark / Ominous ===
  ominous = Trait.new("ominous atmosphere", 1.1)
    + Trait.new("foreboding, sense of dread, impending danger")
    :desc("ominous foreboding atmosphere with a sense of dread and impending danger"),

  sinister = Trait.new("sinister atmosphere, dark and menacing, unsettling")
    :desc("sinister and menacing atmosphere, dark and deeply unsettling"),

  -- === Ethereal / Dream ===
  ethereal = Trait.new("ethereal atmosphere", 1.1)
    + Trait.new("otherworldly, delicate, luminous and airy")
    :desc("ethereal otherworldly atmosphere, delicate and luminously airy"),

  dreamlike = Trait.new("dreamlike atmosphere, surreal, soft and hazy, fantasy")
    :desc("dreamlike surreal atmosphere, soft and hazy like a waking fantasy"),

  surreal = Trait.new("surreal atmosphere, bizarre, impossible, mind-bending")
    :desc("surreal mind-bending atmosphere where the impossible feels real"),

  -- === Nostalgic / Emotional ===
  nostalgic = Trait.new("nostalgic atmosphere", 1.1)
    + Trait.new("wistful, longing, memories of the past")
    :desc("nostalgic wistful atmosphere evoking longing and memories of the past"),

  melancholic = Trait.new("melancholic atmosphere, sorrowful, bittersweet, poignant")
    :desc("melancholic bittersweet atmosphere, sorrowful yet poignant"),

  -- === Cozy / Intimate ===
  cozy = Trait.new("cozy atmosphere, warm and inviting, comfortable, homely")
    :desc("cozy warm atmosphere, inviting and comfortably homely"),

  intimate = Trait.new("intimate atmosphere, close and personal, quiet moment")
    :desc("intimate atmosphere of a close personal quiet moment"),

  -- === Mysterious ===
  mysterious = Trait.new("mysterious atmosphere", 1.1)
    + Trait.new("enigmatic, unknown, hidden secrets")
    :desc("mysterious enigmatic atmosphere hiding unknown secrets"),

  enigmatic = Trait.new("enigmatic atmosphere, cryptic, puzzling, inscrutable")
    :desc("enigmatic cryptic atmosphere, puzzling and inscrutable"),

  -- === Whimsical / Playful ===
  whimsical = Trait.new("whimsical atmosphere, playful, lighthearted, fanciful")
    :desc("whimsical playful atmosphere, lighthearted and fanciful"),

  -- === Tense / Suspenseful ===
  tense = Trait.new("tense atmosphere", 1.1)
    + Trait.new("suspenseful, anxiety, on edge")
    :desc("tense suspenseful atmosphere filled with anxiety and unease"),

  -- === Majestic ===
  majestic = Trait.new("majestic atmosphere, regal, grand, magnificent")
    :desc("majestic regal atmosphere of grand magnificence"),
}
