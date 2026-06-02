--- Dedup lint: detect (warn) and remove (fix) duplicate prompt clauses.
--
-- Unlike over_prompt (detection only), dedup follows the ESLint model: it can
-- both *report* duplicate clauses (M.check -> findings, surfaced as warnings)
-- and *fix* them (M.fix -> a deduplicated prompt string). The fix is applied in
-- the compile path and can be disabled per-render via `no_lint_fix = true`.
--
-- A "clause" is one comma-separated prompt token. Splitting is paren-aware: a
-- weighted group like `(warm tones, warm color palette:1.1)` carries an internal
-- comma but is a single clause, so commas inside parentheses do not split.
--
-- Dedup is exact (case-insensitive on clause text), keep-first. Emphasis is part
-- of the clause text, so `word` and `(word:1.2)` are treated as DISTINCT clauses
-- (we never reinterpret a weight as intensity — see docs/over-prompt-lint.md).
-- This makes the fix meaning-preserving: only verbatim repeats are removed.

local M = {}

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Paren-aware comma split into trimmed, non-empty clauses.
-- Commas inside parentheses (weighted groups) do not split the clause.
-- @param text string
-- @return table array of clause strings
function M.split(text)
  if type(text) ~= "string" then return {} end
  local out, buf, depth = {}, {}, 0
  local function flush()
    local t = trim(table.concat(buf))
    if t ~= "" then out[#out + 1] = t end
    buf = {}
  end
  for i = 1, #text do
    local ch = text:sub(i, i)
    if ch == "(" then
      depth = depth + 1
      buf[#buf + 1] = ch
    elseif ch == ")" then
      if depth > 0 then depth = depth - 1 end
      buf[#buf + 1] = ch
    elseif ch == "," and depth == 0 then
      flush()
    else
      buf[#buf + 1] = ch
    end
  end
  flush()
  return out
end

--- Remove exact duplicate clauses (case-insensitive, keep-first).
-- @param text string  comma-joined prompt
-- @return string  deduplicated prompt (", " joined)
function M.fix(text)
  if type(text) ~= "string" or text == "" then return text end
  local clauses = M.split(text)
  local seen, kept = {}, {}
  for _, c in ipairs(clauses) do
    local key = c:lower()
    if not seen[key] then
      seen[key] = true
      kept[#kept + 1] = c
    end
  end
  -- No duplicate removed → return the original verbatim so clean prompts are
  -- byte-identical (avoid re-normalizing comma spacing on non-dup prompts).
  if #kept == #clauses then return text end
  return table.concat(kept, ", ")
end

--- Is the dedup lint suppressed for this render?
-- Mirrors over_prompt's intents mechanism: Shot:intent("dedup") (set or array
-- form) silences the dedup warning. Suppression affects warnings only — the fix
-- is controlled separately by `no_lint_fix`.
-- @param intents table|nil
-- @return boolean
local function is_suppressed(intents)
  if type(intents) ~= "table" then return false end
  for k, v in pairs(intents) do
    if type(k) == "number" then
      if v == "dedup" then return true end
    elseif k == "dedup" and v then
      return true
    end
  end
  return false
end

--- Check a resolved-grouped Subject for duplicate clauses (warn-only side).
-- @param grouped table  Subject:resolve_grouped() output ({ cat = { "text", ... } })
-- @param intents table|nil  suppressed lints (set or array; "dedup" silences)
-- @return table {
--   findings = { { kind="duplicate", clause, count, suppressed }, ... },
-- }  findings are ordered by first occurrence (stable output).
function M.check(grouped, intents)
  grouped = grouped or {}
  local suppressed = is_suppressed(intents)

  -- Flatten every group entry into paren-aware clauses, preserving order.
  local count, order, sample = {}, {}, {}
  for _, entries in pairs(grouped) do
    for _, entry in ipairs(entries) do
      for _, clause in ipairs(M.split(entry)) do
        local key = clause:lower()
        if count[key] == nil then
          count[key] = 0
          order[#order + 1] = key
          sample[key] = clause -- first-seen casing for the message
        end
        count[key] = count[key] + 1
      end
    end
  end

  local findings = {}
  for _, key in ipairs(order) do
    if count[key] > 1 then
      findings[#findings + 1] = {
        kind       = "duplicate",
        clause     = sample[key],
        count      = count[key],
        suppressed = suppressed,
      }
    end
  end
  return { findings = findings }
end

--- Format a finding into a human-readable, deterministic warning line.
-- The caller (engine M.check) prepends a "cast[N] " locator.
-- @param finding table one element of M.check(...).findings
-- @return string
function M.format(finding)
  return string.format(
    "dedup: \"%s\" x%d (duplicate clause)", finding.clause, finding.count)
end

return M
