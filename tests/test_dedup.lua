--- test_dedup.lua: dedup lint — detect (warn) + fix (autofix) + no_lint_fix opt-out
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;tests/?.lua;'..package.path" tests/test_dedup.lua

local vdsl  = require("vdsl")
local dedup = require("vdsl.lint.dedup")
local T     = require("harness")

vdsl.config._override({})

local WORLD = vdsl.world { model = "m.safetensors" }

local function has(warnings, needle)
  for _, w in ipairs(warnings) do
    if w:find(needle, 1, true) then return true end
  end
  return false
end

-- Walk a compiled result's comfyui prompt for the first CLIPTextEncode whose
-- text matches `kind` (positive = no "low quality", negative = has it).
local function clip_texts(result)
  local out = {}
  for _, node in pairs(result.prompt) do
    if type(node) == "table" and node.class_type == "CLIPTextEncode" then
      out[#out + 1] = node.inputs.text
    end
  end
  return out
end

local function count_occurrences(text, needle)
  local n, i = 0, 1
  while true do
    local s = text:find(needle, i, true)
    if not s then break end
    n = n + 1
    i = s + #needle
  end
  return n
end

-- ============================================================
-- unit: split (paren-aware)
-- ============================================================
do
  local s = dedup.split("a, b, c")
  T.eq("split: plain count", #s, 3)
  T.eq("split: plain[2]", s[2], "b")
end
do
  -- comma inside parens must NOT split
  local s = dedup.split("a, (warm tones, warm color palette:1.1), b")
  T.eq("split: paren-aware count", #s, 3)
  T.eq("split: paren clause kept whole", s[2], "(warm tones, warm color palette:1.1)")
end

-- ============================================================
-- unit: fix (exact, case-insensitive, keep-first, emphasis-distinct)
-- ============================================================
T.eq("fix: drops exact dup",
  dedup.fix("bokeh, blurred background, bokeh"),
  "bokeh, blurred background")
T.eq("fix: case-insensitive dup",
  dedup.fix("Bokeh, bokeh"),
  "Bokeh")
T.eq("fix: keeps emphasis-distinct clause",
  dedup.fix("bokeh, (bokeh:1.2)"),
  "bokeh, (bokeh:1.2)")
T.eq("fix: paren clause with inner comma survives",
  dedup.fix("(warm tones, warm color palette:1.1), bokeh, bokeh"),
  "(warm tones, warm color palette:1.1), bokeh")
T.eq("fix: empty passthrough", dedup.fix(""), "")

-- ============================================================
-- unit: check (warn side) on hand-built grouped
-- ============================================================
do
  local grouped = {
    subject = { "1girl, solo" },
    detail  = { "shallow depth of field, bokeh", "bokeh, blurred background" },
  }
  local r = dedup.check(grouped, {})
  T.ok("unit: a duplicate finding emitted", #r.findings >= 1)
  T.eq("unit: finding kind", r.findings[1].kind, "duplicate")
  T.eq("unit: finding clause", r.findings[1].clause, "bokeh")
  T.eq("unit: finding count", r.findings[1].count, 2)
  T.eq("unit: not suppressed by default", r.findings[1].suppressed, false)
end
do
  local grouped = { detail = { "bokeh", "bokeh" } }
  local r = dedup.check(grouped, { dedup = true })
  T.eq("unit: dedup intent suppresses", r.findings[1].suppressed, true)
end

-- ============================================================
-- engine integration: warn + fix + no_lint_fix
-- ============================================================
-- A subject whose two traits both contribute "bokeh" (token-level dup across
-- separate clauses) plus a verbatim duplicate "soft light".
local function dup_subject()
  return vdsl.subject("1girl, solo")
    :with(vdsl.trait("portrait photography, bokeh, soft light"))
    :with(vdsl.trait("shallow depth of field, bokeh, soft light"))
end

do
  local diag = vdsl.check({ world = WORLD, cast = { vdsl.cast { subject = dup_subject() } } })
  T.ok("engine: dedup warned", has(diag.warnings, "dedup:"))
end

do
  -- compile path applies the fix by default
  local result = vdsl.render { world = WORLD, cast = { vdsl.cast { subject = dup_subject() } } }
  local positive = nil
  for _, txt in ipairs(clip_texts(result)) do
    if txt:find("1girl, solo", 1, true) then positive = txt end
  end
  T.ok("fix: positive prompt found", positive ~= nil)
  T.eq("fix: bokeh appears once after autofix", count_occurrences(positive, "bokeh"), 1)
  T.eq("fix: soft light appears once after autofix", count_occurrences(positive, "soft light"), 1)
end

do
  -- no_lint_fix disables the autofix
  local result = vdsl.render {
    world = WORLD, cast = { vdsl.cast { subject = dup_subject() } }, no_lint_fix = true,
  }
  local positive = nil
  for _, txt in ipairs(clip_texts(result)) do
    if txt:find("1girl, solo", 1, true) then positive = txt end
  end
  T.ok("no_lint_fix: positive prompt found", positive ~= nil)
  T.eq("no_lint_fix: bokeh stays duplicated", count_occurrences(positive, "bokeh"), 2)
end

-- negative-side dedup ("deformed face" piled by two negative sources)
do
  local result = vdsl.render {
    world = WORLD,
    cast  = { vdsl.cast {
      subject  = vdsl.subject("1girl, solo"),
      negative = vdsl.trait("bad anatomy, deformed face, blurry, deformed face"),
    } },
  }
  local negative = nil
  for _, txt in ipairs(clip_texts(result)) do
    if txt:find("bad anatomy", 1, true) then negative = txt end
  end
  T.ok("neg: negative prompt found", negative ~= nil)
  T.eq("neg: deformed face deduped", count_occurrences(negative, "deformed face"), 1)
end

T.done()
