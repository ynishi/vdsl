--- Trait: atomic prompt fragment with optional emphasis and compiler hints.
-- The building block for composable prompt construction.
-- Supports + operator, :with() chaining, and :hint() for auto-post.

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
  self.text     = text
  self.emphasis = emphasis or 1.0
  self._parts   = nil  -- nil = single, table = composite
  self._hints   = nil  -- nil = no hints, table = { op_type = params }
  return self
end

--- Flatten a trait's parts into a target list.
local function flatten_into(target, t)
  if t._parts then
    for _, p in ipairs(t._parts) do
      target[#target + 1] = p
    end
  else
    target[#target + 1] = {
      text = t.text, emphasis = t.emphasis,
    }
  end
end

--- Merge hints from src into dst (src wins on conflict).
local function merge_hints(dst, src)
  if not src then return end
  for k, v in pairs(src) do
    dst[k] = v
  end
end

--- Combine two traits with + operator.
-- Hints are merged (right side wins on conflict).
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
      new._parts[#new._parts + 1] = p
    end
  else
    new.text     = self.text
    new.emphasis = self.emphasis
  end
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

--- Resolve to a prompt string.
-- Applies emphasis syntax: (text:1.5) for non-1.0 emphasis.
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

return Trait
