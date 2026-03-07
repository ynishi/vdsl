--- Catalog: Style presets.
-- Artistic medium and aesthetic Traits for prompt construction.
-- Used internally by Subject:style() and available as vdsl.catalogs.style.
-- Target: SDXL and above.
--
-- Note: pixel and manga styles have limited effectiveness on base SDXL.
-- Anime finetunes (Illustrious, Animagine) or dedicated LoRAs recommended.

local Trait   = require("vdsl.trait")
local Catalog = require("vdsl.catalog")

return Catalog.new {
  -- === Core styles (high reliability on SDXL) ===
  anime = Trait.new("anime style", 1.1)
    + Trait.new("cel shading, flat color, clean lineart, 2D"),

  photo = Trait.new("photorealistic", 1.2)
    + Trait.new("raw photo, DSLR, natural skin texture, film grain"),

  oil = Trait.new("oil painting", 1.1)
    + Trait.new("visible brush strokes, classical art, canvas texture"),

  watercolor = Trait.new("watercolor painting", 1.1)
    + Trait.new("soft edges, wet media, color bleeding, paper texture"),

  cinematic = Trait.new("cinematic", 1.2)
    + Trait.new("film grain, anamorphic lens, dramatic lighting, color grading"),

  concept_art = Trait.new("concept art", 1.1)
    + Trait.new("digital painting, illustration, matte painting"),

  digital_painting = Trait.new("digital painting", 1.1)
    + Trait.new("illustration, vibrant colors, detailed"),

  line_art = Trait.new("line art", 1.1)
    + Trait.new("ink drawing, clean lines, monochrome, pen illustration"),

  -- === Technique modifiers (compose with styles above) ===
  -- These override the default shading/linework of a style.
  -- e.g. style.anime uses cel shading by default;
  --      style.anime + style.soft_shading → anime with gradient shadows.
  flat_color = Trait.new("flat color, no shading", 1.1),

  soft_shading = Trait.new("soft shading", 1.1)
    + Trait.new("smooth gradients, gentle shadows"),

  no_lineart = Trait.new("no lineart, lineless", 1.1)
    + Trait.new("painting without outlines"),

  impasto = Trait.new("impasto", 1.1)
    + Trait.new("thick paint, textured brushwork, heavy strokes"),

  -- === Model-dependent styles (finetune/LoRA recommended) ===
  pixel = Trait.new("pixel art", 1.1)
    + Trait.new("retro game, 8-bit, low resolution sprite"),

  ["3d"] = Trait.new("3d render", 1.1)
    + Trait.new("global illumination, ray tracing, subsurface scattering, realistic materials"),

  manga = Trait.new("manga style", 1.1)
    + Trait.new("ink, black and white, hatching, comic panel"),

  -- === Cultural / Historical styles ===
  -- model-dependent: SDXL base has moderate recognition.
  -- Anime finetunes (Illustrious) may not respond well.
  ukiyo_e = Trait.new("ukiyo-e", 1.1)
    + Trait.new("woodblock print, flat perspective, bold outlines, Japanese art"),

  art_nouveau = Trait.new("art nouveau", 1.1)
    + Trait.new("ornamental, flowing organic lines, decorative borders"),
}
