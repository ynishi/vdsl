--- Entity: base type system for VDSL entities.
-- Provides type registration, runtime type checking, and resolve interface.
-- All VDSL entities (Trait, Subject, World, Cast, Stage) derive from this.

local M = {}

local REGISTRY = {}

--- Define a new entity type.
-- Returns a class table with __index set up for method dispatch.
-- @param name string unique type name
-- @return table entity class (use as metatable)
function M.define(name)
  local cls = setmetatable({}, { __index = M })
  cls.__index = cls
  cls.__type = name
  REGISTRY[name] = cls
  return cls
end

--- Check if an object is a specific entity type.
-- @param obj any
-- @param name string type name
-- @return boolean
function M.is(obj, name)
  if type(obj) ~= "table" then return false end
  local mt = getmetatable(obj)
  return mt ~= nil and mt.__type == name
end

--- Check if an object is any registered entity type.
-- @param obj any
-- @return boolean
function M.is_entity(obj)
  if type(obj) ~= "table" then return false end
  local mt = getmetatable(obj)
  return mt ~= nil and mt.__type ~= nil and REGISTRY[mt.__type] ~= nil
end

--- Get the type name of an entity.
-- @param obj any
-- @return string|nil
function M.type_of(obj)
  if type(obj) ~= "table" then return nil end
  local mt = getmetatable(obj)
  if mt and mt.__type then return mt.__type end
  return nil
end

--- Resolve any value to a prompt string.
-- Handles: nil → "", string → passthrough, entity with :resolve() → call it.
-- @param value any
-- @return string
function M.resolve_text(value)
  if value == nil then return "" end
  if type(value) == "string" then return value end
  if type(value) == "table" and type(value.resolve) == "function" then
    return value:resolve()
  end
  return tostring(value)
end

return M
