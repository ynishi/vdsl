--- Catalog: Eye attributes.
-- Eye color and feature Traits for character description.
-- Compose freely: eyes.blue + eyes.sharp
-- Target: SDXL 1.0 Base and above.
--
-- Eye color tags are single Danbooru tags (e.g. "blue eyes" = blue_eyes).
-- Do NOT decompose these into separate words.
--
-- Known issues:
--   - Color bleeding: eye color may leak into hair/clothing.
--     Mitigation: place clothing color BEFORE eye color in prompt.
--     Source: Fooocus issue #2205
--   - blue_eyes has strong blonde hair bias in SDXL base.
--   - brown_eyes may drift to black on some seeds.
--   - purple_eyes + purple hair = poor color separation.
--
-- Sources:
--   Danbooru2025 tag counts (HuggingFace dataproc5),
--   Fooocus issue #2205 (color bleeding),
--   Crody's Illustrious/NoobAI Tips (Civitai),
--   NovelAI character creation docs.

local Trait   = require("vdsl.trait")
local Catalog = require("vdsl.catalog")
local K       = Trait  -- tag key constants: K.TIER, K.CONFLICTS, K.SOURCE

return Catalog.new {
  -- === Color (Danbooru single tags, do not split) ===
  -- S tier (>1M posts): highly reliable across all SDXL-based models.
  blue    = Trait.new("blue eyes")
    :confidence(0.95):tag(K.TIER, "S"):tag(K.SOURCE, "danbooru"),
  red     = Trait.new("red eyes")
    :confidence(0.95):tag(K.TIER, "S"):tag(K.SOURCE, "danbooru"),
  green   = Trait.new("green eyes")
    :confidence(0.95):tag(K.TIER, "S"):tag(K.SOURCE, "danbooru"),
  brown   = Trait.new("brown eyes")
    :confidence(0.90):tag(K.TIER, "S"):tag(K.SOURCE, "danbooru"),  -- may drift to black on some seeds
  purple  = Trait.new("purple eyes")
    :confidence(0.90):tag(K.TIER, "S"):tag(K.SOURCE, "danbooru")
    :tag(K.CONFLICTS, "purple hair"),
  yellow  = Trait.new("yellow eyes")
    :confidence(0.95):tag(K.TIER, "S"):tag(K.SOURCE, "danbooru"),

  -- A tier (high freq): stable on Illustrious/NoobAI, slightly less reliable on base SDXL.
  orange  = Trait.new("orange eyes")
    :confidence(0.80):tag(K.TIER, "A"):tag(K.SOURCE, "danbooru"),
  aqua    = Trait.new("aqua eyes")
    :confidence(0.80):tag(K.TIER, "A"):tag(K.SOURCE, "danbooru"),
  pink    = Trait.new("pink eyes")
    :confidence(0.80):tag(K.TIER, "A"):tag(K.SOURCE, "danbooru"),

  -- B tier: limited data, model-dependent.
  silver  = Trait.new("silver eyes")
    :confidence(0.65):tag(K.TIER, "B"):tag(K.SOURCE, "danbooru"),

  -- === Feature ===
  -- heterochromia: unreliable alone. Cannot control which eye gets which color.
  -- LoRA recommended for precise control (Heterochromia_h4 etc).
  heterochromia = Trait.new("heterochromia", 1.2)
    :confidence(0.30):tag(K.TIER, "C"):tag(K.SOURCE, "novelai,civitai")
    :hint("benefits_from", { resource = "lora" }),

  -- slit_pupils: single Danbooru tag. Works better on anime finetunes.
  slit_pupils = Trait.new("slit pupils")
    :confidence(0.60):tag(K.TIER, "B"):tag(K.SOURCE, "tensorart"),

  -- glowing_eyes: high visual impact, stable across models.
  -- Best with dark backgrounds.
  glowing = Trait.new("glowing eyes")
    :confidence(0.90):tag(K.TIER, "A"):tag(K.SOURCE, "danbooru"),

  -- sharp_eyes: impression control. Strong gaze effect.
  sharp = Trait.new("sharp eyes")
    :confidence(0.85):tag(K.TIER, "A"):tag(K.SOURCE, "danbooru"),

  -- empty_eyes: horror/emotionless. May conflict with white_eyes.
  empty = Trait.new("empty eyes")
    :confidence(0.60):tag(K.TIER, "B")
    :tag(K.CONFLICTS, "white eyes"):tag(K.SOURCE, "danbooru"),
}
