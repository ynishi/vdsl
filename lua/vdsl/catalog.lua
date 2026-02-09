--- Catalog: named dictionary of Traits.
-- Thin wrapper with validation. Provides reusable, hint-bearing Trait sets.
--
-- Design note: Catalog is intentionally NOT an Entity (no Entity.define).
-- It is a validation pass that returns the input table as-is, so that
-- entries are directly accessible (catalog.portrait) without indirection.
-- Theme wraps Catalog in self.traits. Entity.is(catalog, "catalog") is false.
--
-- Usage:
--   local catalog = vdsl.catalog {
--     portrait = vdsl.trait("portrait, face closeup"):hint("face", { fidelity = 0.7 }),
--     anime_hq = vdsl.trait("anime style"):hint("hires", { scale = 1.5 }),
--   }
--   local cat = vdsl.subject("warrior"):with(catalog.portrait)

local Entity = require("vdsl.entity")

local M = {}

--- Create a Catalog from a name→Trait table.
-- Validates that every value is a Trait entity.
-- @param entries table { name = Trait, ... }
-- @return table the same table (passthrough after validation)
function M.new(entries)
  if type(entries) ~= "table" then
    error("Catalog: expected a table of named Traits", 2)
  end
  for name, value in pairs(entries) do
    if type(name) ~= "string" then
      error("Catalog: keys must be strings, got " .. type(name), 2)
    end
    if not Entity.is(value, "trait") then
      error("Catalog: '" .. name .. "' must be a Trait (got "
        .. (Entity.type_of(value) or type(value)) .. ")", 2)
    end
  end
  return entries
end

return M
