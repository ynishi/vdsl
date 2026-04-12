--- Catalog: Quality presets.
-- Positive quality levels, boosters, and negative quality Traits.
-- Used internally by Subject:quality() and available as vdsl.catalogs.quality.
-- Target: SDXL and above.
--
-- Note: "masterpiece, best quality" are effective on anime finetunes
-- (Animagine, Illustrious) but weak on SDXL Base. Kept for broad compatibility.
-- "8k uhd", "absurdres" removed as cargo cult on base SDXL.

local Trait   = require("vdsl.trait")
local Catalog = require("vdsl.catalog")

return Catalog.new {
  -- === Positive quality levels ===
  high = Trait.new("masterpiece, best quality", 1.1)
    + Trait.new("highly detailed, sharp focus, high resolution")
    :desc("masterpiece quality with high detail, sharp focus, and high resolution"),

  medium = Trait.new("good quality, detailed")
    :desc("good quality with decent detail"),

  draft = Trait.new("sketch, rough, concept art")
    :desc("rough sketch or concept art quality"),

  -- === Boosters (compose with quality levels via +) ===
  ultra = Trait.new("extremely detailed", 1.2)
    + Trait.new("intricate details, fine texture, professional")
    :hint("hires", { scale = 1.5, denoise = 0.35 })
    :hint("sharpen", { radius = 1, sigma = 0.8 })
    :desc("extremely detailed with intricate fine textures at professional quality"),

  sharp = Trait.new("sharp focus, crisp details", 1.1)
    :desc("sharp focus with crisp details"),

  -- === Negative quality (for Cast.negative or Theme.negatives) ===
  neg_default = Trait.new("low quality, worst quality, blurry, jpeg artifacts, watermark, text, signature")
    :desc("low quality, blurry, jpeg artifacts, watermarks, text, and signatures"),

  neg_anatomy = Trait.new("bad anatomy, bad hands, extra fingers, extra limbs, deformed, mutated")
    :desc("bad anatomy with extra fingers, extra limbs, deformed or mutated body parts"),

  neg_face = Trait.new("ugly face, deformed face, disfigured, asymmetric eyes, bad proportions")
    :desc("ugly deformed disfigured face with asymmetric eyes and bad proportions"),

  neg_composition = Trait.new("multiple views, comic, 4koma, monochrome, split screen")
    :desc("multiple views, comic panels, split screen, or unintended monochrome"),
}
