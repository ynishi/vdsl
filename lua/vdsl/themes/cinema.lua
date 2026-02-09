--- Theme: Cinema / Photography
-- Film-inspired traits for lighting, mood, and grading.

local Trait = require("vdsl.trait")
local Theme = require("vdsl.theme")

return Theme.new {
  name     = "cinema",
  category = "photography",
  tags     = { "film", "lighting", "mood", "grading" },
  defaults = {
    steps     = 30,
    cfg       = 7.5,
    sampler   = "euler",
    scheduler = "normal",
    size      = { 1024, 1024 },
  },
  negatives = {
    default = Trait.new("cartoon, anime, drawing, illustration, painting, sketch"),
    quality = Trait.new("low quality, worst quality, blurry, jpeg artifacts, watermark"),
  },
  traits   = {
    golden_hour = Trait.new("golden hour, warm light, sunset glow, long shadows")
      :hint("color", { brightness = 1.05, saturation = 1.1, gamma = 0.9 }),

    blue_hour = Trait.new("blue hour, twilight, cool ambient light, serene")
      :hint("color", { saturation = 1.15, gamma = 1.1 }),

    noir = Trait.new("film noir, high contrast, dramatic shadows, low key lighting")
      :hint("color", { contrast = 1.3, saturation = 0.4, gamma = 0.8 }),

    neon = Trait.new("neon lighting, cyberpunk, vivid colors, night city")
      :hint("color", { saturation = 1.3, contrast = 1.1 }),

    soft_light = Trait.new("soft diffused light, overcast, gentle shadows")
      :hint("color", { contrast = 0.9, brightness = 1.05 }),

    dramatic = Trait.new("dramatic lighting, chiaroscuro, strong shadows, cinematic")
      :hint("color", { contrast = 1.2 }),

    vintage = Trait.new("vintage film, grain, faded colors, retro")
      :hint("color", { saturation = 0.7, gamma = 0.95 }),

    bokeh = Trait.new("shallow depth of field, bokeh, f/1.4, dreamy background blur"),
  },
}
