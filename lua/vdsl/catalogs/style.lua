--- Catalog: Style presets.
-- Artistic medium and aesthetic Traits for prompt construction.
-- Used internally by Subject:style() and available as vdsl.catalogs.style.
-- Target: SDXL and above.
--
-- Note: pixel and manga styles have limited effectiveness on base SDXL.
-- Anime finetunes (Illustrious, Animagine) or dedicated LoRAs recommended.

local Trait   = require("vdsl.trait")
local Catalog = require("vdsl.catalog")
local K       = Trait  -- tag key constants

return Catalog.new {
  -- === Core styles (high reliability on SDXL) ===
  anime = Trait.new("anime style", 1.1)
    + Trait.new("cel shading, flat color, clean lineart, 2D")
    :tag(K.CONFLICTS, "photorealistic")
    :desc("anime-style illustration with cel shading, flat colors, and clean lineart"),

  photo = Trait.new("photorealistic", 1.2)
    + Trait.new("raw photo, DSLR, natural skin texture, film grain")
    :tag(K.CONFLICTS, "anime style")
    :desc("photorealistic DSLR photography with natural skin texture and subtle film grain"),

  oil = Trait.new("oil painting", 1.1)
    + Trait.new("visible brush strokes, classical art, canvas texture")
    :tag(K.CONFLICTS, "watercolor painting")
    :desc("classical oil painting with visible brush strokes on canvas texture"),

  watercolor = Trait.new("watercolor painting", 1.1)
    + Trait.new("soft edges, wet media, color bleeding, paper texture")
    :tag(K.CONFLICTS, "oil painting")
    :desc("watercolor painting with soft edges, color bleeding, and textured paper"),

  cinematic = Trait.new("cinematic", 1.2)
    + Trait.new("film grain, anamorphic lens, dramatic lighting, color grading")
    :desc("cinematic look with film grain, anamorphic lens distortion, dramatic lighting, and professional color grading"),

  concept_art = Trait.new("concept art", 1.1)
    + Trait.new("digital painting, illustration, matte painting")
    :desc("concept art digital painting with matte painting techniques"),

  digital_painting = Trait.new("digital painting", 1.1)
    + Trait.new("illustration, vibrant colors, detailed")
    :desc("detailed digital painting illustration with vibrant colors"),

  line_art = Trait.new("line art", 1.1)
    + Trait.new("ink drawing, clean lines, monochrome, pen illustration")
    :tag(K.CONFLICTS, "no lineart")
    :desc("monochrome ink line art drawing with clean precise lines"),

  -- === Technique modifiers (compose with styles above) ===
  flat_color = Trait.new("flat color, no shading", 1.1)
    :desc("flat color fill without shading or gradients"),

  soft_shading = Trait.new("soft shading", 1.1)
    + Trait.new("smooth gradients, gentle shadows")
    :desc("soft shading with smooth gradients and gentle shadow transitions"),

  no_lineart = Trait.new("no lineart, lineless", 1.1)
    + Trait.new("painting without outlines")
    :tag(K.CONFLICTS, "line art")
    :desc("lineless painting style without visible outlines"),

  impasto = Trait.new("impasto", 1.1)
    + Trait.new("thick paint, textured brushwork, heavy strokes")
    :desc("impasto technique with thick textured paint and heavy brush strokes"),

  -- === Model-dependent styles (finetune/LoRA recommended) ===
  pixel = Trait.new("pixel art", 1.1)
    + Trait.new("retro game, 8-bit, low resolution sprite")
    :desc("retro pixel art in 8-bit game sprite style"),

  ["3d"] = Trait.new("3d render", 1.1)
    + Trait.new("global illumination, ray tracing, subsurface scattering, realistic materials")
    :desc("photorealistic 3D render with global illumination, ray tracing, and subsurface scattering"),

  manga = Trait.new("manga style", 1.1)
    + Trait.new("ink, black and white, hatching, comic panel")
    :desc("manga-style black and white ink illustration with hatching"),

  -- === Cultural / Historical styles ===
  ukiyo_e = Trait.new("ukiyo-e", 1.1)
    + Trait.new("woodblock print, flat perspective, bold outlines, Japanese art")
    :desc("traditional Japanese ukiyo-e woodblock print style with bold outlines and flat perspective"),

  art_nouveau = Trait.new("art nouveau", 1.1)
    + Trait.new("ornamental, flowing organic lines, decorative borders")
    :desc("Art Nouveau style with ornamental flowing organic lines and decorative borders"),
}
