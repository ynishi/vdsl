--- Catalog: named dictionary of Traits.
-- Thin wrapper with validation and key-miss guard.
-- Provides reusable, hint-bearing Trait sets.
--
-- Design note: Catalog is intentionally NOT an Entity (no Entity.define).
-- It is a validation pass that returns the input table with a guard metatable.
-- Missing-key access returns nil (safe for conditional checks).
-- Entity.is(catalog, "catalog") is false.
--
-- Usage:
--   local catalog = vdsl.catalog {
--     portrait = vdsl.trait("portrait, face closeup"):hint("face", { fidelity = 0.7 }),
--     anime_hq = vdsl.trait("anime style"):hint("hires", { scale = 1.5 }),
--   }
--   local cat = vdsl.subject("warrior"):with(catalog.portrait)
--
-- Extension:
--   vdsl.catalog.extend(C.effect, {
--     sakura = vdsl.trait("cherry blossom petals", 1.1),
--   })

local Entity = require("vdsl.entity")

local M = {}

--- Create a Catalog from a name→Trait table.
-- Validates that every value is a Trait entity.
-- Missing-key access returns nil (safe for conditional checks).
-- @param entries table { name = Trait, ... }
-- @return table the same table with guard metatable
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
  return setmetatable(entries, {})
end

--- Extend an existing catalog with additional entries (in-place).
-- Validates that additions are Traits. Warns on key collision via io.stderr.
-- @param catalog table existing catalog (plain table from Catalog.new)
-- @param additions table { name = Trait, ... }
-- @return table the same catalog table (for chaining)
function M.extend(catalog, additions)
  if type(catalog) ~= "table" then
    error("Catalog.extend: first argument must be a catalog table", 2)
  end
  if type(additions) ~= "table" then
    error("Catalog.extend: second argument must be a table of Traits", 2)
  end
  for name, value in pairs(additions) do
    if type(name) ~= "string" then
      error("Catalog.extend: keys must be strings, got " .. type(name), 2)
    end
    if not Entity.is(value, "trait") then
      error("Catalog.extend: '" .. name .. "' must be a Trait (got "
        .. (Entity.type_of(value) or type(value)) .. ")", 2)
    end
    if rawget(catalog, name) ~= nil then
      io.stderr:write(string.format(
        "Catalog.extend: overwriting existing key '%s'\n", name))
    end
    rawset(catalog, name, value)
  end
  return catalog
end

return M
