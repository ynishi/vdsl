--- Tests for figure.eyes, figure.accessory, figure.clothing catalogs.
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;tests/?.lua;'..package.path" tests/test_eyes_accessory_clothing.lua

local vdsl     = require("vdsl")
local Entity   = require("vdsl.entity")
local catalogs = require("vdsl.catalogs")

local pass, fail = 0, 0

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    pass = pass + 1
  else
    fail = fail + 1
    print("FAIL: " .. name .. " — " .. tostring(err))
  end
end

local function assert_eq(a, b, msg)
  if a ~= b then
    error((msg or "") .. " expected: " .. tostring(b) .. ", got: " .. tostring(a), 2)
  end
end

local function assert_contains(str, sub, msg)
  if not str:find(sub, 1, true) then
    error((msg or "") .. " expected '" .. sub .. "' in '" .. str .. "'", 2)
  end
end

local function assert_trait(entry, name)
  if not Entity.is(entry, "trait") then
    error(name .. " is not a Trait", 2)
  end
end

-- ============================================================
-- figure.eyes
-- ============================================================

local eyes = catalogs.figure.eyes

test("eyes catalog loads", function()
  assert(eyes, "eyes catalog is nil")
end)

-- Color entries
local eye_colors = { "blue", "red", "green", "brown", "purple", "yellow", "orange", "aqua", "pink", "silver" }
for _, color in ipairs(eye_colors) do
  test("eyes." .. color .. " is Trait", function()
    assert_trait(eyes[color], "eyes." .. color)
  end)

  test("eyes." .. color .. " resolves to '<color> eyes'", function()
    assert_eq(eyes[color]:resolve(), color .. " eyes")
  end)
end

-- Feature entries
test("eyes.heterochromia is Trait with emphasis", function()
  assert_trait(eyes.heterochromia, "eyes.heterochromia")
  assert_contains(eyes.heterochromia:resolve(), "heterochromia")
end)

test("eyes.slit_pupils resolves", function()
  assert_trait(eyes.slit_pupils, "eyes.slit_pupils")
  assert_eq(eyes.slit_pupils:resolve(), "slit pupils")
end)

test("eyes.glowing resolves", function()
  assert_trait(eyes.glowing, "eyes.glowing")
  assert_eq(eyes.glowing:resolve(), "glowing eyes")
end)

test("eyes.sharp resolves", function()
  assert_trait(eyes.sharp, "eyes.sharp")
  assert_eq(eyes.sharp:resolve(), "sharp eyes")
end)

test("eyes.empty resolves", function()
  assert_trait(eyes.empty, "eyes.empty")
  assert_eq(eyes.empty:resolve(), "empty eyes")
end)

-- Composition with * operator
test("eyes color composes with * (space-join)", function()
  local t = vdsl.trait("blue") * vdsl.trait("eyes")
  assert_eq(t:resolve(), "blue eyes")
end)

test("eyes entry composes with hair via +", function()
  local t = eyes.blue + catalogs.figure.hair.blonde
  local r = t:resolve()
  assert_contains(r, "blue eyes")
  assert_contains(r, "blonde hair")
end)

-- ============================================================
-- figure.accessory
-- ============================================================

local acc = catalogs.figure.accessory

test("accessory catalog loads", function()
  assert(acc, "accessory catalog is nil")
end)

local accessory_keys = {
  "glasses", "sunglasses", "eyepatch", "goggles",
  "headband", "hair_ribbon", "hair_bow", "hair_ornament",
  "beret", "crown", "hood", "witch_hat",
  "choker", "necklace", "scarf",
  "gloves", "fingerless_gloves", "elbow_gloves",
  "earrings", "mask",
}

for _, key in ipairs(accessory_keys) do
  test("accessory." .. key .. " is Trait", function()
    assert_trait(acc[key], "accessory." .. key)
  end)

  test("accessory." .. key .. " resolves to non-empty string", function()
    local r = acc[key]:resolve()
    assert(r ~= "", key .. " resolved to empty")
  end)
end

-- Spot-check resolved values
test("accessory.glasses resolves", function()
  assert_eq(acc.glasses:resolve(), "glasses")
end)

test("accessory.fingerless_gloves resolves", function()
  assert_eq(acc.fingerless_gloves:resolve(), "fingerless gloves")
end)

test("accessory.witch_hat resolves", function()
  assert_eq(acc.witch_hat:resolve(), "witch hat")
end)

-- Composition
test("accessory composes with subject", function()
  local subj = vdsl.subject("1girl"):with(acc.glasses):with(acc.beret)
  local r = subj:resolve()
  assert_contains(r, "glasses")
  assert_contains(r, "beret")
end)

-- ============================================================
-- figure.clothing
-- ============================================================

local cloth = catalogs.figure.clothing

test("clothing catalog loads", function()
  assert(cloth, "clothing catalog is nil")
end)

local clothing_keys = {
  "shirt", "t_shirt", "blouse", "tank_top", "hoodie", "sweater", "cardigan", "crop_top",
  "skirt", "pleated_skirt", "miniskirt", "pants", "jeans", "shorts",
  "dress", "sundress", "evening_gown", "wedding_dress",
  "jacket", "blazer", "coat",
  "school_uniform", "serafuku", "military_uniform", "maid", "suit",
  "kimono", "yukata", "chinese_dress",
  "swimsuit", "bikini", "leotard",
  "armor", "shoulder_armor",
}

for _, key in ipairs(clothing_keys) do
  test("clothing." .. key .. " is Trait", function()
    assert_trait(cloth[key], "clothing." .. key)
  end)

  test("clothing." .. key .. " resolves to non-empty string", function()
    local r = cloth[key]:resolve()
    assert(r ~= "", key .. " resolved to empty")
  end)
end

-- Spot-check resolved values (no compound tags)
test("clothing.school_uniform resolves", function()
  assert_eq(cloth.school_uniform:resolve(), "school uniform")
end)

test("clothing.pleated_skirt resolves", function()
  assert_eq(cloth.pleated_skirt:resolve(), "pleated skirt")
end)

test("clothing.chinese_dress resolves", function()
  assert_eq(cloth.chinese_dress:resolve(), "chinese dress")
end)

test("clothing.shoulder_armor resolves", function()
  assert_eq(cloth.shoulder_armor:resolve(), "shoulder armor")
end)

-- No compound tags (should NOT contain two unrelated concepts in one Trait)
test("clothing entries are single Traits (no composite _parts)", function()
  for _, key in ipairs(clothing_keys) do
    local entry = cloth[key]
    if entry._parts then
      error("clothing." .. key .. " has _parts (composite). Should be single Trait.")
    end
  end
end)

-- Composition
test("clothing composes with subject", function()
  local subj = vdsl.subject("1girl")
    :with(cloth.school_uniform)
    :with(cloth.pleated_skirt)
    :with(acc.hair_ribbon)
  local r = subj:resolve()
  assert_contains(r, "school uniform")
  assert_contains(r, "pleated skirt")
  assert_contains(r, "hair ribbon")
end)

-- ============================================================
-- Cross-catalog composition
-- ============================================================

test("full character composition: eyes + hair + clothing + accessory", function()
  local subj = vdsl.subject("1girl")
    :with(eyes.blue)
    :with(catalogs.figure.hair.blonde + catalogs.figure.hair.long)
    :with(cloth.dress)
    :with(acc.choker)
  local r = subj:resolve()
  assert_contains(r, "blue eyes")
  assert_contains(r, "blonde hair")
  assert_contains(r, "long hair")
  assert_contains(r, "dress")
  assert_contains(r, "choker")
end)

-- ============================================================
-- Summary
-- ============================================================

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
