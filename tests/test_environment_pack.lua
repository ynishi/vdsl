--- test_environment_pack.lua: Tests for environment/ pack (setting, weather, time catalogs).
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;tests/?.lua;'..package.path" tests/test_environment_pack.lua

local vdsl     = require("vdsl")
local Entity   = require("vdsl.entity")
local T        = require("harness")

print("=== Environment Pack Tests ===")

local catalogs = require("vdsl.catalogs")

-- ============================================================
-- Pack lazy-load
-- ============================================================
print("\n--- Pack loading ---")

T.ok("environment pack loads",     catalogs.environment ~= nil)
T.ok("environment.setting loads",  catalogs.environment.setting ~= nil)
T.ok("environment.weather loads",  catalogs.environment.weather ~= nil)
T.ok("environment.time loads",     catalogs.environment.time ~= nil)

-- ============================================================
-- Setting catalog
-- ============================================================
print("\n--- Setting catalog ---")

local setting = catalogs.environment.setting

local setting_expected = {
  -- natural
  "forest", "dense_forest", "mountain", "ocean", "beach", "desert",
  "meadow", "river", "waterfall", "cave", "jungle", "lake", "cliff",
  -- urban
  "city_street", "rooftop", "alley", "park", "bridge", "harbor", "marketplace",
  -- indoor
  "library", "cafe", "cathedral", "workshop", "bedroom", "throne_room",
  "kitchen", "corridor", "dungeon",
  -- fantasy
  "enchanted_forest", "ruins", "ancient_temple", "floating_island", "crystal_cave",
  -- sci-fi
  "cyberpunk_city", "futuristic_city", "space_station", "spaceship_interior",
}

for _, name in ipairs(setting_expected) do
  T.ok("setting." .. name .. " exists", setting[name] ~= nil)
  T.ok("setting." .. name .. " is trait", Entity.is(setting[name], "trait"))
end

T.eq("setting entry count", #setting_expected, 38)

-- Verify resolves
T.ok("setting.forest resolves", setting.forest:resolve():find("forest") ~= nil)
T.ok("setting.cyberpunk has emph", setting.cyberpunk_city:resolve():find("%(cyberpunk city") ~= nil)

-- Verify hints on tagged entries
T.ok("setting.cave has hints", setting.cave:hints() ~= nil)
T.ok("setting.dungeon has hints", setting.dungeon:hints() ~= nil)
T.ok("setting.cyberpunk_city has hints", setting.cyberpunk_city:hints() ~= nil)

-- ============================================================
-- Weather catalog
-- ============================================================
print("\n--- Weather catalog ---")

local weather = catalogs.environment.weather

local weather_expected = {
  "clear_sky", "cloudy", "overcast", "rain", "heavy_rain",
  "snow", "blizzard", "fog", "mist", "storm", "thunder",
  "wind", "aurora", "rainbow",
}

for _, name in ipairs(weather_expected) do
  T.ok("weather." .. name .. " exists", weather[name] ~= nil)
  T.ok("weather." .. name .. " is trait", Entity.is(weather[name], "trait"))
end

T.eq("weather entry count", #weather_expected, 14)

T.ok("weather.rain resolves", weather.rain:resolve():find("rain") ~= nil)
T.ok("weather.rain has emph", weather.rain:resolve():find("%(rain") ~= nil)
T.ok("weather.fog has hints", weather.fog:hints() ~= nil)
T.ok("weather.aurora has hints", weather.aurora:hints() ~= nil)

-- ============================================================
-- Time catalog
-- ============================================================
print("\n--- Time catalog ---")

local time_cat = catalogs.environment.time

local time_expected = {
  -- time of day
  "dawn", "sunrise", "morning", "midday", "afternoon",
  "sunset", "dusk", "twilight", "night", "midnight", "moonlight",
  -- season (basic)
  "spring", "summer", "autumn", "winter",
  -- season (phenomena)
  "cherry_blossom", "wisteria", "sunflower_field", "fireflies",
  "fallen_leaves", "maple_leaves", "first_snow", "winter_frost", "frozen_lake",
  -- season (weather crossover)
  "spring_rain", "summer_thunder", "autumn_wind", "harvest_moon",
}

for _, name in ipairs(time_expected) do
  T.ok("time." .. name .. " exists", time_cat[name] ~= nil)
  T.ok("time." .. name .. " is trait", Entity.is(time_cat[name], "trait"))
end

T.eq("time entry count", #time_expected, 28)

T.ok("time.night resolves", time_cat.night:resolve():find("night") ~= nil)
T.ok("time.night has hints", time_cat.night:hints() ~= nil)
T.ok("time.autumn resolves", time_cat.autumn:resolve():find("autumn") ~= nil)
T.ok("time.spring has hints", time_cat.spring:hints() ~= nil)

-- ============================================================
-- Composability
-- ============================================================
print("\n--- Composability ---")

local s = vdsl.subject("landscape")
  :with(setting.forest)
  :with(weather.rain)
  :with(time_cat.night)

local resolved = s:resolve()
T.ok("compose: has forest", resolved:find("forest") ~= nil)
T.ok("compose: has rain",   resolved:find("rain") ~= nil)
T.ok("compose: has night",  resolved:find("night") ~= nil)

-- Cross-pack composability
local camera = catalogs.camera
local pose   = catalogs.figure.pose

local s2 = vdsl.subject("1girl, solo")
  :with(pose.standing)
  :with(setting.cyberpunk_city)
  :with(weather.rain)
  :with(time_cat.night)
  :with(camera.full_body)

local r2 = s2:resolve()
T.ok("cross-pack: has standing",  r2:find("standing") ~= nil)
T.ok("cross-pack: has cyberpunk", r2:find("cyberpunk") ~= nil)
T.ok("cross-pack: has rain",     r2:find("rain") ~= nil)
T.ok("cross-pack: has full body", r2:find("full body") ~= nil)

-- ============================================================
-- Pipeline integration
-- ============================================================
print("\n--- Pipeline integration ---")

local w = vdsl.world { model = "model.safetensors" }

local scene = vdsl.cast {
  subject = vdsl.subject("enchanted landscape")
    :with(setting.enchanted_forest)
    :with(weather.mist)
    :with(time_cat.moonlight)
    :quality("high"),
}

local result = vdsl.render {
  world = w,
  cast  = { scene },
  seed  = 42,
  steps = 20,
}

T.ok("pipeline: has json", #result.json > 100)

local found = false
for _, node in pairs(result.prompt) do
  if node.class_type == "CLIPTextEncode" then
    local text = node.inputs.text
    if text:find("enchanted") and text:find("mist") and text:find("moonlit") then
      found = true
    end
  end
end
T.ok("pipeline: environment traits in prompt", found)

-- ============================================================
-- Safety
-- ============================================================
print("\n--- Safety ---")

T.ok("setting.nonexistent is nil",     setting.nonexistent == nil)
T.ok("weather.nonexistent is nil",     weather.nonexistent == nil)
T.ok("time.nonexistent is nil",        time_cat.nonexistent == nil)
T.ok("environment.nonexistent is nil", catalogs.environment.nonexistent == nil)

T.summary()
