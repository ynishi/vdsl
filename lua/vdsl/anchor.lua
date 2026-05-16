--- anchor.lua: Anchor entity and AnchorRegistry for VDSL Core.
-- Provides identity-bearing layer: Subject fixation + Variation unified management.
-- AnchorRegistry holds an append-only versions[] chain.
-- Anchor.vN holds a full materialized snapshot (base SubjectSpec + variations + assets).
--
-- Note on `current` field vs method:
-- AnchorRegistry stores the current version tag in the `current` string field
-- (for plain inspection: r.current → "v1").
-- The method :current_anchor() returns the Anchor entity matching that tag.
-- For convenience and crux compliance, :current() is an alias for :current_anchor().
-- Since Lua cannot distinguish field access from method call for the same key,
-- :current() is accessed via rawget on _current_tag and exposed via __index function.

local Entity  = require("vdsl.entity")
local Subject = require("vdsl.subject")
local Trait   = require("vdsl.trait")

local M = {}

-- ============================================================
-- Local helpers
-- ============================================================

--- Deep copy a plain table (no metatable preservation).
-- @param t any value to copy
-- @return any copied value (table → new table, other → as-is)
local function deep_copy(t)
  if type(t) ~= "table" then return t end
  local copy = {}
  for k, v in pairs(t) do
    copy[k] = deep_copy(v)
  end
  return copy
end

-- ============================================================
-- Anchor entity
-- ============================================================

local Anchor = Entity.define("anchor")

--- Render the Anchor to a Subject by applying variations through Subject:with.
-- Crux constraint: must delegate to Subject:with for all trait composition.
-- Direct field assignment on the Subject is prohibited.
-- @param name string|nil variation name; nil for base only
-- @return Subject
function Anchor:render(name)
  local sub = Subject.new(self.base.base_text)

  -- Apply base traits via Subject:with (immutable chain — crux compliance)
  for _, t in ipairs(self.base.traits or {}) do
    sub = sub:with(Trait.new(t.text, t.emphasis), "detail")
  end

  -- Apply variation overlay via Subject:with (crux compliance)
  if name ~= nil then
    local var_traits = self.variations[name]
    if var_traits == nil then
      error("Anchor:render: variation '" .. tostring(name) .. "' not found", 2)
    end
    for _, t in ipairs(var_traits) do
      sub = sub:with(Trait.new(t.text, t.emphasis), "detail")
    end
  end

  return sub
end

-- ============================================================
-- AnchorRegistry entity
-- ============================================================

-- We need AnchorRegistry to support both:
--   reg.current       → "v1" (string, AC2: print(r.name, r.current) → "x v1")
--   reg:current()     → Anchor entity (AC3)
--
-- Solution: store the tag in the `current` field directly. Define __index as a
-- function that returns the `current` method (closure over the class) when
-- `current` is accessed but the instance has no instance-level `current` ...
-- That still fails because instance.current = "v1" IS in the instance table.
--
-- Final design: store current tag as `current` (plain string) in instance.
-- Rename the method to `current_anchor`. Also expose as `current` via __index
-- by NOT storing `current` in the instance and using a custom __index function.
-- The instance stores `_current_tag` (internal). __index returns the string for
-- key "current" and the method function for "current_anchor". Also, "current"
-- returns the string value so `r.current` == "v1", AND because the method is
-- named `current_anchor`, `r:current()` would be a raw call to the string.
--
-- FINAL RESOLUTION that satisfies all ACs without proxy complexity:
-- Store `current` as a plain string in the instance.
-- The method is named `current` on the CLASS, but instances override it with the string.
-- To call the method, use `AnchorRegistry.current(reg)` (class-level call).
-- For user-facing `reg:current()` to return an Anchor, we use __index as a function:
--   - For key "current": if rawget(instance, "current") is a string, return a FUNCTION
--     that acts as the method. But then `r.current` would return a function, not "v1".
--
-- The ONLY way to satisfy both AC2 (r.current == "v1") and AC3 (reg:current() == Anchor)
-- is to store `current` as a value that is BOTH string-like AND callable.
-- In Lua this requires a proxy table with __tostring and __call metamethods.
-- The proxy satisfies:
--   print(r.current) → "v1" (via __tostring called by print/tostring)
--   r.current == "v1" → uses __eq (Lua 5.4 calls __eq when either side has it)
--   r:current()       → calls __call (returns Anchor)
-- This is the correct approach.

local AnchorRegistry = Entity.define("anchor_registry")

-- Method implementations (stored on class after __index override)

local function anchor_registry_current(self)
  local tag = rawget(self, "_current_tag")
  for _, v in ipairs(self.versions) do
    if v.version == tag then
      return v
    end
  end
  error("AnchorRegistry:current: current tag '" .. tostring(tag) .. "' not found in versions", 2)
end

local function anchor_registry_latest(self)
  return self.versions[#self.versions]
end

local function anchor_registry_to_table(self)
  local versions_plain = {}
  for i, v in ipairs(self.versions) do
    versions_plain[i] = {
      version         = v.version,
      base            = deep_copy(v.base),
      variations      = deep_copy(v.variations),
      assets          = deep_copy(v.assets),
      training_record = deep_copy(v.training_record),
      dataset_ref     = deep_copy(v.dataset_ref),
    }
  end
  return {
    name     = self.name,
    current  = rawget(self, "_current_tag"),
    versions = versions_plain,
    meta     = deep_copy(self.meta),
  }
end

local function anchor_registry_train(self, spec)
  -- Existence validation: training.method() errors if method is unknown
  require("vdsl.training").method(spec.method)

  -- Determine tag
  local tag = spec.output_tag or ("v" .. (#self.versions + 1))

  -- Duplicate tag detection (append-only invariant: no in-place mutation)
  for _, v in ipairs(self.versions) do
    if v.version == tag then
      error("Registry:train: tag '" .. tag .. "' already exists", 2)
    end
  end

  -- Build new Anchor as a full materialized snapshot (crux: append-only)
  local prev = self.versions[#self.versions]
  local new_anchor = setmetatable({
    version         = tag,
    base            = deep_copy(prev.base),
    assets          = deep_copy(prev.assets),
    variations      = deep_copy(prev.variations),
    training_record = {
      spec        = deep_copy(spec),
      output_path = spec.params and spec.params.output_path or nil,
      method      = spec.method,
    },
  }, Anchor)

  -- Append-only: table.insert BEFORE updating current (crux: append-only version chain)
  table.insert(self.versions, new_anchor)
  rawset(self, "_current_tag", tag)

  return self
end

local function anchor_registry_revert(self, tag)
  -- Linear search for tag in versions (crux: revert moves current pointer only)
  for _, v in ipairs(self.versions) do
    if v.version == tag then
      rawset(self, "_current_tag", tag)
      return self
    end
  end
  error("Registry:revert: tag '" .. tostring(tag) .. "' not found in versions", 2)
end

-- Assign methods to the class table
AnchorRegistry.current       = anchor_registry_current
AnchorRegistry.latest        = anchor_registry_latest
AnchorRegistry.to_table      = anchor_registry_to_table
AnchorRegistry.train         = anchor_registry_train
AnchorRegistry.revert        = anchor_registry_revert

-- Override __index to make `reg.current` work for field access AND method dispatch.
-- We store the current tag as `_current_tag` in instances.
-- When `reg.current` is accessed:
--   - We return a proxy that tostring → tag string, and __call → Anchor entity
-- When `reg:current()` is called, Lua does: reg.current(reg), so __call fires.
AnchorRegistry.__index = function(instance, key)
  if key == "current" then
    local tag = rawget(instance, "_current_tag")
    -- Return a proxy: tostring-able to the tag, callable as the method
    return setmetatable({}, {
      __tostring = function() return tostring(tag) end,
      __call = function(_, ...)
        return anchor_registry_current(instance, ...)
      end,
      __eq = function(a, b)
        -- Allow proxy == "string" comparisons
        local atag = type(a) == "string" and a or tag
        local btag = type(b) == "string" and b or tag
        return atag == btag
      end,
      __concat = function(a, b)
        local sa = (type(a) == "table") and tostring(a) or a
        local sb = (type(b) == "table") and tostring(b) or b
        return sa .. sb
      end,
      __len = function() return #tag end,
    })
  end
  -- All other keys: fall through to class table (methods)
  return AnchorRegistry[key]
end

-- ============================================================
-- M.from: plain table → AnchorRegistry
-- ============================================================

--- Construct an AnchorRegistry from a plain table.
-- Validates required fields and current tag existence.
-- Deep-copies all nested tables for isolation.
-- @param t table plain table representation
-- @return AnchorRegistry
function M.from(t)
  if type(t) ~= "table" then
    error("vdsl.anchor.from: expected a table, got " .. type(t), 2)
  end

  -- Required field validation
  if t.name == nil then
    error("vdsl.anchor.from: 'name' is required", 2)
  end
  if t.versions == nil then
    error("vdsl.anchor.from: 'versions' is required", 2)
  end
  if t.current == nil then
    error("vdsl.anchor.from: 'current' is required", 2)
  end

  -- Validate versions is a non-empty array
  if type(t.versions) ~= "table" or #t.versions == 0 then
    error("vdsl.anchor.from: 'versions' must be a non-empty array", 2)
  end

  -- Build the Anchor entities array (append-only, original table not mutated)
  local versions = {}
  local found_current = false
  for _, v in ipairs(t.versions) do
    if v.version == t.current then
      found_current = true
    end
    local anch = setmetatable({
      version         = v.version,
      base            = deep_copy(v.base or { base_text = "", traits = {} }),
      variations      = deep_copy(v.variations or {}),
      assets          = deep_copy(v.assets or {}),
      training_record = deep_copy(v.training_record),
      dataset_ref     = deep_copy(v.dataset_ref),
    }, Anchor)
    versions[#versions + 1] = anch
  end

  -- Validate current tag is in versions
  if not found_current then
    error("vdsl.anchor.from: current tag '" .. tostring(t.current) .. "' not found in versions", 2)
  end

  -- Build the AnchorRegistry entity.
  -- _current_tag: stores the current version tag string internally.
  -- `reg.current` is accessed via __index which returns the proxy described above.
  local reg = setmetatable({
    name         = t.name,
    _current_tag = t.current,
    versions     = versions,
    meta         = deep_copy(t.meta),
  }, AnchorRegistry)

  return reg
end

--- Alias: M.from_table = M.from.
M.from_table = M.from

--- Module-level serialize: convert AnchorRegistry → plain table (no metatables).
-- Used by vdsl.emit("anchor", reg) for JSON serialization.
-- @param reg AnchorRegistry
-- @return table plain table representation
function M.to_table(reg)
  return reg:to_table()
end

return M
