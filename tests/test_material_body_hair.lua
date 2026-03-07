--- test_material_body_hair.lua: Tests for material, body, hair catalogs.
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;tests/?.lua;'..package.path" tests/test_material_body_hair.lua

local Entity   = require("vdsl.entity")
local Subject  = require("vdsl.subject")
local T        = require("harness")

local catalogs = require("vdsl.catalogs")

-- ============================================================
-- Material catalog (Top-level)
-- ============================================================
print("=== Material Catalog Tests ===")

T.ok("material loads", catalogs.material ~= nil)
local mat = catalogs.material

local mat_expected = {
  "metallic", "glossy", "matte", "translucent",
  "leather", "silk", "lace", "denim", "fur",
  "glass", "crystal", "wood",
}

for _, name in ipairs(mat_expected) do
  T.ok("material." .. name .. " exists", mat[name] ~= nil)
  T.ok("material." .. name .. " is trait", Entity.is(mat[name], "trait"))
end

-- Entry count
local mat_count = 0
for _ in pairs(mat) do mat_count = mat_count + 1 end
T.eq("material entry count", mat_count, #mat_expected)

-- Resolve spot checks
T.ok("metallic resolves", mat.metallic:resolve():find("metallic") ~= nil)
T.ok("leather resolves", mat.leather:resolve():find("leather") ~= nil)
T.ok("crystal resolves", mat.crystal:resolve():find("crystal") ~= nil)
T.ok("glass resolves", mat.glass:resolve():find("glass") ~= nil)

-- Composability
local combo = mat.leather + "jacket"
T.ok("leather + jacket composes", Entity.is(combo, "trait"))
T.ok("combo has leather", combo:resolve():find("leather") ~= nil)
T.ok("combo has jacket", combo:resolve():find("jacket") ~= nil)

-- Pipeline integration
local World    = require("vdsl.world")
local Cast     = require("vdsl.cast")
local compiler = require("vdsl.compiler")

local subj = Subject.new("1girl"):with(mat.silk)
local result = compiler.compile({
  world = World.new({ model = "test.safetensors" }),
  cast  = { Cast.new({ subject = subj }) },
  seed  = 42,
})
local found_silk = false
for _, node in pairs(result.prompt) do
  if node.class_type == "CLIPTextEncode" then
    local text = node.inputs.text
    if type(text) == "string" and text:find("silk") then
      found_silk = true
    end
  end
end
T.ok("pipeline: silk in prompt", found_silk)

-- No hints (materials are prompt-only)
for _, name in ipairs(mat_expected) do
  T.ok("material." .. name .. " no hints", mat[name]:hints() == nil)
end

-- Nonexistent
T.ok("nonexistent returns nil", mat.nonexistent == nil)

-- ============================================================
-- Body catalog (figure pack)
-- ============================================================
print("\n=== Body Catalog Tests ===")

T.ok("figure.body loads", catalogs.figure.body ~= nil)
local body = catalogs.figure.body

local body_expected = {
  "muscular", "toned", "slim", "skinny", "petite",
  "curvy", "chubby", "abs", "tall", "long_legs", "elderly",
}

for _, name in ipairs(body_expected) do
  T.ok("body." .. name .. " exists", body[name] ~= nil)
  T.ok("body." .. name .. " is trait", Entity.is(body[name], "trait"))
end

local body_count = 0
for _ in pairs(body) do body_count = body_count + 1 end
T.eq("body entry count", body_count, #body_expected)

-- Resolve spot checks
T.ok("muscular resolves", body.muscular:resolve():find("muscular") ~= nil)
T.ok("slim resolves", body.slim:resolve():find("slim") ~= nil)
T.ok("elderly resolves", body.elderly:resolve():find("elderly") ~= nil)
T.ok("elderly has wrinkles", body.elderly:resolve():find("wrinkles") ~= nil)

-- Composability with Subject
local subj2 = Subject.new("1girl"):with(body.muscular)
T.ok("Subject + muscular", subj2:resolve():find("muscular") ~= nil)

-- Nonexistent
T.ok("nonexistent returns nil", body.nonexistent == nil)

-- ============================================================
-- Hair catalog (figure pack)
-- ============================================================
print("\n=== Hair Catalog Tests ===")

T.ok("figure.hair loads", catalogs.figure.hair ~= nil)
local hair = catalogs.figure.hair

local hair_colors = {
  "black", "brown", "blonde", "red", "white", "silver",
  "grey", "blue", "pink", "green", "purple",
}
local hair_lengths = { "short", "medium", "long", "very_long" }
local hair_styles = {
  "ponytail", "twintails", "braid", "bob_cut",
  "straight", "wavy", "curly", "messy",
  "hair_bun", "bangs", "side_ponytail", "hime_cut", "ahoge",
}
local hair_framing = {
  "blunt_bangs", "swept_bangs", "parted_bangs",
  "sidelocks", "hair_over_one_eye", "hair_between_eyes",
}
local hair_texture = {
  "shiny_hair", "floating_hair",
}

-- All entries exist and are traits
local all_hair = {}
for _, t in ipairs(hair_colors) do all_hair[#all_hair + 1] = t end
for _, t in ipairs(hair_lengths) do all_hair[#all_hair + 1] = t end
for _, t in ipairs(hair_styles) do all_hair[#all_hair + 1] = t end
for _, t in ipairs(hair_framing) do all_hair[#all_hair + 1] = t end
for _, t in ipairs(hair_texture) do all_hair[#all_hair + 1] = t end

for _, name in ipairs(all_hair) do
  T.ok("hair." .. name .. " exists", hair[name] ~= nil)
  T.ok("hair." .. name .. " is trait", Entity.is(hair[name], "trait"))
end

local hair_count = 0
for _ in pairs(hair) do hair_count = hair_count + 1 end
T.eq("hair entry count", hair_count, #all_hair)

-- Resolve spot checks
T.ok("blonde resolves", hair.blonde:resolve():find("blonde") ~= nil)
T.ok("ponytail resolves", hair.ponytail:resolve():find("ponytail") ~= nil)
T.ok("very_long resolves", hair.very_long:resolve():find("very long") ~= nil)
T.ok("hime_cut resolves", hair.hime_cut:resolve():find("hime") ~= nil)

-- Triple composition: color + length + style
local hair_combo = hair.blonde + hair.long + hair.ponytail
T.ok("triple hair combo is trait", Entity.is(hair_combo, "trait"))
local hr = hair_combo:resolve()
T.ok("combo has blonde", hr:find("blonde") ~= nil)
T.ok("combo has long", hr:find("long") ~= nil)
T.ok("combo has ponytail", hr:find("ponytail") ~= nil)

-- Compose with Subject
local subj3 = Subject.new("1girl")
  :with(hair.silver + hair.long + hair.wavy)
  :with(body.slim)
T.ok("Subject + hair + body",
  subj3:resolve():find("silver") ~= nil
  and subj3:resolve():find("slim") ~= nil)

-- Pipeline integration
local result2 = compiler.compile({
  world = World.new({ model = "test.safetensors" }),
  cast  = { Cast.new({ subject = subj3 }) },
  seed  = 42,
})
local found_silver = false
for _, node in pairs(result2.prompt) do
  if node.class_type == "CLIPTextEncode" then
    local text = node.inputs.text
    if type(text) == "string" and text:find("silver") then
      found_silver = true
    end
  end
end
T.ok("pipeline: silver hair in prompt", found_silver)

-- Nonexistent
T.ok("nonexistent returns nil", hair.nonexistent == nil)

-- ============================================================
-- Cross-catalog composability
-- ============================================================
print("\n=== Cross-catalog Tests ===")

local effect = catalogs.effect
local expression = catalogs.figure.expression

-- hair + expression + effect
local full_combo = hair.pink + hair.long
local subj_full = Subject.new("1girl")
  :with(full_combo)
  :with(expression.smile)
  :with(effect.bloom)
T.ok("full combo resolves",
  subj_full:resolve():find("pink") ~= nil
  and subj_full:resolve():find("smile") ~= nil
  and subj_full:resolve():find("bloom") ~= nil)

T.summary()
