--- Catalog: Setting / Location / Terrain / Architecture.
-- Scene backdrop Traits. SDXL-effective tags only.
-- Target: SDXL 1.0 Base and above.
--
-- Note on framing:
--   Environment tags work best with wider framings
--   (camera.wide_shot, camera.full_body). Close-up shots
--   reduce environment visibility.
--
-- Sources:
--   wolfden/ComfyUi_PromptStylers environment JSON,
--   Avaray/stable-diffusion-simple-wildcards locations (153 entries),
--   Aiarty SD background prompts, PromptHero landscape prompts.

local Trait   = require("vdsl.trait")
local Catalog = require("vdsl.catalog")

return Catalog.new {
  -- === Natural Outdoor ===
  forest = Trait.new("forest, trees, woodland"),

  dense_forest = Trait.new("dense forest", 1.1)
    + Trait.new("thick vegetation, ancient trees, canopy")
    :hint("color", { brightness = 0.95 }),

  mountain = Trait.new("mountain, mountain range"),

  ocean = Trait.new("ocean, vast sea, open water"),

  beach = Trait.new("beach, sandy shore, coastline"),

  desert = Trait.new("desert, arid landscape, sand dunes"),

  meadow = Trait.new("meadow, open field, wildflowers, grass"),

  river = Trait.new("river, flowing water, riverbank"),

  waterfall = Trait.new("waterfall", 1.1)
    + Trait.new("cascading water, lush cliffs"),

  cave = Trait.new("cave, cavern, rocky interior", 1.1)
    :hint("color", { brightness = 0.85 }),

  jungle = Trait.new("jungle, tropical rainforest", 1.1)
    + Trait.new("dense vegetation, humid"),

  lake = Trait.new("lake, calm water, reflections"),

  cliff = Trait.new("cliffside, cliff edge, steep rock face"),

  -- === Urban Outdoor ===
  city_street = Trait.new("city street, urban"),

  rooftop = Trait.new("rooftop, rooftop view, city skyline"),

  alley = Trait.new("alley, narrow alleyway, back street"),

  park = Trait.new("park, public garden, trees, paths"),

  bridge = Trait.new("bridge, spanning over water"),

  harbor = Trait.new("harbor, port, ships, waterfront"),

  marketplace = Trait.new("marketplace, market stalls, vendors", 1.1),

  -- model-dependent: anime finetunes recognize Japanese-specific
  -- locations more reliably than SDXL base.
  shrine = Trait.new("shrine, torii gate", 1.1)
    + Trait.new("stone lantern, sacred grounds"),

  bus_stop = Trait.new("bus stop, waiting, bench, roadside"),

  stairway = Trait.new("stairway, stairs, steps"),

  -- === Transit ===
  train_station = Trait.new("train station, platform", 1.1)
    + Trait.new("railway, station bench"),

  train_interior = Trait.new("train interior, train window", 1.1)
    + Trait.new("seat, handrail, passenger"),

  -- === Indoor ===
  library = Trait.new("library, bookshelves, reading room"),

  cafe = Trait.new("cafe, coffee shop, cozy interior"),

  cathedral = Trait.new("cathedral, grand interior", 1.1)
    + Trait.new("stained glass, vaulted ceiling"),

  workshop = Trait.new("workshop, tools, workbench, craft room"),

  bedroom = Trait.new("bedroom, bed, interior"),

  throne_room = Trait.new("throne room, grand hall", 1.1)
    + Trait.new("ornate throne, royal"),

  kitchen = Trait.new("kitchen, cooking, interior"),

  corridor = Trait.new("corridor, hallway, long passage"),

  convenience_store = Trait.new("convenience store", 1.1)
    + Trait.new("bright fluorescent light, glass door, shelves"),

  classroom = Trait.new("classroom, school desk", 1.1)
    + Trait.new("chalkboard, school interior"),

  dungeon = Trait.new("dungeon, dark stone walls", 1.1)
    + Trait.new("torchlight, underground")
    :hint("color", { brightness = 0.8, contrast = 1.1 }),

  -- === Fantasy ===
  -- model-dependent: anime/fantasy finetunes produce stronger results.
  -- SDXL base recognizes these but with less atmospheric detail.
  enchanted_forest = Trait.new("enchanted forest, magical", 1.1)
    + Trait.new("glowing plants, mystical atmosphere")
    :hint("color", { saturation = 1.15 }),

  ruins = Trait.new("ancient ruins, crumbling stone, overgrown, weathered"),

  ancient_temple = Trait.new("ancient temple, stone pillars", 1.1)
    + Trait.new("sacred architecture"),

  floating_island = Trait.new("floating island, island in the sky", 1.1)
    + Trait.new("floating landmass"),

  crystal_cave = Trait.new("crystal cave, glowing crystals", 1.1)
    + Trait.new("underground cavern, bioluminescent")
    :hint("color", { saturation = 1.2 }),

  -- === Sci-fi ===
  cyberpunk_city = Trait.new("cyberpunk city, neon lights", 1.1)
    + Trait.new("rain-slicked streets, futuristic")
    :hint("color", { saturation = 1.25, contrast = 1.1 }),

  futuristic_city = Trait.new("futuristic city, advanced architecture", 1.1)
    + Trait.new("flying vehicles, sci-fi"),

  space_station = Trait.new("space station, orbital platform", 1.1)
    + Trait.new("sci-fi interior, zero gravity"),

  spaceship_interior = Trait.new("spaceship interior, control panel", 1.1)
    + Trait.new("sci-fi cockpit, futuristic"),
}
