--- Tests for atmosphere catalog and integration.
package.path = "lua/?.lua;lua/?/init.lua;tests/?.lua;" .. package.path

local T          = require("harness")
local Entity     = require("vdsl.entity")
local Trait      = require("vdsl.trait")

-- ── Catalog presets ──────────────────────────────────────
-- Presets now live in catalogs/atmosphere.lua (raw Traits).
-- init.lua wraps them into Atmosphere entities on access via vdsl.atmosphere.<name>.
local catalog_atm = require("vdsl.catalogs.atmosphere")

local expected_presets = {
  "serene", "peaceful", "tranquil",
  "dramatic", "epic", "intense",
  "ominous", "sinister",
  "ethereal", "dreamlike", "surreal",
  "nostalgic", "melancholic",
  "cozy", "intimate",
  "mysterious", "enigmatic",
  "whimsical",
  "tense",
  "majestic",
}

-- ── Catalog entries are Traits ──────────────────────────────
for _, name in ipairs(expected_presets) do
  local entry = catalog_atm[name]
  T.ok("catalog entry exists: " .. name, entry ~= nil)
  T.ok("catalog entry is Trait: " .. name, Entity.is(entry, "trait"))
end

-- ── Catalog entry resolve not empty ─────────────────────────
for _, name in ipairs(expected_presets) do
  local text = catalog_atm[name]:resolve()
  T.ok("catalog resolves non-empty: " .. name,
    type(text) == "string" and #text > 0)
end

-- ── Catalog entry contains 'atmosphere' keyword ─────────────
for _, name in ipairs(expected_presets) do
  local text = catalog_atm[name]:resolve()
  T.ok("catalog contains 'atmosphere': " .. name,
    text:find("atmosphere") ~= nil)
end

-- ── Catalog entry count ─────────────────────────────────────
local count = 0
for _ in pairs(catalog_atm) do
  count = count + 1
end
T.eq("catalog entry count", count, #expected_presets)

-- ── vdsl.atmosphere callable + presets from catalog ──────────
package.loaded["vdsl"] = nil
local vdsl = require("vdsl")

local va1 = vdsl.atmosphere("custom eerie")
T.ok("vdsl.atmosphere() callable", Entity.is(va1, "trait"))
T.ok("vdsl.atmosphere() resolve", va1:resolve() == "custom eerie")

local va2 = vdsl.atmosphere.serene
T.ok("vdsl.atmosphere.serene is Trait", Entity.is(va2, "trait"))
T.ok("vdsl.atmosphere.serene resolve",
  va2:resolve():find("serene") ~= nil)

-- ── Composability: atmosphere + atmosphere ─────────────────
local c1 = vdsl.atmosphere.serene + vdsl.atmosphere.ethereal
T.ok("compose: serene + ethereal is Trait", Entity.is(c1, "trait"))
local r_c1 = c1:resolve()
T.ok("compose: contains serene", r_c1:find("serene") ~= nil)
T.ok("compose: contains ethereal", r_c1:find("ethereal") ~= nil)

-- ── Composability: atmosphere + string ─────────────────────
local c2 = vdsl.atmosphere.dramatic + "cinematic tension"
T.ok("compose: atm + string is Trait", Entity.is(c2, "trait"))
local r_c2 = c2:resolve()
T.ok("compose: contains dramatic", r_c2:find("dramatic") ~= nil)
T.ok("compose: contains cinematic", r_c2:find("cinematic") ~= nil)

-- ── Nonexistent preset returns nil ────────────────────────
T.ok("nonexistent preset returns nil",
  vdsl.atmosphere.nonexistent_mood == nil)

-- ── Compiler integration ──────────────────────────────────
local World = require("vdsl.world")
local Cast  = require("vdsl.cast")
local compiler = require("vdsl.compiler")

local result = compiler.compile({
  world = World.new({ model = "test.safetensors" }),
  cast  = { Cast.new({ subject = "1girl, white dress" }) },
  atmosphere = vdsl.atmosphere.ominous,
  seed  = 42,
})

-- Find the CLIPTextEncode positive prompt node
local found_atmosphere = false
for _, node in pairs(result.prompt) do
  if node.class_type == "CLIPTextEncode" then
    local text = node.inputs.text
    if type(text) == "string" and text:find("ominous atmosphere") then
      found_atmosphere = true
    end
  end
end
T.ok("compiler: atmosphere in positive prompt", found_atmosphere)

-- Verify atmosphere text comes after subject text
for _, node in pairs(result.prompt) do
  if node.class_type == "CLIPTextEncode" then
    local text = node.inputs.text
    if type(text) == "string" and text:find("ominous atmosphere") then
      local subj_pos = text:find("1girl")
      local atm_pos  = text:find("ominous atmosphere")
      if subj_pos and atm_pos then
        T.ok("compiler: subject before atmosphere", subj_pos < atm_pos)
      end
    end
  end
end

-- Without atmosphere: verify no atmosphere text
local result_no_atm = compiler.compile({
  world = World.new({ model = "test.safetensors" }),
  cast  = { Cast.new({ subject = "1girl, white dress" }) },
  seed  = 42,
})
local no_atm_found = true
for _, node in pairs(result_no_atm.prompt) do
  if node.class_type == "CLIPTextEncode" then
    local text = node.inputs.text
    if type(text) == "string" and text:find("atmosphere") then
      no_atm_found = false
    end
  end
end
T.ok("compiler: no atmosphere when omitted", no_atm_found)

-- ── Recipe round-trip ─────────────────────────────────────
local recipe = require("vdsl.runtime.serializer")

local render_opts = {
  world = World.new({ model = "test.safetensors" }),
  cast  = { Cast.new({ subject = "1girl" }) },
  atmosphere = vdsl.atmosphere.dramatic,
  seed  = 123,
}

local serialized = recipe.serialize(render_opts)
T.ok("recipe: serialized is string", type(serialized) == "string")
T.ok("recipe: contains atmosphere marker", serialized:find("atmosphere") ~= nil)

local deserialized = recipe.deserialize(serialized)
T.ok("recipe: deserialized has atmosphere",
  deserialized.atmosphere ~= nil)
T.ok("recipe: deserialized atmosphere is Trait",
  Entity.is(deserialized.atmosphere, "trait"))

local orig_text = render_opts.atmosphere:resolve()
local deser_text = deserialized.atmosphere:resolve()
T.ok("recipe: round-trip text preserved", orig_text == deser_text)

-- ── Strategy: recommended ─────────────────────────────────
local Subject = require("vdsl.subject")

-- Build a subject with explicit quality/style categories
local subj = Subject.new("1girl, white dress")
  :style("anime")
  :with("long hair, blue eyes")
  :quality("high")

-- Natural order (default): traits in user order, atmosphere at end
local result_natural = compiler.compile({
  world = World.new({ model = "test.safetensors" }),
  cast  = { Cast.new({ subject = subj }) },
  atmosphere = vdsl.atmosphere.serene,
  seed  = 42,
})

local natural_text
for _, node in pairs(result_natural.prompt) do
  if node.class_type == "CLIPTextEncode" then
    local t = node.inputs.text
    if type(t) == "string" and t:find("serene atmosphere") then
      natural_text = t
    end
  end
end
T.ok("strategy natural: prompt assembled", natural_text ~= nil)

-- In natural order: quality appears before atmosphere (user order)
if natural_text then
  local quality_pos = natural_text:find("masterpiece")
  local atm_pos     = natural_text:find("serene atmosphere")
  T.ok("strategy natural: quality before atmosphere",
    quality_pos and atm_pos and quality_pos < atm_pos)
end

-- Recommended strategy: subject → style → detail → atmosphere → quality
local result_rec = compiler.compile({
  world = World.new({ model = "test.safetensors" }),
  cast  = { Cast.new({ subject = subj }) },
  atmosphere = vdsl.atmosphere.serene,
  strategy = "recommended",
  seed  = 42,
})

local rec_text
for _, node in pairs(result_rec.prompt) do
  if node.class_type == "CLIPTextEncode" then
    local t = node.inputs.text
    if type(t) == "string" and t:find("serene atmosphere") then
      rec_text = t
    end
  end
end
T.ok("strategy recommended: prompt assembled", rec_text ~= nil)

-- In recommended: subject first, then style, then detail, then atmosphere, then quality
if rec_text then
  local subj_pos    = rec_text:find("1girl")
  local style_pos   = rec_text:find("anime")
  local detail_pos  = rec_text:find("long hair")
  local atm_pos     = rec_text:find("serene atmosphere")
  local quality_pos = rec_text:find("masterpiece")

  T.ok("strategy recommended: subject first",
    subj_pos and style_pos and subj_pos < style_pos)
  T.ok("strategy recommended: style before detail",
    style_pos and detail_pos and style_pos < detail_pos)
  T.ok("strategy recommended: detail before atmosphere",
    detail_pos and atm_pos and detail_pos < atm_pos)
  T.ok("strategy recommended: atmosphere before quality",
    atm_pos and quality_pos and atm_pos < quality_pos)
end

-- Strategy error: unknown strategy
T.err("strategy error: unknown", function()
  compiler.compile({
    world = World.new({ model = "test.safetensors" }),
    cast  = { Cast.new({ subject = "1girl" }) },
    strategy = "nonexistent",
    seed  = 42,
  })
end)

-- ── Subject category tracking ─────────────────────────────
local grouped = subj:resolve_grouped()
T.ok("resolve_grouped: has subject", grouped.subject ~= nil)
T.ok("resolve_grouped: has style", grouped.style ~= nil)
T.ok("resolve_grouped: has quality", grouped.quality ~= nil)
T.ok("resolve_grouped: has detail", grouped.detail ~= nil)

-- ── Recipe round-trip with strategy + categories ──────────
local recipe_mod = require("vdsl.runtime.serializer")

local render_opts_strat = {
  world = World.new({ model = "test.safetensors" }),
  cast  = { Cast.new({ subject = subj }) },
  atmosphere = vdsl.atmosphere.dramatic,
  strategy = "recommended",
  seed  = 456,
}

local ser_strat = recipe_mod.serialize(render_opts_strat)
local deser_strat = recipe_mod.deserialize(ser_strat)
T.eq("recipe: strategy round-trip", deser_strat.strategy, "recommended")

-- Verify categories survive round-trip
local deser_grouped = deser_strat.cast[1].subject:resolve_grouped()
T.ok("recipe: subject category preserved", deser_grouped.subject ~= nil)
T.ok("recipe: style category preserved", deser_grouped.style ~= nil)
T.ok("recipe: quality category preserved", deser_grouped.quality ~= nil)
T.ok("recipe: detail category preserved", deser_grouped.detail ~= nil)

-- ── Token estimation ──────────────────────────────────────
T.eq("estimate_tokens: empty", compiler.estimate_tokens(""), 0)
T.eq("estimate_tokens: nil", compiler.estimate_tokens(nil), 0)
T.eq("estimate_tokens: single word", compiler.estimate_tokens("cat"), 1)
T.eq("estimate_tokens: two words", compiler.estimate_tokens("white cat"), 2)
T.eq("estimate_tokens: comma separated",
  compiler.estimate_tokens("1girl, white dress"), 4)  -- 1girl , white dress
T.eq("estimate_tokens: emphasis syntax",
  compiler.estimate_tokens("(dramatic:1.1)"), 7)  -- ( dramatic : 1 . 1 ) = 7

-- ── compiler.check ────────────────────────────────────────
local check_subj = Subject.new("1girl, white dress")
  :style("anime")
  :with("long hair, blue eyes, standing in garden")
  :quality("high")

local diag = compiler.check({
  world = World.new({ model = "test.safetensors" }),
  cast  = { Cast.new({ subject = check_subj }) },
  atmosphere = vdsl.atmosphere.serene,
  strategy = "recommended",
})

T.ok("check: returns casts", diag.casts ~= nil and diag.casts[1] ~= nil)
T.ok("check: positive has text", type(diag.casts[1].positive.text) == "string")
T.ok("check: positive has tokens",
  type(diag.casts[1].positive.estimated_tokens) == "number"
  and diag.casts[1].positive.estimated_tokens > 0)
T.ok("check: positive has chunks",
  diag.casts[1].positive.chunks >= 1)
T.ok("check: has budget", #diag.casts[1].budget > 0)
T.ok("check: has limits", diag.limits.chunk_size == 75)
T.ok("check: has sweet_spot", diag.limits.sweet_spot == 20)

-- Budget has categories
local budget_cats = {}
for _, b in ipairs(diag.casts[1].budget) do
  budget_cats[b.category] = b.tokens
end
T.ok("check budget: has subject", budget_cats.subject ~= nil and budget_cats.subject > 0)
T.ok("check budget: has style", budget_cats.style ~= nil and budget_cats.style > 0)
T.ok("check budget: has atmosphere", budget_cats.atmosphere ~= nil and budget_cats.atmosphere > 0)
T.ok("check budget: has quality", budget_cats.quality ~= nil and budget_cats.quality > 0)

-- Token budget sum ≈ total (may differ slightly due to comma separators in assembly)
local budget_sum = 0
for _, b in ipairs(diag.casts[1].budget) do
  budget_sum = budget_sum + b.tokens
end
T.ok("check budget: sum reasonable",
  budget_sum > 0 and budget_sum <= diag.casts[1].positive.estimated_tokens + 10)

-- ── check: warnings for long prompt ───────────────────────
local long_text = {}
for i = 1, 80 do long_text[i] = "word" .. i end
local long_subj = Subject.new(table.concat(long_text, ", "))

local diag_long = compiler.check({
  world = World.new({ model = "test.safetensors" }),
  cast  = { Cast.new({ subject = long_subj }) },
})
T.ok("check long: has warnings", #diag_long.warnings > 0)
T.ok("check long: token warning",
  diag_long.warnings[1]:find("token") ~= nil)

-- ── check: no warnings for short prompt ───────────────────
local diag_short = compiler.check({
  world = World.new({ model = "test.safetensors" }),
  cast  = { Cast.new({ subject = "1girl" }) },
})
T.eq("check short: no warnings", #diag_short.warnings, 0)

-- ── vdsl.check exposed ───────────────────────────────────
local vdsl_diag = vdsl.check({
  world = World.new({ model = "test.safetensors" }),
  cast  = { Cast.new({ subject = check_subj }) },
  atmosphere = vdsl.atmosphere.dramatic,
})
T.ok("vdsl.check: works", vdsl_diag.casts ~= nil)

T.summary()
