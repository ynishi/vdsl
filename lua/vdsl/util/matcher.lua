--- Matcher: fuzzy resource name matching.
-- Extracted from registry for single-responsibility.
-- Supports custom matcher injection (e.g. Rust fuzzy-match crate).

local M = {}

local custom_matcher = nil

--- Default scorer: case-insensitive, multi-strategy.
-- @param query string search term
-- @param name string candidate name
-- @return number score (0 = no match, higher = better)
function M.default_score(query, name)
  local q = query:lower()
  local n = name:lower()

  -- Exact match
  if n == q then return 1000 end

  -- Exact match without extension
  local n_stem = n:gsub("%.[^%.]+$", "")
  if n_stem == q then return 900 end

  -- Starts with query
  if n:sub(1, #q) == q then return 500 + (1.0 / #name) end
  if n_stem:sub(1, #q) == q then return 400 + (1.0 / #name) end

  -- Contains query
  if n:find(q, 1, true) then return 100 + (1.0 / #name) end

  -- Normalized match: strip separators
  local q_norm = q:gsub("[_%-%.%s]", "")
  local n_norm = n:gsub("[_%-%.%s]", "")
  if n_norm == q_norm then return 850 end
  if n_norm:sub(1, #q_norm) == q_norm then return 350 + (1.0 / #name) end
  if n_norm:find(q_norm, 1, true) then return 80 + (1.0 / #name) end

  -- Tokenized match
  local q_tokens = {}
  for token in q:gmatch("[^_%-%.%s]+") do
    q_tokens[#q_tokens + 1] = token
  end
  if #q_tokens > 1 then
    local all_found = true
    for _, qt in ipairs(q_tokens) do
      if not n:find(qt, 1, true) then
        all_found = false
        break
      end
    end
    if all_found then return 50 + (1.0 / #name) end
  end

  return 0
end

--- Find the best matching resource from a list.
-- @param query string search term
-- @param candidates table list of resource names
-- @param resource_type string category name for error messages
-- @return string matched resource name
function M.find(query, candidates, resource_type)
  if not candidates or #candidates == 0 then
    error("no " .. resource_type .. " available on server", 3)
  end

  local best_name = nil
  local best_score = 0  -- intentional: score > 0 required to match (0 = no match)
  local scorer = custom_matcher or M.default_score

  for _, name in ipairs(candidates) do
    local score = scorer(query, name)
    if score > best_score then
      best_name = name
      best_score = score
    end
  end

  if not best_name then
    local preview = {}
    for i = 1, math.min(10, #candidates) do
      preview[i] = candidates[i]
    end
    local suffix = ""
    if #candidates > 10 then
      suffix = string.format(" ... (+%d more)", #candidates - 10)
    end
    error(string.format(
      "no %s matching '%s'\n  available: %s%s",
      resource_type, query, table.concat(preview, ", "), suffix
    ), 3)
  end

  return best_name
end

--- Replace the default fuzzy matcher.
-- @param fn function(query, name) -> number | nil to restore default
function M.set_matcher(fn)
  if fn ~= nil and type(fn) ~= "function" then
    error("set_matcher expects a function or nil", 2)
  end
  custom_matcher = fn
end

--- Get the default scoring function.
-- @return function
function M.get_default()
  return M.default_score
end

return M
