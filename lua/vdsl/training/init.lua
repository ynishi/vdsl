--- Training: LoRA training method selection, dataset organization & verification.
--
-- Design:
--   Methods (Impl) — config generators for specific training tools
--   Dataset (Decl) — declarative manifest for dataset directory organization
--   Verify  (Impl) — Pipeline-based LoRA quality verification
--
-- Usage:
--   local training = require("vdsl.training")
--
--   -- Method config generation
--   local toml = training.method("kohya").config {
--     checkpoint = "/workspace/models/base_model.safetensors",
--     data_dir   = "/workspace/datasets/abc01",
--     rank = 8, steps = 300,
--   }
--
--   -- Dataset manifest (declarative — emit JSON, backend executes)
--   local ds = training.dataset {
--     name       = "puni_slider",
--     layout     = "sliders",
--     source_dir = "puni_slider_pairs",
--     pairs      = pairs_def,
--   }
--   ds:emit()           -- register manifest; runner applies after download
--
--   -- Post-training verification (returns a Pipeline)
--   local pipe = training.verify {
--     name    = "verify_abc01",
--     lora    = "my_lora.safetensors",
--     world   = vdsl.world { model = "base_model.safetensors" },
--     weights = { 0.3, 0.5, 0.7, 1.0 },
--   }
--   pipe:compile(test_variations)

local M = {}

-- ============================================================
-- Method dispatch
-- ============================================================

local METHODS = {
  kohya    = "vdsl.training.methods.kohya",
  sliders  = "vdsl.training.methods.sliders",
  leco     = "vdsl.training.methods.leco",
  lycoriss = "vdsl.training.methods.lycoriss",
  ti       = "vdsl.training.methods.ti",
}

--- Get a training method implementation.
-- @param name string method name ("kohya", "sliders", ...)
-- @return table method module
function M.method(name)
  local mod_path = METHODS[name]
  if not mod_path then
    error("training.method: unknown method '" .. tostring(name)
      .. "' (available: " .. table.concat(M.available_methods(), ", ") .. ")", 2)
  end
  return require(mod_path)
end

--- List available training methods.
-- @return table array of method name strings
function M.available_methods()
  local names = {}
  for k in pairs(METHODS) do
    names[#names + 1] = k
  end
  table.sort(names)
  return names
end

-- ============================================================
-- Dataset (declarative manifest)
-- ============================================================

M.dataset = setmetatable({}, {
  __index = function(t, k)
    local mod = require("vdsl.training.dataset")
    for mk, mv in pairs(mod) do rawset(t, mk, mv) end
    return t[k]
  end,
  __call = function(t, ...)
    local mod = require("vdsl.training.dataset")
    rawset(t, "new", mod.new)
    return mod.new(...)
  end,
})

-- ============================================================
-- Env (declarative environment specification)
-- ============================================================

M.env = setmetatable({}, {
  __index = function(t, k)
    local mod = require("vdsl.training.env")
    for mk, mv in pairs(mod) do rawset(t, mk, mv) end
    return t[k]
  end,
  __call = function(t, ...)
    local mod = require("vdsl.training.env")
    rawset(t, "new", mod.new)
    return mod.new(...)
  end,
})

-- ============================================================
-- Verify (Pipeline-based)
-- ============================================================

M.verify = setmetatable({}, {
  __index = function(t, k)
    local mod = require("vdsl.training.verify")
    for mk, mv in pairs(mod) do rawset(t, mk, mv) end
    return t[k]
  end,
  __call = function(t, ...)
    local mod = require("vdsl.training.verify")
    rawset(t, "new", mod.new)
    return mod.new(...)
  end,
})

return M
