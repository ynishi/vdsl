--- Cast: subject definition entity.
-- Maps to: CLIPTextEncode, LoraLoader, IPAdapterApply
--
-- V2: Always subject-based. Strings auto-coerce to Subject.
-- Negative always coerces to Trait.

local Entity  = require("vdsl.entity")
local Subject = require("vdsl.subject")
local Trait   = require("vdsl.trait")

local Cast = Entity.define("cast")

--- Validate a single LoRA entry.
local function validate_lora(lora, index)
  if type(lora) ~= "table" then
    error("Cast: lora[" .. index .. "] must be a table", 3)
  end
  if not lora.name or lora.name == "" then
    error("Cast: lora[" .. index .. "].name is required", 3)
  end
end

--- Validate IPAdapter config.
local function validate_ipadapter(ipa)
  if type(ipa) ~= "table" then
    error("Cast: ipadapter must be a table", 3)
  end
  if not ipa.image or ipa.image == "" then
    error("Cast: ipadapter.image is required", 3)
  end
end

--- Coerce a value to Subject.
-- @param v string|Subject|Trait
-- @return Subject
local function to_subject(v)
  if type(v) == "string" then
    return Subject.new(v)
  end
  if Entity.is(v, "subject") then
    return v
  end
  if Entity.is(v, "trait") then
    return Subject.from_trait(v)
  end
  error("Cast: 'subject' must be a string, Subject, or Trait", 3)
end

--- Coerce a value to Trait (or nil).
-- @param v string|Trait|nil
-- @return Trait|nil
local function to_trait(v)
  if v == nil or v == "" then return nil end
  if type(v) == "string" then return Trait.new(v) end
  if Entity.is(v, "trait") then return v end
  error("Cast: 'negative' must be a string or Trait", 3)
end

--- Create a Cast entity.
-- @param opts table { subject (required), negative, lora, ipadapter }
-- @return Cast
function Cast.new(opts)
  if type(opts) ~= "table" then
    error("Cast: expected a table, got " .. type(opts), 2)
  end

  if opts.subject == nil then
    error("Cast: 'subject' is required (string or Subject)", 2)
  end

  -- Validate LoRAs
  local loras = nil
  if opts.lora then
    loras = {}
    for i, lora in ipairs(opts.lora) do
      validate_lora(lora, i)
      loras[i] = {
        name   = lora.name,
        weight = lora.weight or 1.0,
      }
    end
  end

  -- Validate IPAdapter
  local ipadapter = nil
  if opts.ipadapter then
    validate_ipadapter(opts.ipadapter)
    ipadapter = {
      image  = opts.ipadapter.image,
      weight = opts.ipadapter.weight or 1.0,
    }
  end

  local self = setmetatable({}, Cast)
  self.subject   = to_subject(opts.subject)
  self.negative  = to_trait(opts.negative)
  self.lora      = loras
  self.ipadapter = ipadapter
  return self
end

--- Derive a new Cast with field overrides.
-- @param overrides table fields to replace
-- @return Cast
function Cast:with(overrides)
  if type(overrides) ~= "table" then
    error("Cast:with expects a table", 2)
  end
  local function pick(key)
    if overrides[key] ~= nil then return overrides[key] end
    return self[key]
  end
  return Cast.new({
    subject   = pick("subject"),
    negative  = pick("negative"),
    lora      = pick("lora"),
    ipadapter = pick("ipadapter"),
  })
end

return Cast
