--- World: generative foundation entity.
-- Maps to: CheckpointLoaderSimple, VAELoader, CLIPSetLastLayer

local Entity = require("vdsl.entity")

local World = Entity.define("world")

local DEFAULTS = {
  clip_skip = 1,
}

--- Create a World entity.
-- @param opts table { model (required), vae, clip_skip }
-- @return World
function World.new(opts)
  if type(opts) ~= "table" then
    error("World: expected a table, got " .. type(opts), 2)
  end
  if not opts.model or opts.model == "" then
    error("World: 'model' is required", 2)
  end

  local self = setmetatable({}, World)
  self.model     = opts.model
  self.vae       = opts.vae
  self.clip_skip = opts.clip_skip or DEFAULTS.clip_skip
  return self
end

return World
