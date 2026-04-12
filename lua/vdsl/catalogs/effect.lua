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
    + Trait.new("glow, soft light diffusion")
    :desc("bloom effect with soft glowing light diffusion"),

  light_particles = Trait.new("light particles", 1.1)
    + Trait.new("floating particles, dust motes, sparkles")
    :desc("floating light particles, dust motes, and sparkles in the air"),

  lens_flare = Trait.new("lens flare, light flare")
    :desc("lens flare from a bright light source"),

  -- === Film/analog effects ===
  film_grain = Trait.new("film grain", 1.1)
    + Trait.new("analog noise, grain texture")
    :desc("analog film grain noise texture"),

  vignette = Trait.new("vignetting, vignette, darkened edges")
    :desc("vignette effect with darkened edges"),

  -- === Motion effects ===
  motion_blur = Trait.new("motion blur", 1.1)
    :desc("motion blur conveying movement and speed"),

  -- === Artistic effects ===
  double_exposure = Trait.new("double exposure", 1.1)
    + Trait.new("overlay, merged images")
    :desc("double exposure effect with overlaid merged images"),

  spot_color = Trait.new("spot color", 1.1)
    + Trait.new("selective color, monochrome with color accent")
    :desc("spot color effect with selective color accent on a monochrome image"),

  glitch = Trait.new("glitch art", 1.1)
    + Trait.new("digital distortion, data corruption")
    :desc("glitch art with digital distortion and data corruption artifacts"),

  -- === Lens / Optical effects ===
  chromatic_aberration = Trait.new("chromatic aberration", 1.1)
    + Trait.new("color fringing, RGB shift")
    :desc("chromatic aberration with color fringing and RGB shift"),

  halation = Trait.new("halation", 1.1)
    + Trait.new("light bleed, film halation, soft glow around highlights")
    :desc("film halation with soft glowing light bleed around highlights"),

  light_leak = Trait.new("light leak", 1.1)
    + Trait.new("film light leak, warm color wash, analog photography")
    :desc("analog film light leak with a warm color wash"),

  -- === Scene particles / visual props ===
  bubbles = Trait.new("soap bubbles", 1.1)
    + Trait.new("floating bubbles, iridescent")
    :desc("floating iridescent soap bubbles"),

  feathers = Trait.new("feathers", 1.1)
    + Trait.new("white feathers, floating feathers")
    :desc("white feathers floating gently in the air"),

  butterflies = Trait.new("butterflies", 1.1)
    + Trait.new("colorful butterflies, flying")
    :desc("colorful butterflies flying around"),

  confetti = Trait.new("confetti", 1.1)
    + Trait.new("colorful confetti, scattered")
    :desc("colorful confetti scattered in the air"),

  scattered_papers = Trait.new("scattered papers", 1.1)
    + Trait.new("flying papers, pages")
    :desc("papers and pages scattered and flying through the air"),

  embers = Trait.new("embers", 1.1)
    + Trait.new("floating embers, scattered, small particles")
    :desc("glowing embers floating as small scattered particles"),
}
