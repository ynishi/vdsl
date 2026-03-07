--- test_color_pack.lua: Tests for color/ pack (palette catalog).
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;tests/?.lua;'..package.path" tests/test_color_pack.lua

local vdsl     = require("vdsl")
local Entity   = require("vdsl.entity")
local T        = require("harness")

print("=== Color Pack Tests ===")

local catalogs = require("vdsl.catalogs")

-- ============================================================
-- Pack lazy-load
-- ============================================================
print("\n--- Pack loading ---")

T.ok("color pack loads",        catalogs.color ~= nil)
T.ok("color.palette loads",     catalogs.color.palette ~= nil)
T.ok("color.hue loads",         catalogs.color.hue ~= nil)

-- ============================================================
-- Palette catalog
-- ============================================================
print("\n--- Palette catalog ---")

local palette = catalogs.color.palette

local palette_expected = {
  "warm_tones", "cool_tones",
  "vibrant", "muted", "desaturated", "pastel",
  "monochrome", "black_and_white", "sepia",
  "high_contrast",
  "earth_tones", "jewel_tones",
  "limited_palette", "complementary",
}

for _, name in ipairs(palette_expected) do
  T.ok("palette." .. name .. " exists", palette[name] ~= nil)
  T.ok("palette." .. name .. " is trait", Entity.is(palette[name], "trait"))
end

T.eq("palette entry count", #palette_expected, 14)

-- Verify resolves
T.ok("palette.monochrome resolves", palette.monochrome:resolve():find("monochrome") ~= nil)
T.ok("palette.warm_tones has emph", palette.warm_tones:resolve():find("%(warm tones") ~= nil)
T.ok("palette.sepia resolves",      palette.sepia:resolve():find("sepia") ~= nil)

-- Verify all palette entries have color hints
for _, name in ipairs(palette_expected) do
  T.ok("palette." .. name .. " has hints", palette[name]:hints() ~= nil)
end

-- ============================================================
-- Hue catalog
-- ============================================================
print("\n--- Hue catalog ---")

local hue = catalogs.color.hue

local hue_expected = {
  -- reds
  "red", "crimson", "scarlet", "burgundy",
  -- blues
  "blue", "navy", "azure", "teal", "indigo",
  -- greens
  "green", "emerald", "olive", "mint", "forest_green",
  -- yellows/golds
  "yellow", "gold", "amber",
  -- purples
  "purple", "violet", "lavender", "magenta",
  -- oranges/pinks
  "orange", "coral", "pink", "peach",
  -- neutrals
  "white", "black", "silver", "gray", "ivory",
  -- metallics
  "gold_metallic", "silver_metallic", "copper", "bronze",
}

for _, name in ipairs(hue_expected) do
  T.ok("hue." .. name .. " exists", hue[name] ~= nil)
  T.ok("hue." .. name .. " is trait", Entity.is(hue[name], "trait"))
end

T.eq("hue entry count", #hue_expected, 34)

-- Verify resolves
T.ok("hue.red resolves",     hue.red:resolve():find("red") ~= nil)
T.ok("hue.teal resolves",    hue.teal:resolve():find("teal") ~= nil)
T.ok("hue.gold resolves",    hue.gold:resolve():find("golden") ~= nil)
T.ok("hue.lavender resolves", hue.lavender:resolve():find("lavender") ~= nil)

-- ============================================================
-- Composability
-- ============================================================
print("\n--- Composability ---")

-- Color + Scene
local setting = catalogs.environment.setting
local s = vdsl.subject("japanese garden")
  :with(setting.park)
  :with(palette.warm_tones)

local resolved = s:resolve()
T.ok("compose: has park",       resolved:find("park") ~= nil)
T.ok("compose: has warm tones", resolved:find("warm tones") ~= nil)

-- Color + Style
local style = catalogs.style
local s2 = vdsl.subject("portrait of a woman")
  :with(style.cinematic)
  :with(palette.desaturated)

local r2 = s2:resolve()
T.ok("compose+style: has cinematic",   r2:find("cinematic") ~= nil)
T.ok("compose+style: has desaturated", r2:find("desaturated") ~= nil)

-- Monochrome pipeline
local w = vdsl.world { model = "model.safetensors" }

local mono_scene = vdsl.cast {
  subject = vdsl.subject("city skyline")
    :with(palette.monochrome)
    :with(palette.high_contrast)
    :quality("high"),
}

local result = vdsl.render {
  world = w,
  cast  = { mono_scene },
  seed  = 42,
  steps = 20,
}

T.ok("pipeline: has json", #result.json > 100)

local found = false
for _, node in pairs(result.prompt) do
  if node.class_type == "CLIPTextEncode" then
    local text = node.inputs.text
    if text:find("monochrome") and text:find("high contrast") then
      found = true
    end
  end
end
T.ok("pipeline: color traits in prompt", found)

-- ============================================================
-- Safety
-- ============================================================
print("\n--- Safety ---")

T.ok("palette.nonexistent is nil", palette.nonexistent == nil)
T.ok("color.nonexistent is nil",   catalogs.color.nonexistent == nil)

T.summary()
