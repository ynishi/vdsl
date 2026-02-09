--- test_entity.lua: Tests for Entity type system, Trait, Subject, Weight
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;tests/?.lua;'..package.path" tests/test_entity.lua

local vdsl   = require("vdsl")
local Entity = require("vdsl.entity")
local T      = require("harness")

-- ============================================================
-- Entity type system
-- ============================================================
local t = vdsl.trait("test")
T.ok("entity: is trait",       Entity.is(t, "trait"))
T.ok("entity: not subject",    not Entity.is(t, "subject"))
T.ok("entity: is_entity",      Entity.is_entity(t))
T.eq("entity: type_of",        Entity.type_of(t), "trait")

local s = vdsl.subject("cat")
T.ok("entity: is subject",     Entity.is(s, "subject"))
T.ok("entity: is_entity sub",  Entity.is_entity(s))

-- Non-entities
T.ok("entity: string false",   not Entity.is_entity("hello"))
T.ok("entity: number false",   not Entity.is_entity(42))
T.ok("entity: nil false",      not Entity.is_entity(nil))
T.ok("entity: table false",    not Entity.is_entity({}))

-- resolve_text
T.eq("resolve: nil",           Entity.resolve_text(nil), "")
T.eq("resolve: string",        Entity.resolve_text("hello"), "hello")
T.eq("resolve: trait",         Entity.resolve_text(t), "test")
T.eq("resolve: subject",       Entity.resolve_text(s), "cat")

-- ============================================================
-- Trait tests
-- ============================================================
local t1 = vdsl.trait("walking pose")
T.ok("trait: is trait",    Entity.is(t1, "trait"))
T.eq("trait: resolve",    t1:resolve(), "walking pose")

local t2 = vdsl.trait("detailed", 1.5)
T.eq("trait: emphasis",   t2:resolve(), "(detailed:1.5)")

local t3 = t1 + t2
T.eq("trait: composite",  t3:resolve(), "walking pose, (detailed:1.5)")

local t4 = t1 + vdsl.trait("full body")
T.eq("trait: + trait",    t4:resolve(), "walking pose, full body")

local t5 = vdsl.trait("a"):with("b"):with("c")
T.eq("trait: chain",      t5:resolve(), "a, b, c")

local t6 = vdsl.trait("face", 1.3) + vdsl.trait("eyes", 1.5)
T.eq("trait: emph chain", t6:resolve(), "(face:1.3), (eyes:1.5)")

local t7 = (vdsl.trait("a") + vdsl.trait("b")) + vdsl.trait("c")
T.eq("trait: flatten",    t7:resolve(), "a, b, c")

T.err("trait: empty text", function() vdsl.trait("") end)

-- ============================================================
-- Weight tests
-- ============================================================
T.eq("weight: none",   vdsl.weight.resolve(vdsl.weight.none),   0.0)
T.eq("weight: subtle", vdsl.weight.resolve(vdsl.weight.subtle), 0.2)
T.eq("weight: light",  vdsl.weight.resolve(vdsl.weight.light),  0.4)
T.eq("weight: medium", vdsl.weight.resolve(vdsl.weight.medium), 0.6)
T.eq("weight: heavy",  vdsl.weight.resolve(vdsl.weight.heavy),  0.8)
T.eq("weight: full",   vdsl.weight.resolve(vdsl.weight.full),   1.0)

T.eq("weight: number passthrough", vdsl.weight.resolve(0.7), 0.7)
T.eq("weight: nil default",   vdsl.weight.resolve(nil),      1.0)
T.eq("weight: nil custom",    vdsl.weight.resolve(nil, 0.5), 0.5)

math.randomseed(42)
local rw = vdsl.weight.range(0.3, 0.8)
T.ok("weight: is_weight",  vdsl.weight.is_weight(rw))
T.eq("weight: range mode",  rw.mode, "range")
for i = 1, 20 do
  local v = vdsl.weight.resolve(rw)
  T.ok("weight: range bounds " .. i, v >= 0.3 and v <= 0.8)
end

local rw_step = vdsl.weight.range(0.0, 1.0, 0.2)
for i = 1, 20 do
  local v = vdsl.weight.resolve(rw_step)
  local remainder = math.abs(v % 0.2)
  T.ok("weight: step " .. i,
    remainder < 0.001 or math.abs(remainder - 0.2) < 0.001)
end

T.err("weight: min>max", function() vdsl.weight.range(0.8, 0.3) end)

-- ============================================================
-- Subject tests
-- ============================================================
local s1 = vdsl.subject("cat")
T.ok("subject: is subject",  Entity.is(s1, "subject"))
T.eq("subject: resolve",     s1:resolve(), "cat")

local s2 = s1:with("walking pose")
T.eq("subject: with str",    s2:resolve(), "cat, walking pose")

local s3 = s1:with(vdsl.trait("sitting", 1.2))
T.eq("subject: with trait",  s3:resolve(), "cat, (sitting:1.2)")

local s4 = vdsl.subject("warrior"):with("armor"):with("sword")
T.eq("subject: chain",       s4:resolve(), "warrior, armor, sword")

-- Immutability
T.eq("subject: immutable",   s1:resolve(), "cat")

local s5 = s1:quality("high")
T.ok("subject: quality",     s5:resolve():find("masterpiece") ~= nil)

local s6 = s1:style("anime")
T.ok("subject: style",       s6:resolve():find("anime") ~= nil)

local s7 = vdsl.subject("cat"):with("walking"):quality("high"):style("photo")
local r7 = s7:resolve()
T.ok("subject: full cat",        r7:find("cat") ~= nil)
T.ok("subject: full walking",    r7:find("walking") ~= nil)
T.ok("subject: full master",     r7:find("masterpiece") ~= nil)
T.ok("subject: full photo",      r7:find("photorealistic") ~= nil)

local walking = vdsl.trait("walking")
local s8 = vdsl.subject("cat"):with(walking)
local s9 = s8:replace(walking, "sitting")
T.eq("subject: replace",         s9:resolve(), "cat, sitting")
T.eq("subject: replace immut",   s8:resolve(), "cat, walking")

T.err("subject: empty",          function() vdsl.subject("") end)
T.err("subject: quality bad",    function() vdsl.subject("x"):quality("nonexistent") end)
T.err("subject: style bad",      function() vdsl.subject("x"):style("nonexistent") end)

-- ============================================================
-- vdsl.lora convenience
-- ============================================================
local l1 = vdsl.lora("detail.safetensors", 0.7)
T.eq("lora: name",   l1.name,   "detail.safetensors")
T.eq("lora: weight", l1.weight, 0.7)

local l2 = vdsl.lora("lcm.safetensors", vdsl.weight.heavy)
T.ok("lora: weight entity", vdsl.weight.is_weight(l2.weight))

local l3 = vdsl.lora("default.safetensors")
T.eq("lora: default weight", l3.weight, 1.0)

T.err("lora: empty name", function() vdsl.lora("") end)

-- ============================================================
-- Cast with Subject (V2: always subject-based)
-- ============================================================
local cat_subject = vdsl.subject("cat"):with("walking"):quality("high")
local ugly_trait  = vdsl.trait("blurry, ugly, deformed")

local c1 = vdsl.cast {
  subject  = cat_subject,
  negative = ugly_trait,
  lora     = { vdsl.lora("detail.safetensors", vdsl.weight.heavy) },
}
T.ok("cast: is cast",          Entity.is(c1, "cast"))
T.ok("cast: has subject",      Entity.is(c1.subject, "subject"))

-- Cast with string auto-coercion
local c2 = vdsl.cast { subject = "warrior woman" }
T.ok("cast: string coerce",    Entity.is(c2.subject, "subject"))
T.eq("cast: coerce resolve",   c2.subject:resolve(), "warrior woman")

-- Cast:with derivation
local c3 = c1:with { negative = vdsl.trait("low quality") }
T.ok("cast: with type",        Entity.is(c3, "cast"))
T.ok("cast: with subject ok",  c3.subject ~= nil)

-- Validation
T.err("cast: no subject", function() vdsl.cast {} end)

-- ============================================================
-- Full pipeline: Entity -> ComfyUI JSON
-- ============================================================
local w = vdsl.world { model = "model.safetensors" }

local hero_subject = vdsl.subject("warrior woman")
  :with("silver armor")
  :with(vdsl.trait("dynamic pose", 1.2))
  :quality("high")

local hero = vdsl.cast {
  subject  = hero_subject,
  negative = vdsl.trait("blurry, ugly"),
  lora     = { vdsl.lora("detail.safetensors", vdsl.weight.medium) },
}

local result = vdsl.render {
  world = w,
  cast  = { hero },
  seed  = 42,
  steps = 20,
}

T.ok("pipeline: has json",   #result.json > 100)
T.ok("pipeline: has prompt", type(result.prompt) == "table")

local found_prompt = false
local found_negative = false
for _, node in pairs(result.prompt) do
  if node.class_type == "CLIPTextEncode" then
    local text = node.inputs.text
    if text:find("warrior woman") and text:find("silver armor") then
      found_prompt = true
      T.ok("pipeline: emphasis", text:find("%(dynamic pose:1.2%)") ~= nil)
      T.ok("pipeline: quality",  text:find("masterpiece") ~= nil)
    end
    if text:find("blurry") then
      found_negative = true
    end
  end
end
T.ok("pipeline: positive resolved", found_prompt)
T.ok("pipeline: negative resolved", found_negative)

for _, node in pairs(result.prompt) do
  if node.class_type == "LoraLoader" then
    T.eq("pipeline: lora weight", node.inputs.strength_model, 0.6)
  end
end

-- ============================================================
-- Trait as negative
-- ============================================================
local neg_trait = vdsl.trait("nsfw", 1.5) + vdsl.trait("watermark")
local c_neg = vdsl.cast {
  subject  = "landscape",
  negative = neg_trait,
}
local neg_result = vdsl.render {
  world = w,
  cast  = { c_neg },
  seed  = 1,
}
local found_neg_trait = false
for _, node in pairs(neg_result.prompt) do
  if node.class_type == "CLIPTextEncode" then
    if node.inputs.text:find("%(nsfw:1.5%)") and node.inputs.text:find("watermark") then
      found_neg_trait = true
    end
  end
end
T.ok("neg trait: resolved", found_neg_trait)

T.summary()
