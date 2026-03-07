--- Session: ComfyUI connection & Registry cache.
-- Encapsulates environment config and Registry caching.
--
-- Usage (from .env file):
--   local Session = require("vdsl.session")
--   local s = Session.from_env()
--   local result = s:run({ world = ..., cast = {...} })
--
-- Usage (explicit config):
--   local s = Session.new({ token = "mytoken", url = "http://localhost:8188" })
--   local result = s:run({ world = ..., cast = {...} })
--
-- Resource discovery (url= set):
--   s:checkpoints()                     -- server checkpoint list
--   s:loras()                           -- LoRA list
--   s:lora("detail", 0.8)              -- fuzzy-match LoRA
--   s:controlnets()                     -- ControlNet model list
--   s:controlnet("canny", image, opts)  -- build ControlNet entry
--   s:vaes()                            -- VAE list
--   s:upscalers()                       -- upscaler list

local fs = require("vdsl.runtime.fs")

local Session = {}
Session.__index = Session

-- ============================================================
-- Environment file helpers
-- ============================================================

--- Load key=value file (trim, skip comments/empty lines).
-- @param path string file path
-- @param required boolean if true, error when file not found
-- @return table key-value pairs
local function load_kv(path, required)
  local content = fs.read(path)
  if not content then
    if required then error("No " .. path .. " found", 3) end
    return {}
  end
  local kv = {}
  for line in content:gmatch("[^\n]+") do
    line = line:match("^%s*(.-)%s*$")
    if line ~= "" and not line:match("^#") then
      local k, v = line:match("^([%w_]+)=(.+)$")
      if k then kv[k] = v end
    end
  end
  return kv
end

-- ============================================================
-- Constructors
-- ============================================================

--- Create a new Session with explicit config.
-- @param opts table { token, url }
-- @return Session
function Session.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Session)
  self.env = {
    token = opts.token,
    url   = opts.url,
  }
  self._registry = nil
  return self
end

--- Create a Session from .env file.
-- @param env_path string|nil path to .env file (default ".env")
-- @return Session
function Session.from_env(env_path)
  env_path = env_path or ".env"

  local env = load_kv(env_path, true)
  if not env.token then
    error(env_path .. ": token= is required", 2)
  end

  local self = setmetatable({}, Session)
  self.env       = env
  self._registry = nil
  return self
end

-- ============================================================
-- URL resolution & Registry
-- ============================================================

--- Resolve the ComfyUI URL.
-- @return string|nil url
function Session:url()
  return self.env.url
end

--- Get or create the cached Registry.
-- Connects once on first call, reuses for all subsequent operations.
-- @return Registry
function Session:registry()
  if not self._registry then
    local vdsl = require("vdsl")
    local url = self:url()
    if not url then
      error("No ComfyUI URL available. Call :setup() or set url= in config", 2)
    end
    self._registry = vdsl.connect(url, { token = self.env.token })
  end
  return self._registry
end

-- ============================================================
-- Resource discovery (delegates to Registry)
-- ============================================================

--- List available checkpoint files on the ComfyUI server.
-- @return table array of checkpoint filenames
function Session:checkpoints() return self:registry().checkpoints end

--- List available VAE files on the ComfyUI server.
-- @return table array of VAE filenames
function Session:vaes() return self:registry().vaes end

--- List available upscaler models on the ComfyUI server.
-- @return table array of upscaler filenames
function Session:upscalers() return self:registry().upscalers end

--- List available LoRA files on the ComfyUI server.
-- @return table array of LoRA filenames
function Session:loras() return self:registry().loras end

--- List available ControlNet models on the ComfyUI server.
-- @return table array of ControlNet filenames
function Session:controlnets() return self:registry().controlnets end

--- Fuzzy-match a LoRA name against the server inventory.
-- @param query string partial name to match
-- @param weight number|Weight|nil weight (default 1.0)
-- @return table { name, weight }
function Session:lora(query, weight)
  return self:registry():lora(query, weight)
end

--- Build a Stage-ready ControlNet entry with fuzzy-match and auto-upload.
-- @param query string partial model name to match (e.g. "canny", "union")
-- @param image string local filepath or server-side filename
-- @param opts table|nil { strength, preprocessor, start_percent, end_percent }
-- @return table Stage.controlnet entry
function Session:controlnet(query, image, opts)
  opts = opts or {}
  local reg = self:registry()
  local model_name = reg:controlnet(query)
  local server_image = reg:resolve_image(image)
  return {
    type          = model_name,
    image         = server_image,
    strength      = opts.strength or 1.0,
    preprocessor  = opts.preprocessor,
    start_percent = opts.start_percent,
    end_percent   = opts.end_percent,
  }
end

-- ============================================================
-- Run pipeline
-- ============================================================

--- Run the full pipeline: compile -> queue -> poll -> download.
-- Returns result directly. Caller is responsible for error handling.
-- @param opts table vdsl.run options (world, cast, etc.)
-- @return table result { prompt_id, images, files, render }
function Session:run(opts)
  local vdsl = require("vdsl")
  if not opts.url then opts.url = self.env.url end
  if not opts.token then opts.token = self.env.token end
  return vdsl.run(opts, self:registry())
end

return Session
