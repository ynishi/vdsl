--- 09_zimage_showcase.lua: Z-Image Turbo capability showcase
-- Demonstrates Z-Image Turbo across multiple domains:
--   Part 1: Cinematic scenes (rain Tokyo, noir detective, solarpunk, seasons)
--   Part 2: Portrait photography styles
--   Part 3: Anime / illustration styles
--   Part 4: Fantasy / SF / concept art
--   Part 5: Catalog vs natural language comparison
--
-- Run (compile only):
--   lua -e "package.path='lua/?.lua;lua/?/init.lua;'..package.path" examples/09_zimage_showcase.lua
--
-- Run (compile + generate via vdsl_run MCP):
--   vdsl_run(script_file="examples/09_zimage_showcase.lua", working_dir=".")

local vdsl   = require("vdsl")
local zimage = require("vdsl.compilers.zimage")
local C      = require("vdsl.catalogs")

-- ============================================================
-- World: Z-Image Turbo
-- ============================================================

local w = vdsl.world {
  model = "z_image_turbo_fp16.safetensors",
  vae   = "ae.safetensors",
}

local text_encoder = "qwen_3_4b_bf16.safetensors"

-- ============================================================
-- Part 1: Cinematic scenes
-- ============================================================

local scenes = {
  -- === Rain Tokyo ===
  {
    name   = "rain_yamanote",
    prompt = "Interior of a Tokyo Yamanote Line train on a rainy morning, water droplets streaming down window glass, blurred neon city lights outside, empty green seats, warm fluorescent lighting inside, melancholic atmosphere, cinematic photography, 35mm film grain, shallow depth of field",
    size   = { 1344, 768 },
    seed   = 20001,
  },
  {
    name   = "rain_hydrangea",
    prompt = "Close-up of blue and purple hydrangea flowers in full bloom during Japanese rainy season, raindrops on petals, a traditional wooden fence in soft bokeh background, overcast diffused light, macro photography, warm film color tones, moody and serene",
    size   = { 1024, 1024 },
    seed   = 20002,
  },
  {
    name   = "rain_izakaya",
    prompt = "Narrow Tokyo alleyway at night in heavy rain, warm golden light spilling from a tiny izakaya entrance with noren curtains, red paper lantern reflecting on wet cobblestones, steam rising from a kitchen vent, cinematic noir lighting, 50mm prime lens",
    size   = { 832, 1248 },
    seed   = 20003,
  },

  -- === Noir Detective ===
  {
    name   = "noir_office",
    prompt = "Film noir detective sitting alone in a dark 1940s office, single desk lamp casting dramatic shadows through venetian blinds, cigarette smoke curling upward, fedora hat on desk, glass of whiskey, black and white photography with slight sepia tone, high contrast chiaroscuro lighting",
    size   = { 1344, 768 },
    seed   = 30001,
  },
  {
    name   = "noir_alley",
    prompt = "Silhouette of a man in a trench coat and fedora walking down a rain-slicked alley at night, single streetlamp creating a pool of light, long dramatic shadow stretching forward, wet brick walls, 1940s film noir aesthetic, black and white, strong rim lighting",
    size   = { 832, 1248 },
    seed   = 30002,
  },

  -- === Solarpunk City ===
  {
    name   = "solar_skyline",
    prompt = "Breathtaking panoramic view of a solarpunk city skyline at golden hour, organic architecture covered in lush vertical gardens, transparent solar panel rooftops glowing amber, elevated greenway bridges connecting towers, flocks of birds in warm sunset sky, utopian futuristic cityscape, architectural visualization, ultra detailed",
    size   = { 1568, 672 },
    seed   = 40001,
  },
  {
    name   = "solar_market",
    prompt = "Bustling open-air market inside a solarpunk greenhouse dome, sunlight filtering through translucent solar glass ceiling, vendors selling colorful produce at wooden stalls wrapped in flowering vines, children playing near a small waterfall fountain, warm natural lighting, wide angle photography, vibrant colors",
    size   = { 1344, 768 },
    seed   = 40002,
  },
  {
    name   = "solar_garden",
    prompt = "Rooftop community garden in a solarpunk city, raised wooden planting beds overflowing with vegetables and herbs, small wind turbines and solar panels integrated into bamboo trellises, a person in casual clothing watering plants, city skyline with green towers in background, late afternoon golden light, lifestyle photography",
    size   = { 1248, 832 },
    seed   = 40003,
  },

  -- === Seasons Station (same seed, different seasons) ===
  {
    name   = "station_spring",
    prompt = "Small rural Japanese train station platform in spring, cherry blossom trees in full bloom with petals drifting across the tracks, a single-car local train approaching, wooden station bench, soft overcast morning light, nostalgic pastoral atmosphere, hand-painted animation background art, watercolor-like soft tones",
    size   = { 1344, 768 },
    seed   = 50001,
  },
  {
    name   = "station_summer",
    prompt = "Same rural Japanese train station in midsummer, intense green foliage, cicada-season heat haze rising from the tracks, cumulus clouds towering in deep blue sky, sunflowers growing beside the platform, a red vending machine in shade, harsh midday sunlight with strong shadows, vivid saturated colors",
    size   = { 1344, 768 },
    seed   = 50001,
  },
  {
    name   = "station_autumn",
    prompt = "Rural Japanese train station in autumn, maple and ginkgo trees in brilliant red and gold foliage, fallen leaves scattered on the platform, a departing train's red taillights, early evening amber light, thin clouds streaked across orange sky, melancholic beauty, warm earth tones, Japanese countryside photography",
    size   = { 1344, 768 },
    seed   = 50001,
  },
  {
    name   = "station_winter",
    prompt = "Rural Japanese train station in deep winter, heavy snow covering the platform and tracks, bare dark tree branches against grey sky, a single warm yellow light inside the waiting room, footprints in fresh snow leading to the entrance, falling snowflakes, quiet solitude, cold blue-white tones with warm interior glow",
    size   = { 1344, 768 },
    seed   = 50001,
  },

  -- ============================================================
  -- Part 2: Portrait photography
  -- ============================================================

  {
    name   = "portrait_mediterranean",
    prompt = "Professional portrait photography of a young Japanese woman sitting on white stone steps in a Mediterranean hillside village, wearing a light blue long flowing skirt and white cotton blouse, bright afternoon sunlight casting clean shadows on whitewashed walls, bougainvillea flowers cascading down a blue door in the background, warm travel photography aesthetic, natural smile looking at camera, mirrorless camera with warm film tones, 56mm f/1.2 lens, shallow depth of field",
    size   = { 832, 1248 },
    seed   = 70011,
  },
  {
    name   = "portrait_casual",
    prompt = "Candid street photography of a stylish young Japanese woman in a cafe, oversized knit sweater falling off one shoulder, holding a coffee cup, window light illuminating her face, bokeh city street outside, natural smile, mirrorless camera with warm film tones, 56mm f/1.2 lens",
    size   = { 832, 1248 },
    seed   = 70005,
  },

  -- ============================================================
  -- Part 3: Anime / illustration styles
  -- ============================================================

  {
    name   = "anime_schoolgirl",
    prompt = "Beautiful anime girl in a Japanese high school uniform standing under cherry blossom trees, petals falling around her, gentle smile, wind blowing through long black hair, spring afternoon, soft pastel colors, anime key visual illustration, high quality animation art",
    size   = { 832, 1248 },
    seed   = 80001,
  },
  {
    name   = "illust_watercolor",
    prompt = vdsl.subject("young girl reading a book in a sunlit garden, surrounded by wildflowers and butterflies")
      :with(C.style.watercolor)
      :with(C.lighting.dappled)
      :with(C.atmosphere.peaceful),
    size   = { 1248, 832 },
    seed   = 80002,
  },
  {
    name   = "illust_ukiyoe",
    prompt = vdsl.subject("great wave crashing against rocky shore, Mount Fuji in distance, fishing boats tossed by waves")
      :with(C.style.ukiyo_e),
    size   = { 1344, 768 },
    seed   = 80003,
  },
  {
    name   = "illust_nouveau",
    prompt = vdsl.subject("elegant woman with flowing auburn hair holding a lily, ornamental floral frame surrounding the figure")
      :with(C.style.art_nouveau)
      :with(C.lighting.soft_studio),
    size   = { 832, 1248 },
    seed   = 80004,
  },
  {
    name   = "anime_action",
    prompt = "Dynamic anime battle scene, a female samurai in traditional armor mid-slash with a glowing katana, cherry blossom petals frozen in the air, dramatic speed lines, intense expression, dark stormy background with lightning, vibrant cel shading, anime key frame illustration",
    size   = { 1344, 768 },
    seed   = 80005,
  },
  {
    name   = "illust_pastoral",
    prompt = "Hand-painted pastoral landscape, a small European cottage on a grassy hillside overlooking a vast blue sea, fluffy cumulus clouds in bright sky, laundry hanging on a clothesline, a girl with a straw hat walking up a winding dirt path, warm afternoon light, traditional animation background art, painterly soft edges",
    size   = { 1344, 768 },
    seed   = 80006,
  },

  -- ============================================================
  -- Part 4: Fantasy / SF / concept art
  -- ============================================================

  {
    name   = "fantasy_knight",
    prompt = vdsl.subject("female knight in ornate silver plate armor standing before a massive dragon, sword raised, cape billowing in wind")
      :with(C.camera.low_angle)
      :with(C.lighting.volumetric)
      :with(C.atmosphere.epic),
    size   = { 832, 1248 },
    seed   = 90001,
  },
  {
    name   = "sf_cyberpunk",
    prompt = "Cyberpunk hacker girl sitting in a dark room surrounded by floating holographic screens, neon-lit cables connected to neural implants, short white hair with cyan highlights, black leather jacket, rain visible through a grimy window, dystopian cyberpunk aesthetic, hard sci-fi illustration, concept art",
    size   = { 1344, 768 },
    seed   = 90002,
  },
  {
    name   = "sf_mecha",
    prompt = "Colossal humanoid mecha standing in a devastated urban battlefield at sunset, pilot visible in open cockpit, smoke and debris floating in orange light, military helicopters circling overhead, weathered battle-damaged armor with unit markings, realistic mechanical design, classic mecha anime aesthetic, cinematic concept art",
    size   = { 832, 1248 },
    seed   = 90003,
  },
  {
    name   = "fantasy_witch",
    prompt = vdsl.subject("beautiful witch in a moonlit ancient forest, long silver hair, flowing dark violet robes, holding a glowing crystal orb, ancient rune stones surrounding her")
      :with(C.lighting.low_key)
      :with(C.atmosphere.mysterious)
      :with(C.camera.full_body),
    size   = { 832, 1248 },
    seed   = 90004,
  },
  {
    name   = "sf_space",
    prompt = "Vast space station orbiting a gas giant planet with swirling storm bands, a sleek starship approaching the docking bay, nebula glowing in deep purple and gold in the background, hard science fiction, cinematic wide shot, photorealistic space art, retro-futuristic spacecraft design",
    size   = { 1568, 672 },
    seed   = 90005,
  },
  {
    name   = "illust_oil",
    prompt = vdsl.subject("still life arrangement of autumn harvest on a wooden table, pumpkins, grapes, brass candlestick, a half-peeled lemon, draped velvet cloth")
      :with(C.style.oil)
      :with(C.lighting.chiaroscuro),
    size   = { 1248, 832 },
    seed   = 90006,
  },

  -- ============================================================
  -- Part 5: Catalog vs natural language comparison
  -- Same seeds to compare output quality between approaches.
  -- ============================================================

  -- Catalog-composed prompts
  {
    name   = "cat_portrait_studio",
    prompt = vdsl.subject("beautiful young Japanese woman in elegant black dress")
      :with(C.camera.bust_shot)
      :with(C.camera.portrait_lens)
      :with(C.lighting.rembrandt),
    size   = { 832, 1248 },
    seed   = 60001,
  },
  {
    name   = "cat_pose_golden",
    prompt = vdsl.subject("young woman in white summer dress, flower field")
      :with(C.figure.pose.contrapposto)
      :with(C.camera.full_body)
      :with(C.lighting.golden_hour),
    size   = { 832, 1248 },
    seed   = 60002,
  },
  {
    name   = "cat_multi_combine",
    prompt = vdsl.subject("woman with long black hair, traditional Japanese kimono, garden")
      :with(C.camera.medium_shot)
      :with(C.camera.shallow_dof)
      :with(C.lighting.dappled)
      :with(C.figure.pose.looking_at_viewer),
    size   = { 832, 1248 },
    seed   = 60003,
  },

  -- Same concepts, pure natural language (same seeds for A/B comparison)
  {
    name   = "nl_portrait_studio",
    prompt = "Upper body portrait of a beautiful young Japanese woman in an elegant black dress, Rembrandt lighting with triangle shadow on cheek, 85mm lens with shallow depth of field and bokeh, studio photography",
    size   = { 832, 1248 },
    seed   = 60001,
  },
  {
    name   = "nl_pose_golden",
    prompt = "Full body shot of a young woman in a white summer dress standing in a flower field, contrapposto S-curve pose, golden hour warm sunlight with long shadows, portrait photography",
    size   = { 832, 1248 },
    seed   = 60002,
  },
  {
    name   = "nl_multi_combine",
    prompt = "Medium shot of a woman with long black hair wearing a traditional Japanese kimono in a garden, sunlight filtering through leaves creating dappled light patterns, looking directly at the viewer, shallow depth of field with soft bokeh background",
    size   = { 832, 1248 },
    seed   = 60003,
  },
}

-- ============================================================
-- Compile & emit all scenes
-- ============================================================

print("=== Z-Image Turbo Showcase ===")
print(string.format("  model: %s", w.model))
print(string.format("  scenes: %d\n", #scenes))

for _, scene in ipairs(scenes) do
  local cast = vdsl.cast { subject = scene.prompt }

  local result = zimage.compile {
    world        = w,
    cast         = { cast },
    seed         = scene.seed,
    size         = scene.size,
    text_encoder = text_encoder,
    auto_post    = false,
  }

  vdsl.emit(scene.name, result)

  local resolved = type(scene.prompt) == "string"
    and scene.prompt:sub(1, 60)
    or  tostring(scene.prompt):sub(1, 60)

  print(string.format("  %-22s %dx%d  seed=%d  prompt=%.60s...",
    scene.name,
    scene.size[1], scene.size[2],
    scene.seed,
    resolved))
end

print(string.format("\nDone. %d scenes compiled.", #scenes))
