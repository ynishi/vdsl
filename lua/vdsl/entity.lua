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
-- @param mode string|nil "natural" to prefer desc over tags, nil for default
-- @return string
function M.resolve_text(value, mode)
  if value == nil then return "" end
  if type(value) == "string" then return value end
  if type(value) == "table" and type(value.resolve) == "function" then
    return value:resolve(mode)
  end
  return tostring(value)
end

-- ============================================================
-- Lifecycle (CoreEntity foundation, Phase 0)
-- Adds the domain-entity lifecycle the bare type system lacked:
-- serialize / deserialize / clone / with / equals.
-- Two derivation families share one lifecycle implementation:
--   Core (value/aggregate) — __index = method dispatch, lifecycle as :methods
--   Collection             — __index = member lookup,  lifecycle as Collection.* statics
-- ============================================================

--- Deep copy preserving entity metatables (so clones keep their type).
local function deep_clone(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, val in pairs(v) do out[k] = deep_clone(val) end
  return setmetatable(out, getmetatable(v))
end

--- Deep value equality. Same type tag + same fields (recursively).
local function deep_eq(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  if M.type_of(a) ~= M.type_of(b) then return false end
  for k, v in pairs(a) do
    if not deep_eq(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

--- Project to a plain table, tagging entity-typed tables with _type.
local function serialize_value(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, val in pairs(v) do out[k] = serialize_value(val) end
  local tn = M.type_of(v)
  if tn then out._type = tn end
  return out
end

--- Rebuild from a plain table, restoring metatables from _type tags.
local function deserialize_value(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, val in pairs(v) do
    if k ~= "_type" then out[k] = deserialize_value(val) end
  end
  local tn = v._type
  if tn and REGISTRY[tn] then setmetatable(out, REGISTRY[tn]) end
  return out
end

-- shared lifecycle ops (used by both Core methods and Col statics)
local function lc_clone(self)        return deep_clone(self) end
local function lc_equals(self, o)    return deep_eq(self, o) end
local function lc_serialize(self)    return serialize_value(self) end
local function lc_with(self, overrides)
  if type(overrides) ~= "table" then
    error("with: expected an overrides table", 2)
  end
  local c = deep_clone(self)
  for k, val in pairs(overrides) do c[k] = val end
  return c
end

--- Reconstruct an entity of `name` from a plain (serialized) table.
-- @param name string registered type name
-- @param t table serialized form (from :serialize())
-- @return table entity instance
function M.deserialize(name, t)
  local cls = REGISTRY[name]
  if not cls then
    error("deserialize: unknown type '" .. tostring(name) .. "'", 2)
  end
  if type(t) ~= "table" then
    error("deserialize: expected a table for '" .. name .. "'", 2)
  end
  local out = deserialize_value(t)
  return setmetatable(out, cls)
end

--- Define a Core entity type (value/aggregate).
-- Like define(), plus the lifecycle methods :clone/:with/:equals/:serialize.
-- @param name string unique type name
-- @return table entity class (use as metatable)
function M.define_core(name)
  local cls = M.define(name)
  cls.clone     = lc_clone
  cls.equals    = lc_equals
  cls.serialize = lc_serialize
  cls.with      = lc_with
  return cls
end

--- Collection family: lifecycle exposed as statics so __index stays free
--- for member lookup (e.g. catalog.portrait). Use with define_collection.
M.Collection = {
  clone     = lc_clone,
  equals    = lc_equals,
  serialize = lc_serialize,
  with      = lc_with,
}

--- Define a Collection type.
-- Instances are plain member tables tagged with the type; missing-key access
-- returns nil (no method dispatch on __index). Lifecycle via Entity.Collection.*.
-- @param name string unique type name
-- @return table instance metatable (use as metatable on the member table)
function M.define_collection(name)
  local meta = { __type = name }   -- type tag only; no __index method dispatch
  REGISTRY[name] = meta
  return meta
end

return M
