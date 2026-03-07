--- Catalog: Visual Effects.
-- Screen-wide visual effects that modify the overall look of the output.
-- These are independent from camera (framing), lighting (light source),
-- and style (artistic medium). They compose freely with all other catalogs.
-- Target: SDXL 1.0 Base and above.
--
-- Note on overlap:
--   film_grain also appears in style.photo and style.cinematic as part of
--   their aesthetic bundle. Using effect.film_grain independently allows
--   combining it with non-photo styles (e.g. anime + film_grain).
--
-- Sources:
--   Civitai visual effect guides, Danbooru tag analysis,
--   Segmind SDXL Prompt Guide, ComfyUI-Prompt-Snippets effect category.

local Trait   = require("vdsl.trait")
local Catalog = require("vdsl.catalog")

return Catalog.new {
  -- === Light effects ===
  bloom = Trait.new("bloom, light bloom", 1.1)
    + Trait.new("glow, soft light diffusion"),

  light_particles = Trait.new("light particles", 1.1)
    + Trait.new("floating particles, dust motes, sparkles"),

  lens_flare = Trait.new("lens flare, light flare"),

  -- === Film/analog effects ===
  film_grain = Trait.new("film grain", 1.1)
    + Trait.new("analog noise, grain texture"),

  vignette = Trait.new("vignetting, vignette, darkened edges"),

  -- === Motion effects ===
  motion_blur = Trait.new("motion blur", 1.1),

  -- === Artistic effects ===
  double_exposure = Trait.new("double exposure", 1.1)
    + Trait.new("overlay, merged images"),

  spot_color = Trait.new("spot color", 1.1)
    + Trait.new("selective color, monochrome with color accent"),

  glitch = Trait.new("glitch art", 1.1)
    + Trait.new("digital distortion, data corruption"),

  -- === Lens / Optical effects ===
  chromatic_aberration = Trait.new("chromatic aberration", 1.1)
    + Trait.new("color fringing, RGB shift"),

  halation = Trait.new("halation", 1.1)
    + Trait.new("light bleed, film halation, soft glow around highlights"),

  light_leak = Trait.new("light leak", 1.1)
    + Trait.new("film light leak, warm color wash, analog photography"),

  -- === Scene particles / visual props ===
  -- Concrete visual objects scattered in the scene.
  -- Tested: seed-fixed A/B comparison on anime (novaAnimeXL) and
  --         photo (RealVisXL Lightning) checkpoints.
  --
  -- Model compatibility:
  --   anime+photo : bubbles, feathers, butterflies
  --   anime only  : confetti (photo: turns to bokeh), scattered_papers (photo: no effect)
  --   anime+photo*: embers (photo: warm bokeh glow, weak particle feel but atmospheric)

  -- anime+photo: soap bubbles. Transparent, iridescent reflections. Stable on both.
  bubbles = Trait.new("soap bubbles", 1.1)
    + Trait.new("floating bubbles, iridescent"),

  -- anime+photo: white feathers. Especially striking on photo models (fashion-shoot feel).
  feathers = Trait.new("feathers", 1.1)
    + Trait.new("white feathers, floating feathers"),

  -- anime+photo: butterflies. Slightly fantasy-leaning on photo but still works.
  butterflies = Trait.new("butterflies", 1.1)
    + Trait.new("colorful butterflies, flying"),

  -- anime only: on photo models turns into bokeh light. On anime renders as confetti.
  confetti = Trait.new("confetti", 1.1)
    + Trait.new("colorful confetti, scattered"),

  -- anime only: completely ignored on photo models. Dramatic visual change on anime.
  scattered_papers = Trait.new("scattered papers", 1.1)
    + Trait.new("flying papers, pages"),

  -- anime+photo*: adding "glowing" makes it a light source. "scattered, small particles" disperses.
  -- On photo models rendered as warm bokeh glow (weak particle feel).
  embers = Trait.new("embers", 1.1)
    + Trait.new("floating embers, scattered, small particles"),
}
