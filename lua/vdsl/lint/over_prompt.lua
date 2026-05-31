--- Over-prompt lint: detect category-localized prompt overflow (warn-only).
--
-- Some prompt failures are not about total length but about a single category
-- being piled too high: lighting words washing an image out ("light burn"),
-- or 2D-style words flattening a photoreal subject ("cartoonification").
-- These typically come from stacking supplementary words on top of a preset
-- anchor (:quality() / :style()) that already occupies that dimension.
--
-- This pass operates on Subject:resolve_grouped() output. Because cam overlays
-- and bare :with() traits collapse into the "detail" category, structural
-- category alone cannot tell lighting from 2D — so a static lexicon classifies
-- supplementary clauses, while the structural quality/style groups act as the
-- "anchor present" signal for double-anchor detection.
--
-- Detection only. This module never blocks, folds, or rewrites a prompt; it
-- emits findings that the caller surfaces as warnings. Authors silence
-- intentional cases (a deliberately blown-out highlight) via Shot:intent().
--
-- The default lexicon / budget below are tuned for cam-style photoreal/anime
-- portraits (see findings in the cam quality work). Callers may override
-- M.LEXICON / M.BUDGET, or pass their own to M.check via a future config hook.

local M = {}

--- Lexical categories → lowercase substring patterns (plain find, no magic).
-- light = illumination / glow / atmosphere words (light-burn predictor).
-- lock  = 2D / flat / line-art words (cartoonification predictor).
-- quality = booster words (used for double-anchor against a :quality() preset).
M.LEXICON = {
  light = {
    "golden glow", "golden hour", "amber", "evening light", "warm light",
    "warm tones", "warm amber", "moody", "sunlight", "sunbeam", "bokeh",
    "atmosphere", "soft light", "backlight", "rim light", "candlelight",
    "lens flare", "dappled light", "ambient light", "window light",
    "natural light", "glow", "glowing", "radiant", "luminous",
  },
  lock = {
    "cel shading", "cel-shaded", "flat color", "flat colour", "clean lineart",
    "lineart", "line art", "2d", "masterwork illustration", "anime style",
    "manga", "toon", "vector art", "comic style", "flat shading",
  },
  quality = {
    "masterpiece", "best quality", "highly detailed", "sharp focus",
    "high resolution", "ultra detailed", "ultra-detailed", "8k", "4k",
    "intricate detail",
  },
}

--- Per-category soft budget (max supplementary clauses before a warn).
-- Sourced from the cam baseline measurement (clean hand-written max).
M.BUDGET = { light = 3, lock = 2, quality = 5 }

--- Structural Subject category → the lexcat its preset anchors.
-- A non-empty quality/style group means that dimension is already anchored,
-- so any supplementary word in the same lexcat is a double-anchor.
M.ANCHOR_CAT = { quality = "quality", style = "lock" }

--- Friendly intent aliases → lexcat. Lets authors write a semantic reason
-- (Shot:intent("blown-highlight")) instead of the raw lexcat.
M.ALIAS = {
  ["blown-highlight"] = "light",
  ["over-light"]      = "light",
  ["dramatic-light"]  = "light",
  ["stylized"]        = "lock",
  ["flat-2d"]         = "lock",
  ["heavy-quality"]   = "quality",
}

-- Structural categories treated as preset anchors (excluded from supplementary).
local ANCHOR_GROUPS = { quality = true, style = true }

-- Deterministic lexcat scan order (stable output ordering).
local LEXCAT_ORDER = { "light", "lock", "quality" }

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Classify a single clause into at most one lexcat.
-- First lexcat (in LEXCAT_ORDER) with a substring match wins, so a clause is
-- counted once regardless of how many patterns it hits.
-- @param clause string a single comma-delimited prompt clause
-- @return string|nil lexcat, or nil when the clause matches no lexicon
function M.classify(clause)
  local c = clause:lower()
  for _, lexcat in ipairs(LEXCAT_ORDER) do
    for _, pat in ipairs(M.LEXICON[lexcat]) do
      if c:find(pat, 1, true) then
        return lexcat
      end
    end
  end
  return nil
end

--- Split a resolved group entry into trimmed, non-empty clauses (by comma).
local function split_clauses(text)
  local out = {}
  for piece in text:gmatch("[^,]+") do
    local t = trim(piece)
    if t ~= "" then out[#out + 1] = t end
  end
  return out
end

--- Normalize an intents table into a set of suppressed lexcats.
-- Accepts a set form ({ light = true }), an array form ({ "blown-highlight" }),
-- or a mix. Tokens are resolved through M.ALIAS, then accepted if they name a
-- known lexcat. Unknown tokens are ignored (no error — lint is best-effort).
-- @param intents table|nil
-- @return table set of { [lexcat] = true }
local function normalize_intents(intents)
  local set = {}
  if type(intents) ~= "table" then return set end
  local function accept(token)
    if type(token) ~= "string" then return end
    local lexcat = M.ALIAS[token] or token
    if M.BUDGET[lexcat] ~= nil then set[lexcat] = true end
  end
  for k, v in pairs(intents) do
    if type(k) == "number" then
      accept(v)          -- array form: value is the token
    elseif v then
      accept(k)          -- set form: key is the token, truthy value
    end
  end
  return set
end

--- Check a resolved-grouped Subject for over-prompt findings.
-- @param grouped table  Subject:resolve_grouped() output ({ cat = { "text", ... } })
-- @param intents table|nil  suppressed lexcats (set or array; aliases allowed)
-- @return table {
--   anchors  = { [lexcat] = true },              -- preset-anchored dimensions
--   counts   = { [lexcat] = number },            -- supplementary clause counts
--   matched  = { [lexcat] = { "clause", ... } }, -- named clauses per lexcat
--   findings = { { lexcat, kind, count, budget, clauses, suppressed }, ... },
-- }
-- kind ∈ { "over_budget", "double_anchor" }. suppressed=true means an intent
-- silenced this finding (the caller should not surface it as a warning).
function M.check(grouped, intents)
  grouped = grouped or {}
  local suppressed = normalize_intents(intents)

  -- Anchor detection: a non-empty preset group anchors its dimension.
  local anchors = {}
  for cat, lexcat in pairs(M.ANCHOR_CAT) do
    local g = grouped[cat]
    if g and #g > 0 then anchors[lexcat] = true end
  end

  -- Tally supplementary clauses (everything outside the anchor groups).
  local counts  = { light = 0, lock = 0, quality = 0 }
  local matched = { light = {}, lock = {}, quality = {} }
  for cat, entries in pairs(grouped) do
    if not ANCHOR_GROUPS[cat] then
      for _, entry in ipairs(entries) do
        for _, clause in ipairs(split_clauses(entry)) do
          local lexcat = M.classify(clause)
          if lexcat then
            counts[lexcat] = counts[lexcat] + 1
            matched[lexcat][#matched[lexcat] + 1] = clause
          end
        end
      end
    end
  end

  -- Build findings in stable order.
  local findings = {}
  for _, lexcat in ipairs(LEXCAT_ORDER) do
    local n      = counts[lexcat]
    local budget = M.BUDGET[lexcat]
    if n > budget then
      findings[#findings + 1] = {
        lexcat = lexcat, kind = "over_budget",
        count = n, budget = budget, clauses = matched[lexcat],
        suppressed = suppressed[lexcat] == true,
      }
    elseif anchors[lexcat] and n >= 1 then
      findings[#findings + 1] = {
        lexcat = lexcat, kind = "double_anchor",
        count = n, budget = budget, clauses = matched[lexcat],
        suppressed = suppressed[lexcat] == true,
      }
    end
  end

  return { anchors = anchors, counts = counts, matched = matched, findings = findings }
end

--- Format a finding into a human-readable, deterministic warning line.
-- The caller (engine M.check) prepends a "cast[N] " locator.
-- @param finding table one element of M.check(...).findings
-- @return string
function M.format(finding)
  local clauses = table.concat(finding.clauses, " / ")
  if finding.kind == "over_budget" then
    return string.format(
      "over-prompt: %s x%d supplementary (budget %d) -> %s",
      finding.lexcat, finding.count, finding.budget, clauses)
  else
    return string.format(
      "over-prompt: %s preset anchor + %d supplementary -> %s",
      finding.lexcat, finding.count, clauses)
  end
end

return M
