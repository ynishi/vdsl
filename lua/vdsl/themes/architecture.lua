--- Theme: Architecture / Procedural
-- Traits for architectural visualization and procedural generation.

local Trait = require("vdsl.trait")
local Theme = require("vdsl.theme")

return Theme.new {
  name     = "architecture",
  category = "visualization",
  tags     = { "archviz", "procedural", "3d", "environment" },
  defaults = {
    steps     = 35,
    cfg       = 7.0,
    sampler   = "euler",
    scheduler = "normal",
    size      = { 1024, 1024 },
  },
  negatives = {
    default = Trait.new("cartoon, anime, sketch, low detail, blurry"),
    quality = Trait.new("low quality, worst quality, jpeg artifacts, watermark"),
  },
  traits   = {
    exterior = Trait.new("architectural exterior, building facade, urban, photorealistic")
      :hint("hires", { scale = 1.5, denoise = 0.35 }),

    interior = Trait.new("interior design, room, furniture, ambient lighting")
      :hint("color", { brightness = 1.05 }),

    aerial = Trait.new("aerial view, bird's eye, urban planning, top-down perspective")
      :hint("hires", { scale = 2.0, denoise = 0.4 }),

    blueprint = Trait.new("architectural blueprint, technical drawing, wireframe, schematic")
      :hint("sharpen", { radius = 2, sigma = 1.0 }),

    organic = Trait.new("organic architecture, biomimicry, flowing forms, parametric design"),

    brutalist = Trait.new("brutalist architecture, raw concrete, monolithic, geometric")
      :hint("color", { contrast = 1.15, saturation = 0.8 }),

    futuristic = Trait.new("futuristic architecture, sci-fi, sleek, glass and metal")
      :hint("color", { contrast = 1.1 }),

    landscape = Trait.new("landscape architecture, garden design, natural elements, greenery")
      :hint("color", { saturation = 1.15, brightness = 1.05 }),
  },
}
