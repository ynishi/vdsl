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
  forest = Trait.new("forest, trees, woodland")
    :desc("a forest with trees and woodland"),

  dense_forest = Trait.new("dense forest", 1.1)
    + Trait.new("thick vegetation, ancient trees, canopy")
    :hint("color", { brightness = 0.95 })
    :desc("a dense forest with thick vegetation, ancient trees, and a canopy overhead"),

  mountain = Trait.new("mountain, mountain range")
    :desc("a mountain or mountain range"),

  ocean = Trait.new("ocean, vast sea, open water")
    :desc("a vast open ocean"),

  beach = Trait.new("beach, sandy shore, coastline")
    :desc("a sandy beach along the coastline"),

  desert = Trait.new("desert, arid landscape, sand dunes")
    :desc("an arid desert landscape with sand dunes"),

  meadow = Trait.new("meadow, open field, wildflowers, grass")
    :desc("an open meadow with wildflowers and grass"),

  river = Trait.new("river, flowing water, riverbank")
    :desc("a river with flowing water along the riverbank"),

  waterfall = Trait.new("waterfall", 1.1)
    + Trait.new("cascading water, lush cliffs")
    :desc("a waterfall cascading down lush cliffs"),

  cave = Trait.new("cave, cavern, rocky interior", 1.1)
    :hint("color", { brightness = 0.85 })
    :desc("a cave or cavern with a dark rocky interior"),

  jungle = Trait.new("jungle, tropical rainforest", 1.1)
    + Trait.new("dense vegetation, humid")
    :desc("a tropical jungle rainforest with dense humid vegetation"),

  lake = Trait.new("lake, calm water, reflections")
    :desc("a calm lake with water reflections"),

  cliff = Trait.new("cliffside, cliff edge, steep rock face")
    :desc("a steep cliff edge with a rock face"),

  -- === Urban Outdoor ===
  city_street = Trait.new("city street, urban")
    :desc("an urban city street"),

  rooftop = Trait.new("rooftop, rooftop view, city skyline")
    :desc("a rooftop with a city skyline view"),

  alley = Trait.new("alley, narrow alleyway, back street")
    :desc("a narrow back-street alleyway"),

  park = Trait.new("park, public garden, trees, paths")
    :desc("a public park with gardens, trees, and paths"),

  bridge = Trait.new("bridge, spanning over water")
    :desc("a bridge spanning over water"),

  harbor = Trait.new("harbor, port, ships, waterfront")
    :desc("a harbor port with ships at the waterfront"),

  marketplace = Trait.new("marketplace, market stalls, vendors", 1.1)
    :desc("a bustling marketplace with stalls and vendors"),

  shrine = Trait.new("shrine, torii gate", 1.1)
    + Trait.new("stone lantern, sacred grounds")
    :desc("a Japanese shrine with a torii gate, stone lanterns, and sacred grounds"),

  bus_stop = Trait.new("bus stop, waiting, bench, roadside")
    :desc("a roadside bus stop with a bench"),

  stairway = Trait.new("stairway, stairs, steps")
    :desc("a stairway with steps"),

  -- === Transit ===
  train_station = Trait.new("train station, platform", 1.1)
    + Trait.new("railway, station bench")
    :desc("a train station platform with railway tracks and benches"),

  train_interior = Trait.new("train interior, train window", 1.1)
    + Trait.new("seat, handrail, passenger")
    :desc("inside a train car with seats, handrails, and a window view"),

  -- === Indoor ===
  library = Trait.new("library, bookshelves, reading room")
    :desc("a library with bookshelves and a reading room"),

  cafe = Trait.new("cafe, coffee shop, cozy interior")
    :desc("a cozy cafe or coffee shop interior"),

  cathedral = Trait.new("cathedral, grand interior", 1.1)
    + Trait.new("stained glass, vaulted ceiling")
    :desc("a grand cathedral interior with stained glass windows and vaulted ceilings"),

  workshop = Trait.new("workshop, tools, workbench, craft room")
    :desc("a workshop with tools and a workbench"),

  bedroom = Trait.new("bedroom, bed, interior")
    :desc("a bedroom interior"),

  throne_room = Trait.new("throne room, grand hall", 1.1)
    + Trait.new("ornate throne, royal")
    :desc("a grand royal throne room with an ornate throne"),

  kitchen = Trait.new("kitchen, cooking, interior")
    :desc("a kitchen interior"),

  corridor = Trait.new("corridor, hallway, long passage")
    :desc("a long corridor or hallway"),

  convenience_store = Trait.new("convenience store", 1.1)
    + Trait.new("bright fluorescent light, glass door, shelves")
    :desc("inside a convenience store with fluorescent lighting and shelves"),

  classroom = Trait.new("classroom, school desk", 1.1)
    + Trait.new("chalkboard, school interior")
    :desc("a school classroom with desks and a chalkboard"),

  dungeon = Trait.new("dungeon, dark stone walls", 1.1)
    + Trait.new("torchlight, underground")
    :hint("color", { brightness = 0.8, contrast = 1.1 })
    :desc("a dark underground dungeon with stone walls lit by torchlight"),

  -- === Fantasy ===
  enchanted_forest = Trait.new("enchanted forest, magical", 1.1)
    + Trait.new("glowing plants, mystical atmosphere")
    :hint("color", { saturation = 1.15 })
    :desc("an enchanted magical forest with glowing plants and a mystical atmosphere"),

  ruins = Trait.new("ancient ruins, crumbling stone, overgrown, weathered")
    :desc("ancient weathered ruins with crumbling overgrown stone"),

  ancient_temple = Trait.new("ancient temple, stone pillars", 1.1)
    + Trait.new("sacred architecture")
    :desc("an ancient temple with stone pillars and sacred architecture"),

  floating_island = Trait.new("floating island, island in the sky", 1.1)
    + Trait.new("floating landmass")
    :desc("a floating island suspended in the sky"),

  crystal_cave = Trait.new("crystal cave, glowing crystals", 1.1)
    + Trait.new("underground cavern, bioluminescent")
    :hint("color", { saturation = 1.2 })
    :desc("an underground crystal cave with glowing bioluminescent crystals"),

  -- === Sci-fi ===
  cyberpunk_city = Trait.new("cyberpunk city, neon lights", 1.1)
    + Trait.new("rain-slicked streets, futuristic")
    :hint("color", { saturation = 1.25, contrast = 1.1 })
    :desc("a cyberpunk city with neon lights reflecting off rain-slicked futuristic streets"),

  futuristic_city = Trait.new("futuristic city, advanced architecture", 1.1)
    + Trait.new("flying vehicles, sci-fi")
    :desc("a futuristic city with advanced architecture and flying vehicles"),

  space_station = Trait.new("space station, orbital platform", 1.1)
    + Trait.new("sci-fi interior, zero gravity")
    :desc("a space station orbital platform with a sci-fi zero-gravity interior"),

  spaceship_interior = Trait.new("spaceship interior, control panel", 1.1)
    + Trait.new("sci-fi cockpit, futuristic")
    :desc("inside a spaceship cockpit with futuristic control panels"),
}
