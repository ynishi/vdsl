--- test_over_prompt.lua: over-prompt lint (warn-only) detection + intent suppression
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;tests/?.lua;'..package.path" tests/test_over_prompt.lua

local vdsl        = require("vdsl")
local over_prompt = require("vdsl.lint.over_prompt")
local Shot        = require("vdsl.shot")
local T           = require("harness")

-- Isolate from user config (workspaces/config.lua)
vdsl.config._override({})

local WORLD = vdsl.world { model = "m.safetensors" }

-- A subject whose detail overlay piles 6 lighting clauses on top of a
-- :quality()/:style() anchor (mirrors the pre-fix cam over-prompt case).
local function over_light_subject()
  return vdsl.subject("1girl, solo")
    :with(vdsl.trait("almond-shaped calm black eyes"))
    :quality("high")
    :style("photo")
    :with(vdsl.trait(
      "warm amber evening light, golden glow, moody, warm tones, "
      .. "autumn atmosphere, soft bokeh"))
end

-- A clean (within-budget) overlay: one light source + supporting clauses.
local function clean_subject()
  return vdsl.subject("1girl, solo")
    :with(vdsl.trait("almond-shaped calm black eyes"))
    :quality("high")
    :style("photo")
    :with(vdsl.trait(
      "professional portrait photography, soft bokeh, "
      .. "autumn indoor atmosphere, soft natural window light, sheer curtains"))
end

-- An anime subject stacking 2D words on a :style("anime") anchor.
local function over_lock_subject()
  return vdsl.subject("1girl, solo")
    :quality("high")
    :style("anime")
    :with(vdsl.trait(
      "anime style, cel shading, flat color, clean lineart, 2D, "
      .. "masterwork illustration"))
end

local function has(warnings, needle)
  for _, w in ipairs(warnings) do
    if w:find(needle, 1, true) then return true end
  end
  return false
end

-- ============================================================
-- module unit: classify + check on hand-built grouped
-- ============================================================
T.eq("classify: golden glow -> light", over_prompt.classify("golden glow"), "light")
T.eq("classify: cel shading -> lock",  over_prompt.classify("cel shading"), "lock")
T.eq("classify: blue eyes -> nil",     over_prompt.classify("blue eyes"), nil)

do
  local grouped = {
    subject = { "1girl, solo" },
    quality = { "masterpiece, best quality" },          -- anchor
    style   = { "photorealistic" },                     -- anchor
    detail  = { "warm amber evening light, golden glow, moody, warm tones, autumn atmosphere, soft bokeh" },
  }
  local r = over_prompt.check(grouped, {})
  T.eq("unit: light counted = 6", r.counts.light, 6)
  T.ok("unit: a finding emitted", #r.findings >= 1)
  T.eq("unit: finding is over_budget", r.findings[1].kind, "over_budget")
  T.eq("unit: not suppressed by default", r.findings[1].suppressed, false)
  T.eq("unit: 6 clauses named", #r.findings[1].clauses, 6)
end

-- ============================================================
-- engine integration via vdsl.check
-- ============================================================
do
  local diag = vdsl.check({ world = WORLD, cast = { vdsl.cast { subject = over_light_subject() } } })
  T.ok("engine: light over-prompt warned", has(diag.warnings, "over-prompt: light"))
end

do
  local diag = vdsl.check({ world = WORLD, cast = { vdsl.cast { subject = clean_subject() } } })
  T.ok("engine: clean subject does NOT warn light", not has(diag.warnings, "over-prompt: light"))
end

do
  local diag = vdsl.check({ world = WORLD, cast = { vdsl.cast { subject = over_lock_subject() } } })
  T.ok("engine: 2D/lock over-prompt warned", has(diag.warnings, "over-prompt: lock"))
end

-- ============================================================
-- intent suppression (Warn & Ignore — the "Ignore" side)
-- ============================================================
do
  -- raw opts.intents set form
  local diag = vdsl.check({
    world = WORLD,
    cast  = { vdsl.cast { subject = over_light_subject() } },
    intents = { light = true },
  })
  T.ok("intent (opts set): light warn suppressed", not has(diag.warnings, "over-prompt: light"))
end

do
  -- friendly alias resolves to light
  local diag = vdsl.check({
    world = WORLD,
    cast  = { vdsl.cast { subject = over_light_subject() } },
    intents = { ["blown-highlight"] = true },
  })
  T.ok("intent (alias): blown-highlight suppresses light", not has(diag.warnings, "over-prompt: light"))
end

do
  -- end-to-end via Shot:intent() (exercises shot.lua plumbing + provenance field)
  local shot = Shot.new({ world = WORLD, cast = { vdsl.cast { subject = over_light_subject() } } })
  T.ok("shot: warns before intent", has(shot:check().warnings, "over-prompt: light"))
  local quieted = shot:intent("light")
  T.ok("shot: intent field carried", quieted.intents and quieted.intents.light == true)
  T.ok("shot: warn suppressed after intent", not has(quieted:check().warnings, "over-prompt: light"))
  T.ok("shot: original shot unchanged (immutable)", has(shot:check().warnings, "over-prompt: light"))
end

T.summary()
