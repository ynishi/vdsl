--- test_effect.lua: Tests for effect catalog (visual effects).
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;tests/?.lua;'..package.path" tests/test_effect.lua

local vdsl     = require("vdsl")
local Entity   = require("vdsl.entity")
local Catalog  = require("vdsl.catalog")
local T        = require("harness")

print("=== Effect Catalog Tests ===")

local catalogs = require("vdsl.catalogs")

-- ============================================================
-- Catalog loading
-- ============================================================
print("\n--- Loading ---")

T.ok("effect catalog loads", catalogs.effect ~= nil)

local effect = catalogs.effect

-- ============================================================
-- Entry existence and type
-- ============================================================
print("\n--- Entry existence ---")

local expected = {
  "bloom", "light_particles", "lens_flare",
  "film_grain", "vignette",
  "motion_blur",
  "double_exposure", "spot_color", "glitch",
  "chromatic_aberration", "halation", "light_leak",
  "confetti", "bubbles", "butterflies", "feathers", "scattered_papers",
  "embers",
}

for _, name in ipairs(expected) do
  T.ok("effect." .. name .. " exists", effect[name] ~= nil)
  T.ok("effect." .. name .. " is trait", Entity.is(effect[name], "trait"))
end

-- Entry count matches
local count = 0
for _ in pairs(effect) do count = count + 1 end
T.eq("effect entry count", count, #expected)

-- ============================================================
-- Resolve output
-- ============================================================
print("\n--- Resolve output ---")

-- Each entry resolves to non-empty string
for _, name in ipairs(expected) do
  local text = effect[name]:resolve()
  T.ok("effect." .. name .. " resolves non-empty",
    type(text) == "string" and #text > 0)
end

-- Spot-check keyword presence
T.ok("bloom contains bloom",
  effect.bloom:resolve():find("bloom") ~= nil)
T.ok("film_grain contains grain",
  effect.film_grain:resolve():find("grain") ~= nil)
T.ok("motion_blur contains motion",
  effect.motion_blur:resolve():find("motion") ~= nil)
T.ok("double_exposure contains double",
  effect.double_exposure:resolve():find("double") ~= nil)
T.ok("glitch contains glitch",
  effect.glitch:resolve():find("glitch") ~= nil)
T.ok("spot_color contains color",
  effect.spot_color:resolve():find("color") ~= nil)
T.ok("vignette contains vignett",
  effect.vignette:resolve():find("vignett") ~= nil)
T.ok("light_particles contains particles",
  effect.light_particles:resolve():find("particles") ~= nil)
T.ok("lens_flare contains flare",
  effect.lens_flare:resolve():find("flare") ~= nil)
T.ok("confetti contains confetti",
  effect.confetti:resolve():find("confetti") ~= nil)
T.ok("bubbles contains bubbles",
  effect.bubbles:resolve():find("bubbles") ~= nil)
T.ok("butterflies contains butterflies",
  effect.butterflies:resolve():find("butterflies") ~= nil)
T.ok("feathers contains feathers",
  effect.feathers:resolve():find("feathers") ~= nil)
T.ok("scattered_papers contains papers",
  effect.scattered_papers:resolve():find("papers") ~= nil)
T.ok("embers contains embers",
  effect.embers:resolve():find("embers") ~= nil)

-- ============================================================
-- Composability
-- ============================================================
print("\n--- Composability ---")

-- effect + effect
local combo1 = effect.bloom + effect.film_grain
T.ok("bloom + film_grain is trait", Entity.is(combo1, "trait"))
local r1 = combo1:resolve()
T.ok("combo contains bloom", r1:find("bloom") ~= nil)
T.ok("combo contains grain", r1:find("grain") ~= nil)

-- effect + string
local combo2 = effect.glitch + "cyberpunk aesthetic"
T.ok("glitch + string is trait", Entity.is(combo2, "trait"))
local r2 = combo2:resolve()
T.ok("combo2 contains glitch", r2:find("glitch") ~= nil)
T.ok("combo2 contains cyberpunk", r2:find("cyberpunk") ~= nil)

-- effect + lighting (cross-catalog)
local lighting = catalogs.lighting
T.ok("lighting loads", lighting ~= nil)

local combo3 = effect.bloom + lighting.golden_hour
T.ok("bloom + golden_hour is trait", Entity.is(combo3, "trait"))
local r3 = combo3:resolve()
T.ok("cross-catalog: contains bloom", r3:find("bloom") ~= nil)
T.ok("cross-catalog: contains golden", r3:find("golden") ~= nil)

-- effect + style (cross-catalog)
local style = catalogs.style
T.ok("style loads", style ~= nil)

local combo4 = effect.film_grain + style.anime
T.ok("film_grain + anime is trait", Entity.is(combo4, "trait"))
local r4 = combo4:resolve()
T.ok("cross-catalog: contains grain", r4:find("grain") ~= nil)
T.ok("cross-catalog: contains anime", r4:find("anime") ~= nil)

-- ============================================================
-- Pipeline integration
-- ============================================================
print("\n--- Pipeline integration ---")

local World    = require("vdsl.world")
local Cast     = require("vdsl.cast")
local Subject  = require("vdsl.subject")
local compiler = require("vdsl.compiler")

local subj = Subject.new("1girl, white dress")
  :with(effect.bloom)

local result = compiler.compile({
  world = World.new({ model = "test.safetensors" }),
  cast  = { Cast.new({ subject = subj }) },
  seed  = 42,
})

local found_bloom = false
for _, node in pairs(result.prompt) do
  if node.class_type == "CLIPTextEncode" then
    local text = node.inputs.text
    if type(text) == "string" and text:find("bloom") then
      found_bloom = true
    end
  end
end
T.ok("pipeline: bloom in positive prompt", found_bloom)

-- ============================================================
-- vdsl.catalogs.effect access pattern
-- ============================================================
print("\n--- Access pattern ---")

-- Reload to test lazy-load
package.loaded["vdsl.catalogs"] = nil
local catalogs2 = require("vdsl.catalogs")
T.ok("lazy reload: effect loads", catalogs2.effect ~= nil)
T.ok("lazy reload: bloom exists", catalogs2.effect.bloom ~= nil)

-- Nonexistent entry returns nil
T.ok("nonexistent returns nil", effect.nonexistent_effect == nil)

-- ============================================================
-- Safety: no hints (effects are prompt-only, no Post/Stage metadata)
-- ============================================================
print("\n--- Safety ---")

for _, name in ipairs(expected) do
  local hints = effect[name]:hints()
  T.ok("effect." .. name .. " has no hints", hints == nil)
end

T.summary()
