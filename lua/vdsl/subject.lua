--- Subject: composable entity representing "who/what" in the scene.
-- Built by chaining Traits. Immutable: every operation returns a new Subject.
--
-- Each trait is tagged with a category for strategy-based prompt ordering:
--   "subject"  — base identity (auto-set by new/from_trait)
--   "quality"  — quality level (set by :quality())
--   "style"    — artistic medium (set by :style())
--   "detail"   — everything else (default for :with())
--
-- Recursive composition:
--   Subject can contain inner Subjects via :with().
--   Inner Subjects whose base trait carries hint("merge") undergo
--   Accumulative Mutation (AccMut) at resolve time:
--     Subject.part("eyes"):with(Trait.new("blue"))
--     → resolves to "blue eyes" (modifier prepended to base noun).
--   This keeps the DSL layer semantic — the merge rule is a hint
--   consumed during resolution, not domain knowledge in the DSL.

local Entity = require("vdsl.entity")
local Trait  = require("vdsl.trait")

local Subject = Entity.define("subject")

--- Create a new Subject from a base description.
-- @param base_text string core identity (e.g. "cat", "warrior woman")
-- @return Subject
function Subject.new(base_text)
  if type(base_text) ~= "string" or base_text == "" then
    error("Subject: base text is required", 2)
  end
  local self = setmetatable({}, Subject)
  self._traits     = { Trait.new(base_text) }
  self._categories = { "subject" }
  return self
end

--- Create a Subject from a single Trait (preserves hints).
-- @param trait Trait
-- @return Subject
function Subject.from_trait(trait)
  local self = setmetatable({}, Subject)
  self._traits     = { trait }
  self._categories = { "subject" }
  return self
end

--- Clone this Subject (internal, for immutability).
function Subject:_clone()
  local new = setmetatable({}, Subject)
  new._traits     = {}
  new._categories = {}
  for i, t in ipairs(self._traits) do
    new._traits[i]     = t
    new._categories[i] = self._categories[i]
  end
  return new
end

--- Add a Trait or string. Returns a new Subject (immutable).
-- @param trait_or_string Trait|string
-- @param category string|nil trait category ("subject","quality","style","detail")
-- @return Subject
function Subject:with(trait_or_string, category)
  local new = self:_clone()
  if type(trait_or_string) == "string" then
    new._traits[#new._traits + 1] = Trait.new(trait_or_string)
  elseif Entity.is(trait_or_string, "trait") then
    new._traits[#new._traits + 1] = trait_or_string
  else
    error("Subject:with expects a string or Trait", 2)
  end
  new._categories[#new._categories + 1] = category or "detail"
  return new
end

--- Add a quality preset trait.
-- Looks up from catalogs.quality. Available: "high", "medium", "draft".
-- @param level string quality level
-- @return Subject
function Subject:quality(level)
  local catalog = require("vdsl.catalogs.quality")
  local trait = catalog[level]
  if not trait then
    local available = {}
    for k in pairs(catalog) do available[#available + 1] = k end
    table.sort(available)
    error("Subject:quality unknown '" .. level
      .. "', available: " .. table.concat(available, ", "), 2)
  end
  return self:with(trait, "quality")
end

--- Add a style preset trait.
-- Looks up from catalogs.style. Available: "anime", "photo", "oil", etc.
-- @param name string style name
-- @return Subject
function Subject:style(name)
  local catalog = require("vdsl.catalogs.style")
  local trait = catalog[name]
  if not trait then
    local available = {}
    for k in pairs(catalog) do available[#available + 1] = k end
    table.sort(available)
    error("Subject:style unknown '" .. name
      .. "', available: " .. table.concat(available, ", "), 2)
  end
  return self:with(trait, "style")
end

--- Replace a specific Trait with another. Identity-based (same table reference).
-- @param old_trait Trait to replace
-- @param new_trait Trait|string replacement
-- @return Subject
function Subject:replace(old_trait, new_trait)
  if type(new_trait) == "string" then
    new_trait = Trait.new(new_trait)
  end
  local new = setmetatable({}, Subject)
  new._traits     = {}
  new._categories = {}
  for i, t in ipairs(self._traits) do
    if t == old_trait then
      new._traits[#new._traits + 1] = new_trait
    else
      new._traits[#new._traits + 1] = t
    end
    new._categories[#new._categories + 1] = self._categories[i]
  end
  return new
end

--- Collect merged hints from all traits.
-- Later traits win on conflict (same key).
-- @return table|nil merged hints or nil if none
function Subject:hints()
  local merged = nil
  for _, t in ipairs(self._traits) do
    local h = t:hints()
    if h then
      if not merged then merged = {} end
      for k, v in pairs(h) do
        merged[k] = v
      end
    end
  end
  return merged
end

--- Collect trait diagnostics for compiler analysis.
-- Returns per-trait confidence, tags, hints, and resolved text.
-- @return table array of { text, confidence, tags, hints, category }
function Subject:trait_diagnostics()
  local diags = {}
  for i, t in ipairs(self._traits) do
    local cat = (self._categories and self._categories[i])
             or (i == 1 and "subject" or "detail")
    diags[#diags + 1] = {
      text       = t:resolve(),
      confidence = t:get_confidence(),
      tags       = t:get_tags(),
      hints      = t:hints(),
      category   = cat,
    }
  end
  return diags
end

--- Resolve all traits into a single prompt string (natural order).
-- @return string
function Subject:resolve()
  local parts = {}
  for _, t in ipairs(self._traits) do
    local resolved = t:resolve()
    if resolved ~= "" then
      parts[#parts + 1] = resolved
    end
  end
  return table.concat(parts, ", ")
end

--- Resolve traits grouped by category.
-- Returns { category_name = { "resolved text", ... }, ... }
-- Used by compiler strategies for prompt reordering.
-- @return table
function Subject:resolve_grouped()
  local groups = {}
  for i, t in ipairs(self._traits) do
    local cat = (self._categories and self._categories[i])
             or (i == 1 and "subject" or "detail")
    if not groups[cat] then groups[cat] = {} end
    local resolved = t:resolve()
    if resolved ~= "" then
      groups[cat][#groups[cat] + 1] = resolved
    end
  end
  return groups
end

return Subject
