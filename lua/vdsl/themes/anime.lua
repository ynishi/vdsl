--- Theme: Anime / NPR
-- Non-photorealistic rendering traits for anime/illustration styles.

local Trait = require("vdsl.trait")
local Theme = require("vdsl.theme")

return Theme.new {
  name     = "anime",
  category = "illustration",
  tags     = { "anime", "manga", "cel", "2d" },
  defaults = {
    steps     = 28,
    cfg       = 7.0,
    sampler   = "euler",
    scheduler = "normal",
    size      = { 832, 1216 },
  },
  negatives = {
    default = Trait.new("photorealistic, 3d render, realistic, photo, deformed"),
    quality = Trait.new("low quality, worst quality, blurry, jpeg artifacts"),
  },
  traits   = {
    cel_shade = Trait.new("anime style, cel shading, flat colors, clean lineart")
      :hint("sharpen", { radius = 1, sigma = 0.8, alpha = 0.6 }),

    watercolor = Trait.new("anime watercolor, soft edges, pastel colors, illustration")
      :hint("color", { saturation = 0.9 }),

    ghibli = Trait.new("studio ghibli style, lush scenery, warm palette, hand painted")
      :hint("color", { saturation = 1.1, brightness = 1.05 }),

    cyberpunk = Trait.new("cyberpunk anime, neon glow, dark atmosphere, sci-fi")
      :hint("color", { contrast = 1.15, saturation = 1.2 }),

    chibi = Trait.new("chibi style, super deformed, cute, big head, small body"),

    sketch = Trait.new("pencil sketch, line drawing, rough strokes, concept art"),

    retro = Trait.new("90s anime style, VHS aesthetic, slightly grainy, nostalgic")
      :hint("color", { saturation = 0.85, gamma = 0.95 }),

    bijutsu = Trait.new("detailed anime background, scenic, atmospheric perspective"),
  },
}
