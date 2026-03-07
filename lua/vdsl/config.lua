--- Config: layered configuration loader.
-- Load order (later wins):
--   1. .vdsl/config.lua   (project-level defaults)
--   2. workspaces/config.lua (user-level overrides)
--   3. Environment variables (VDSL_MODEL, etc.)
--
-- Available keys:
--   model         = "my_model.safetensors"   -- World default checkpoint
--   vae           = "my_vae.safetensors"      -- VAE (env: VDSL_VAE)
--   clip_skip     = 2                         -- CLIP skip layers (env: VDSL_CLIP_SKIP)
--   upscale_model = "4x-UltraSharp.pth"       -- Upscale model
--   face_model    = "codeformer-v0.1.0.pth"   -- Face restore model
--   detectors     = { face = "...", hand = "...", person = "..." }
--   preprocessors = { depth = { ckpt_name = "..." } }
--
-- Example (.vdsl/config.lua):
--   return { model = "my_model.safetensors", clip_skip = 2 }

local fs = require("vdsl.runtime.fs")

local M = {}

local _cache = nil

local CONFIG_PATHS = {
  ".vdsl/config.lua",
  "workspaces/config.lua",
}

local ENV_MAP = {
  model     = "VDSL_MODEL",
  vae       = "VDSL_VAE",
  clip_skip = "VDSL_CLIP_SKIP",
}

--- Load and merge a config file into target table.
local function merge_file(target, path)
  if not fs.exists(path) then return end
  local loader = loadfile(path)
  if not loader then return end
  local ok, cfg = pcall(loader)
  if not ok or type(cfg) ~= "table" then return end
  for k, v in pairs(cfg) do
    target[k] = v
  end
end

--- Load environment variable overrides.
local function merge_env(target)
  for key, env_name in pairs(ENV_MAP) do
    local val = os.getenv(env_name)
    if val and val ~= "" then
      if key == "clip_skip" then
        target[key] = tonumber(val) or target[key]
      else
        target[key] = val
      end
    end
  end
end

--- Load config (cached after first call).
-- @return table merged config
function M.load()
  if _cache then return _cache end
  _cache = {}
  for _, path in ipairs(CONFIG_PATHS) do
    merge_file(_cache, path)
  end
  merge_env(_cache)
  return _cache
end

--- Force reload config (clear cache).
-- @return table fresh merged config
function M.reload()
  _cache = nil
  return M.load()
end

--- Get a single config value.
-- @param key string
-- @return any|nil
function M.get(key)
  return M.load()[key]
end

--- Override cache with a fixed table (for test isolation).
-- Pass nil to resume normal file-based loading on next access.
-- @param t table|nil
function M._override(t)
  _cache = t
end

return M
