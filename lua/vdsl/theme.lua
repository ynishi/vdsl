--- Theme: named Catalog with metadata.
-- A collection of Traits organized by name, category, and tags.
-- Themes are discoverable, categorized, and can be imported selectively.
--
-- Usage:
--   local cinema = vdsl.theme {
--     name     = "cinema",
--     category = "photography",
--     tags     = { "film", "lighting", "lens" },
--     traits   = {
--       golden_hour = vdsl.trait("golden hour"):hint("color", { gamma = 0.9 }),
--       noir        = vdsl.trait("film noir"):hint("color", { contrast = 1.3 }),
--     },
--   }
--   -- Access: cinema.traits.golden_hour
--   -- Meta:   cinema.name, cinema.category, cinema.tags

local Entity  = require("vdsl.entity")
local Catalog = require("vdsl.catalog")

local M = Entity.define("theme")

--- Create a Theme from a definition table.
-- @param def table { name (required), category, tags, traits (required) }
-- @return Theme
function M.new(def)
  if type(def) ~= "table" then
    error("Theme: expected a table", 2)
  end
  if type(def.name) ~= "string" or def.name == "" then
    error("Theme: 'name' is required", 2)
  end
  if not def.traits or type(def.traits) ~= "table" then
    error("Theme: 'traits' table is required", 2)
  end

  -- Validate traits via Catalog
  local traits = Catalog.new(def.traits)

  -- Validate negatives (optional: name → Trait dictionary)
  local negatives = nil
  if def.negatives then
    if type(def.negatives) ~= "table" then
      error("Theme: 'negatives' must be a table", 2)
    end
    for name, value in pairs(def.negatives) do
      if type(name) ~= "string" then
        error("Theme: negatives keys must be strings", 2)
      end
      if not Entity.is(value, "trait") then
        error("Theme: negatives['" .. name .. "'] must be a Trait", 2)
      end
    end
    negatives = def.negatives
  end

  -- Validate defaults (optional: render parameter defaults)
  local defaults = nil
  if def.defaults then
    if type(def.defaults) ~= "table" then
      error("Theme: 'defaults' must be a table", 2)
    end
    defaults = def.defaults
  end

  local self = setmetatable({}, M)
  self.name      = def.name
  self.category  = def.category or ""
  self.tags      = def.tags or {}
  self.traits    = traits
  self.negatives = negatives or {}
  self.defaults  = defaults or {}
  return self
end

--- Check if this theme has a specific tag.
-- @param tag string
-- @return boolean
function M:has_tag(tag)
  for _, t in ipairs(self.tags) do
    if t == tag then return true end
  end
  return false
end

--- List all trait names in this theme.
-- @return table list of strings
function M:trait_names()
  local names = {}
  for k in pairs(self.traits) do
    names[#names + 1] = k
  end
  table.sort(names)
  return names
end

return M
