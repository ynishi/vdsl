--- Trait: atomic prompt fragment with optional emphasis, confidence, tags, and compiler hints.
-- The building block for composable prompt construction.
-- Supports * (space-join), + (comma-compose), :with() chaining, :hint() for auto-post,
-- :confidence() for reliability scoring, and :tag() for arbitrary metadata.

local Entity = require("vdsl.entity")

local Trait = Entity.define("trait")

--- Create a new Trait.
-- @param text string prompt fragment
-- @param emphasis number|nil emphasis weight (1.0 = normal, >1 = stronger)
-- @return Trait
function Trait.new(text, emphasis)
  if type(text) ~= "string" or text == "" then
    error("Trait: text is required", 2)
  end
  local self = setmetatable({}, Trait)
  self.text        = text
  self.emphasis    = emphasis or 1.0
  self._parts      = nil  -- nil = single, table = composite
  self._hints      = nil  -- nil = no hints, table = { op_type = params }
  self._confidence = nil  -- nil = unset (treated as 1.0), number = 0.0-1.0
  self._tags       = nil  -- nil = no tags, table = { key = value }
  return self
end

--- Flatten a trait's parts into a target list.
-- Carries confidence and tags per part for composite preservation.
local function flatten_into(target, t)
  if t._parts then
    for _, p in ipairs(t._parts) do
      target[#target + 1] = p
    end
  else
    target[#target + 1] = {
      text       = t.text,
      emphasis   = t.emphasis,
      confidence = t._confidence,
      tags       = t._tags,
    }
  end
end

--- Merge a key-value table from src into dst (src wins on conflict).
local function merge_table(dst, src)
  if not src then return end
  for k, v in pairs(src) do
    dst[k] = v
  end
end

--- Merge hints from src into dst (src wins on conflict).
-- Alias kept for readability in hint-specific code.
local merge_hints = merge_table

--- Copy metadata (confidence, tags, hints) from src Trait to dst Trait.
-- Used by immutable-copy methods to preserve metadata across transforms.
local function copy_meta(dst, src)
  dst._confidence = src._confidence
  if src._tags then
    dst._tags = {}
    merge_table(dst._tags, src._tags)
  end
  if src._hints then
    dst._hints = {}
    merge_hints(dst._hints, src._hints)
  end
end

--- Space-join two traits with * operator.
-- Merges text into a single Trait. Hints/tags are merged (right side wins).
-- Confidence takes the minimum (conservative: weakest link).
-- Higher precedence than + so:  a * b + c  →  "a b, c"
-- @return Trait single (not composite)
function Trait.__mul(a, b)
  if type(a) == "string" then a = Trait.new(a) end
  if type(b) == "string" then b = Trait.new(b) end

  local text = a:resolve() .. " " .. b:resolve()
  local result = Trait.new(text)

  -- Merge hints
  if a._hints or b._hints then
    result._hints = {}
    merge_hints(result._hints, a._hints)
    merge_hints(result._hints, b._hints)
  end

  -- Merge tags
  if a._tags or b._tags then
    result._tags = {}
    merge_table(result._tags, a._tags)
    merge_table(result._tags, b._tags)
  end

  -- Confidence: min of both (conservative)
  local ca = a._confidence or a:get_confidence()
  local cb = b._confidence or b:get_confidence()
  if a._confidence or b._confidence then
    result._confidence = math.min(ca, cb)
  end

  return result
end

--- Combine two traits with + operator (comma-compose).
-- Hints/tags are merged at composite level (right side wins on conflict).
-- Per-part confidence/tags are preserved via flatten_into.
-- @return Trait composite
function Trait.__add(a, b)
  if type(a) == "string" then a = Trait.new(a) end
  if type(b) == "string" then b = Trait.new(b) end

  local composite = setmetatable({}, Trait)
  composite._parts = {}
  flatten_into(composite._parts, a)
  flatten_into(composite._parts, b)

  -- Merge hints
  if a._hints or b._hints then
    composite._hints = {}
    merge_hints(composite._hints, a._hints)
    merge_hints(composite._hints, b._hints)
  end

  -- Composite-level confidence: min across all parts
  local min_c = nil
  for _, p in ipairs(composite._parts) do
    local pc = p.confidence or 1.0
    if not min_c or pc < min_c then
      min_c = pc
    end
  end
  if min_c and min_c < 1.0 then
    composite._confidence = min_c
  end

  -- Composite-level tags: merged from all parts (later wins)
  local has_tags = false
  for _, p in ipairs(composite._parts) do
    if p.tags then has_tags = true; break end
  end
  if has_tags then
    composite._tags = {}
    for _, p in ipairs(composite._parts) do
      merge_table(composite._tags, p.tags)
    end
  end

  return composite
end

--- Chain-style composition.
-- @param other Trait|string
-- @return Trait composite
function Trait:with(other)
  if type(other) == "string" then
    return self + Trait.new(other)
  end
  return self + other
end

--- Set confidence score. Returns a new Trait (immutable).
-- Confidence represents how reliably this tag produces the intended effect.
-- @param value number 0.0 (unreliable) to 1.0 (highly reliable)
-- @return Trait
function Trait:confidence(value)
  if type(value) ~= "number" then
    error("Trait:confidence: value must be a number", 2)
  end
  if value < 0.0 or value > 1.0 then
    error("Trait:confidence: value must be 0.0-1.0, got " .. value, 2)
  end
  local new = setmetatable({}, Trait)
  if self._parts then
    new._parts = {}
    for _, p in ipairs(self._parts) do
      new._parts[#new._parts + 1] = {
        text       = p.text,
        emphasis   = p.emphasis,
        confidence = p.confidence,
        tags       = p.tags,
      }
    end
  else
    new.text     = self.text
    new.emphasis = self.emphasis
  end
  copy_meta(new, self)
  new._confidence = value
  return new
end

--- Get effective confidence (nil-safe).
-- @return number confidence value (1.0 if unset)
function Trait:get_confidence()
  if self._confidence then
    return self._confidence
  end
  if self._parts then
    local min_c = 1.0
    for _, p in ipairs(self._parts) do
      local pc = p.confidence or 1.0
      if pc < min_c then min_c = pc end
    end
    return min_c
  end
  return 1.0
end

--- Set a tag key-value pair. Returns a new Trait (immutable).
-- Use TagKeys constants for reserved keys, or any string for custom keys.
-- @param key string tag key
-- @param value any tag value (string recommended)
-- @return Trait
function Trait:tag(key, value)
  if type(key) ~= "string" or key == "" then
    error("Trait:tag: key must be a non-empty string", 2)
  end
  local new = setmetatable({}, Trait)
  if self._parts then
    new._parts = {}
    for _, p in ipairs(self._parts) do
      new._parts[#new._parts + 1] = {
        text       = p.text,
        emphasis   = p.emphasis,
        confidence = p.confidence,
        tags       = p.tags,
      }
    end
  else
    new.text     = self.text
    new.emphasis = self.emphasis
  end
  copy_meta(new, self)
  if not new._tags then new._tags = {} end
  new._tags[key] = value
  return new
end

--- Get a tag value by key.
-- @param key string tag key
-- @return any|nil tag value
function Trait:get_tag(key)
  if self._tags then
    return self._tags[key]
  end
  return nil
end

--- Get all tags (shallow copy).
-- @return table|nil tags table or nil if none
function Trait:get_tags()
  if not self._tags then return nil end
  local copy = {}
  for k, v in pairs(self._tags) do
    copy[k] = v
  end
  return copy
end

--- Attach a compiler hint. Returns a new Trait (immutable).
-- Hints tell the compiler to auto-generate Post operations.
-- @param op_type string post operation type (e.g. "face", "hires")
-- @param params table|nil operation parameters
-- @return Trait
function Trait:hint(op_type, params)
  if type(op_type) ~= "string" or op_type == "" then
    error("Trait:hint: op_type is required", 2)
  end
  local new = setmetatable({}, Trait)
  if self._parts then
    new._parts = {}
    for _, p in ipairs(self._parts) do
      new._parts[#new._parts + 1] = {
        text       = p.text,
        emphasis   = p.emphasis,
        confidence = p.confidence,
        tags       = p.tags,
      }
    end
  else
    new.text     = self.text
    new.emphasis = self.emphasis
  end
  -- Copy confidence and tags
  new._confidence = self._confidence
  if self._tags then
    new._tags = {}
    merge_table(new._tags, self._tags)
  end
  -- Merge hints (new hint added)
  new._hints = {}
  merge_hints(new._hints, self._hints)
  new._hints[op_type] = params or {}
  return new
end

--- Get hints table (for compiler/subject).
-- @return table|nil
function Trait:hints()
  return self._hints
end

--- Adjust emphasis of primary tags by a relative delta. Returns a new Trait (immutable).
-- Primary = parts with emphasis ~= 1.0 (the concept tags, not supplementary).
-- If all parts are 1.0 (no emphasis set), adjusts the first part.
-- @param delta number emphasis adjustment (e.g. 0.2 to increase, -0.1 to decrease)
-- @return Trait
function Trait:boost(delta)
  if type(delta) ~= "number" then
    error("Trait:boost: delta must be a number", 2)
  end

  local new = setmetatable({}, Trait)

  if self._parts then
    new._parts = {}
    local adjusted_any = false
    for _, p in ipairs(self._parts) do
      if p.emphasis ~= 1.0 then
        new._parts[#new._parts + 1] = {
          text       = p.text,
          emphasis   = p.emphasis + delta,
          confidence = p.confidence,
          tags       = p.tags,
        }
        adjusted_any = true
      else
        new._parts[#new._parts + 1] = {
          text       = p.text,
          emphasis   = p.emphasis,
          confidence = p.confidence,
          tags       = p.tags,
        }
      end
    end
    if not adjusted_any and #new._parts > 0 then
      new._parts[1].emphasis = new._parts[1].emphasis + delta
    end
  else
    new.text     = self.text
    new.emphasis = self.emphasis + delta
  end

  copy_meta(new, self)

  return new
end

--- Resolve to a prompt string.
-- Applies emphasis syntax: (text:1.5) for non-1.0 emphasis.
-- Confidence and tags do NOT affect prompt text (metadata only).
-- @return string
function Trait:resolve()
  if self._parts then
    local parts = {}
    for _, p in ipairs(self._parts) do
      if p.emphasis ~= 1.0 then
        parts[#parts + 1] = string.format("(%s:%.1f)", p.text, p.emphasis)
      else
        parts[#parts + 1] = p.text
      end
    end
    return table.concat(parts, ", ")
  else
    if self.emphasis ~= 1.0 then
      return string.format("(%s:%.1f)", self.text, self.emphasis)
    end
    return self.text
  end
end

-- ============================================================
-- Tag key constants (prevent typos for commonly used keys)
-- ============================================================

Trait.TIER      = "tier"       -- Reliability tier: "S", "A", "B", "C"
Trait.CONFLICTS = "conflicts"  -- Conflicting trait text
Trait.SOURCE    = "source"     -- Provenance: "danbooru", "civitai", etc.

return Trait
