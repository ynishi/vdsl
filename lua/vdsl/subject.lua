--- Subject: composable entity representing "who/what" in the scene.
-- Built by chaining Traits. Immutable: every operation returns a new Subject.

local Entity = require("vdsl.entity")
local Trait  = require("vdsl.trait")

local Subject = Entity.define("subject")

-- Quality presets
local QUALITY_PRESETS = {
  high   = "masterpiece, best quality, highly detailed",
  medium = "good quality, detailed",
  draft  = "sketch, rough, concept art",
}

-- Style presets
local STYLE_PRESETS = {
  anime      = "anime style, cel shading, 2D",
  photo      = "photorealistic, 8k uhd, raw photo",
  oil        = "oil painting, classical art, brush strokes",
  watercolor = "watercolor painting, soft edges, wet media",
  pixel      = "pixel art, retro game, 8-bit",
  ["3d"]     = "3d render, octane render, unreal engine",
}

--- Create a new Subject from a base description.
-- @param base_text string core identity (e.g. "cat", "warrior woman")
-- @return Subject
function Subject.new(base_text)
  if type(base_text) ~= "string" or base_text == "" then
    error("Subject: base text is required", 2)
  end
  local self = setmetatable({}, Subject)
  self._traits = { Trait.new(base_text) }
  return self
end

--- Create a Subject from a single Trait (preserves hints).
-- @param trait Trait
-- @return Subject
function Subject.from_trait(trait)
  local self = setmetatable({}, Subject)
  self._traits = { trait }
  return self
end

--- Clone this Subject (internal, for immutability).
function Subject:_clone()
  local new = setmetatable({}, Subject)
  new._traits = {}
  for i, t in ipairs(self._traits) do
    new._traits[i] = t
  end
  return new
end

--- Add a Trait or string. Returns a new Subject (immutable).
-- @param trait_or_string Trait|string
-- @return Subject
function Subject:with(trait_or_string)
  local new = self:_clone()
  if type(trait_or_string) == "string" then
    new._traits[#new._traits + 1] = Trait.new(trait_or_string)
  elseif Entity.is(trait_or_string, "trait") then
    new._traits[#new._traits + 1] = trait_or_string
  else
    error("Subject:with expects a string or Trait", 2)
  end
  return new
end

--- Add a quality preset trait.
-- @param level string "high"|"medium"|"draft"
-- @return Subject
function Subject:quality(level)
  local text = QUALITY_PRESETS[level]
  if not text then
    local available = {}
    for k in pairs(QUALITY_PRESETS) do available[#available + 1] = k end
    table.sort(available)
    error("Subject:quality unknown '" .. level
      .. "', available: " .. table.concat(available, ", "), 2)
  end
  return self:with(Trait.new(text))
end

--- Add a style preset trait.
-- @param name string "anime"|"photo"|"oil"|"watercolor"|"pixel"|"3d"
-- @return Subject
function Subject:style(name)
  local text = STYLE_PRESETS[name]
  if not text then
    local available = {}
    for k in pairs(STYLE_PRESETS) do available[#available + 1] = k end
    table.sort(available)
    error("Subject:style unknown '" .. name
      .. "', available: " .. table.concat(available, ", "), 2)
  end
  return self:with(Trait.new(text))
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
  new._traits = {}
  for _, t in ipairs(self._traits) do
    if t == old_trait then
      new._traits[#new._traits + 1] = new_trait
    else
      new._traits[#new._traits + 1] = t
    end
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

--- Resolve all traits into a single prompt string.
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

return Subject
