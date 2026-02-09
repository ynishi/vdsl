--- Stage: spatial composition entity.
-- Maps to: ControlNetLoader, ControlNetApply, LoadImage, VAEEncode

local Entity = require("vdsl.entity")

local Stage = Entity.define("stage")

--- Validate a single ControlNet entry.
local function validate_controlnet(cn, index)
  if type(cn) ~= "table" then
    error("Stage: controlnet[" .. index .. "] must be a table", 3)
  end
  if not cn.type or cn.type == "" then
    error("Stage: controlnet[" .. index .. "].type is required", 3)
  end
  if not cn.image or cn.image == "" then
    error("Stage: controlnet[" .. index .. "].image is required", 3)
  end
end

--- Create a Stage entity.
-- @param opts table { controlnet, mask, latent_image }
-- @return Stage
function Stage.new(opts)
  if type(opts) ~= "table" then
    error("Stage: expected a table, got " .. type(opts), 2)
  end

  local controlnets = nil
  if opts.controlnet then
    controlnets = {}
    for i, cn in ipairs(opts.controlnet) do
      validate_controlnet(cn, i)
      controlnets[i] = {
        type     = cn.type,
        image    = cn.image,
        strength = cn.strength or 1.0,
      }
    end
  end

  local self = setmetatable({}, Stage)
  self.controlnet   = controlnets
  self.mask         = opts.mask
  self.latent_image = opts.latent_image
  return self
end

return Stage
