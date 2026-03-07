--- World: generative foundation entity.
-- Encapsulates the execution environment: model + compilation parameters.
-- Maps to: CheckpointLoaderSimple, VAELoader, CLIPSetLastLayer, KSampler config
--
-- Design rationale:
--   World = "the stage equipment" (camera, film, development settings).
--   Cast  = "what is placed on stage" (semantic domain objects).
--   Sampler/steps/cfg/size/post are implementation details that belong here,
--   not in the DSL layer (render opts). Think SQL Execution Plan vs SQL Query.
--
-- Resolution chain (in engine.lua opt()):
--   opts[key] (explicit) > world[key] > config fallback

local Entity = require("vdsl.entity")
local config = require("vdsl.config")

local World = Entity.define("world")

local DEFAULTS = {
  clip_skip = 1,
}

--- Normalize lora option into map + ordered list.
-- Accepts:
--   Dict form:  { style = { name = "file.safetensors", weight = 0.8 }, ... }
--   Array form: { { name = "file.safetensors", weight = 0.8 }, ... }  (backward-compat)
-- @param raw table|nil
-- @return table|nil lora_map  { key = { name, weight } }
-- @return table|nil lora_list { { key, name, weight }, ... } (insertion order)
local function normalize_lora(raw)
  if not raw then return nil, nil end

  -- Detect: if raw[1] exists it's array form
  if raw[1] ~= nil then
    -- Array form → anonymous keys (_1, _2, ...)
    local map, list = {}, {}
    for i, entry in ipairs(raw) do
      if type(entry) ~= "table" or not entry.name or entry.name == "" then
        error("World: lora[" .. i .. "] must be a table with 'name'", 3)
      end
      local key = "_" .. i
      local item = { name = entry.name, weight = entry.weight or 1.0 }
      map[key] = item
      list[#list + 1] = { key = key, name = item.name, weight = item.weight }
    end
    return map, list
  end

  -- Dict form
  local map, list = {}, {}
  -- Deterministic order: sort by key
  local keys = {}
  for k in pairs(raw) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local entry = raw[k]
    if type(entry) ~= "table" or not entry.name or entry.name == "" then
      error("World: lora['" .. k .. "'] must be a table with 'name'", 3)
    end
    local item = { name = entry.name, weight = entry.weight or 1.0 }
    map[k] = item
    list[#list + 1] = { key = k, name = item.name, weight = item.weight }
  end
  return map, list
end

--- Create a World entity.
-- @param opts table {
--   model      (required) string   checkpoint filename
--   vae        (optional) string   VAE filename
--   clip_skip  (optional) number   CLIP skip layers (default 1)
--   sampler    (optional) string   sampler name (e.g. "euler", "dpmpp_2m")
--   steps      (optional) number   sampling steps
--   cfg        (optional) number   classifier-free guidance scale
--   scheduler  (optional) string   scheduler name (e.g. "normal", "karras")
--   size       (optional) table    { width, height }
--   denoise    (optional) number   denoising strength
--   lora       (optional) table    LoRA resource pool:
--              Dict form:  { style = { name = "file.safetensors", weight = 0.8 } }
--              Array form: { { name = "file.safetensors", weight = 0.8 } } (backward-compat)
--   post       (optional) Post     post-processing pipeline
-- }
-- @return World
function World.new(opts)
  if type(opts) ~= "table" then
    error("World: expected a table, got " .. type(opts), 2)
  end

  -- Model resolution: explicit > config > error
  local model = opts.model
  if not model or model == "" then
    model = config.get("model")
  end
  if not model or model == "" then
    error("World: 'model' is required (set in opts, workspaces/config.lua, .vdsl/config.lua, or VDSL_MODEL env)", 2)
  end

  local self = setmetatable({}, World)
  -- Core (model identity)
  self.model     = model
  self.vae       = opts.vae or config.get("vae")
  self.clip_skip = opts.clip_skip or config.get("clip_skip") or DEFAULTS.clip_skip
  -- Compiler parameters (execution plan)
  self.sampler   = opts.sampler
  self.steps     = opts.steps
  self.cfg       = opts.cfg
  self.scheduler = opts.scheduler
  self.size      = opts.size
  self.denoise   = opts.denoise
  self.post      = opts.post
  -- LoRA resource pool
  local lora_map, lora_list = normalize_lora(opts.lora)
  self._lora_map  = lora_map   -- { key = { name, weight } }
  self._lora_list = lora_list  -- { { key, name, weight }, ... }
  -- Backward-compat: engine.lua reads world.lora as array
  self.lora = lora_list and {} or nil
  if lora_list then
    for i, entry in ipairs(lora_list) do
      self.lora[i] = { name = entry.name, weight = entry.weight }
    end
  end
  return self
end

--- Resolve a LoRA key to { name, weight }.
-- Supports fuzzy match: exact key first, then substring match.
-- @param key string LoRA key (e.g. "style", "torn")
-- @return table|nil { name, weight }
function World:resolve_lora(key)
  if not self._lora_map then return nil end
  -- Exact match
  if self._lora_map[key] then
    return self._lora_map[key]
  end
  -- Fuzzy: substring match on key
  local match = nil
  for k, v in pairs(self._lora_map) do
    if k:find(key, 1, true) then
      if match then return nil end  -- ambiguous: multiple matches
      match = v
    end
  end
  if match then return match end
  -- Fuzzy: substring match on filename
  for _, v in pairs(self._lora_map) do
    if v.name:find(key, 1, true) then
      if match then return nil end
      match = v
    end
  end
  return match
end

return World
