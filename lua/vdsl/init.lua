--- vdsl V2: Visual DSL for ComfyUI
-- Public API facade. Core entities + execution layer.
--
-- Usage:
--   local vdsl = require("vdsl")
--   local walking = vdsl.trait("walking pose, full body")
--   local cat = vdsl.subject("cat"):with(walking):quality("high"):style("anime")
--   local ugly = vdsl.trait("blurry, ugly")
--   local w = vdsl.world { model = "sd_xl_base_1.0",
--                          lora = { style = { name = "detail.safetensors", weight = 0.8 } } }
--   local c = vdsl.cast { subject = cat:hint("lora", "style"), negative = ugly }
--   local r = vdsl.render { world = w, cast = { c } }
--   print(r.json)

local Entity     = require("vdsl.entity")
local Trait      = require("vdsl.trait")
local Subject    = require("vdsl.subject")
local Weight     = require("vdsl.weight")
local World      = require("vdsl.world")
local Cast       = require("vdsl.cast")
local Stage      = require("vdsl.stage")
local Post       = require("vdsl.post")
local Catalog    = require("vdsl.catalog")
local compiler   = require("vdsl.compiler")
local decode_mod = require("vdsl.compilers.comfyui.decoder")
local png_mod    = require("vdsl.runtime.png")
local serializer = require("vdsl.runtime.serializer")
local json_mod   = require("vdsl.util.json")
local fs         = require("vdsl.runtime.fs")
local emit_mod   = require("vdsl.runtime.emit")
local config_mod = require("vdsl.config")
local M = {}

M._VERSION = "0.1.0"

-- ============================================================
-- Core Entity constructors
-- ============================================================

function M.trait(text, emphasis)
  return Trait.new(text, emphasis)
end

function M.subject(base_text)
  return Subject.new(base_text)
end

function M.world(opts)
  return World.new(opts)
end

function M.cast(opts)
  return Cast.new(opts)
end

function M.stage(opts)
  return Stage.new(opts)
end

--- Create a Post operation (chainable with +).
-- @param op_type string operation type ("hires", "upscale", etc.)
-- @param params table|nil operation parameters
-- @return Post
function M.post(op_type, params)
  return Post.new(op_type, params)
end

--- Create a Catalog (named Trait dictionary).
-- @param entries table { name = Trait, ... }
-- @return table validated catalog
function M.catalog(entries)
  return Catalog.new(entries)
end


-- vdsl.lora() removed.
-- LoRA is a World resource, not a DSL entity constructor.
-- Use:  hint("lora", "key")  on Traits (Compiler resolves via World)
-- Or:   cast.lora = { { name = "file.safetensors", weight = 1.0 } }  (direct)

--- Layered config (project + user + env).
-- vdsl.config.get("model") → resolved model name
-- vdsl.config.load()        → full merged config table
-- vdsl.config.reload()      → force re-read
M.config = config_mod

--- Semantic weight values.
M.weight = Weight

--- Tag key constants (from Trait module).
-- Usage: vdsl.trait("blue eyes"):tag(vdsl.K.TIER, "S")
M.K = Trait

--- Atmosphere: emotional tone Traits (callable + presets from catalog).
-- Returns plain Traits — composable with lighting, effect, camera via +.
-- vdsl.atmosphere("custom mood")  → Trait
-- vdsl.atmosphere.serene          → Trait (from catalogs.atmosphere)
-- vdsl.atmosphere.serene + C.lighting.rembrandt → works naturally
M.atmosphere = setmetatable({}, {
  __call = function(_, mood, emphasis)
    return Trait.new(mood, emphasis)
  end,
  __index = function(t, name)
    local cat = M.catalogs.atmosphere
    if cat then
      local trait = cat[name]
      if trait then
        rawset(t, name, trait)
        return trait
      end
    end
    return nil
  end,
})

-- ============================================================
-- Built-in catalogs (lazy-loaded) + user overlay
-- ============================================================

-- User catalog directories registered via use_catalogs().
-- Each entry is an absolute or relative directory path.
local _user_catalog_dirs = {}

M.catalogs = setmetatable({}, {
  __index = function(t, name)
    -- 1. Try built-in
    local ok, cat = pcall(require, "vdsl.catalogs." .. name)
    if ok then
      rawset(t, name, cat)
    end
    -- 2. Overlay user catalogs (merge into built-in, or create new)
    for _, dir in ipairs(_user_catalog_dirs) do
      local path = dir .. "/" .. name .. ".lua"
      if fs.exists(path) then
        local loader = loadfile(path)
        if loader then
          local user_ok, user_cat = pcall(loader)
          if user_ok and type(user_cat) == "table" then
            local existing = rawget(t, name)
            if existing and type(existing) == "table" then
              -- Merge into existing (extend)
              Catalog.extend(existing, user_cat)
            else
              -- New catalog from user dir
              local validated = Catalog.new(user_cat)
              rawset(t, name, validated)
            end
          end
        end
      end
    end
    return rawget(t, name)
  end,
})

--- Register a user catalog directory for overlay.
-- Lua files in the directory are loaded and merged with built-in catalogs.
-- e.g., dir/effect.lua → entries merged into C.effect
-- e.g., dir/weapon.lua → new C.weapon catalog created
-- Can be called multiple times; directories are searched in registration order.
-- @param dir string path to directory containing catalog .lua files
function M.use_catalogs(dir)
  if type(dir) ~= "string" then
    error("use_catalogs: expected a directory path string", 2)
  end
  _user_catalog_dirs[#_user_catalog_dirs + 1] = dir
  -- Invalidate cached catalogs so next access triggers re-merge.
  -- Only clear catalogs that have a corresponding file in the new dir.
  for name in pairs(M.catalogs) do
    local path = dir .. "/" .. name .. ".lua"
    if fs.exists(path) then
      rawset(M.catalogs, name, nil)
    end
  end
end

--- List registered user catalog directories.
-- @return table array of directory paths
function M.catalog_dirs()
  local dirs = {}
  for i, d in ipairs(_user_catalog_dirs) do dirs[i] = d end
  return dirs
end

-- ============================================================
-- Type system (exposed for advanced usage)
-- ============================================================

M.entity = Entity

-- ============================================================
-- Preflight (model availability check)
-- ============================================================

--- Lazy-loaded preflight module.
-- vdsl.preflight.extract(prompt) → required models
-- vdsl.preflight.check(required, available) → report
M.preflight = setmetatable({}, {
  __index = function(t, k)
    local mod = require("vdsl.compilers.comfyui.preflight")
    for mk, mv in pairs(mod) do rawset(t, mk, mv) end
    return t[k]
  end,
})

--- Lazy-loaded Repository (Workspace > Run > Generation).
-- vdsl.repo:ensure_workspace("name") → workspace
-- vdsl.repo:create_run(ws_id, script) → run
-- vdsl.repo:save({ run_id, seed, model, output, recipe }) → gen
-- vdsl.repo:find(gen_id) → record
-- vdsl.repo:query({ model, workspace, ... }) → records
M.repo = setmetatable({}, {
  __index = function(t, k)
    -- First access: instantiate real repo and replace proxy
    local Repository = require("vdsl.repository")
    local repo = Repository.new()
    -- Install method forwarders on proxy table
    for mk, mv in pairs(Repository) do
      if type(mv) == "function" and mk ~= "new" then
        rawset(t, mk, function(_, ...) return mv(repo, ...) end)
      end
    end
    rawset(t, "_inner", repo)
    return rawget(t, k)
  end,
})

--- Lazy-loaded Sync engine (3-location file sync).
-- vdsl.sync(opts) → Sync instance (shares DB with repo)
-- vdsl.sync:register(path, type, opts) → sync_state row
-- vdsl.sync:push_file(path, dest, dest_path) → ok, err
-- vdsl.sync:pull_file(src, src_path, dest_path) → ok, err
-- vdsl.sync:pending(loc) → files needing sync
-- vdsl.sync:summary() → counts by state/location
--
-- opts: { pod_id, ssh_key, bucket }
-- Requires repo to be initialized first (shared DB).
do
  local _sync_instance = nil

  --- Create or return the Sync engine.
  -- @param opts table|nil  { pod_id, ssh_key, bucket }
  -- @return Sync
  function M.sync(opts)
    if _sync_instance and not opts then
      return _sync_instance
    end
    local SyncEngine = require("vdsl.runtime.sync")
    -- Share DB with repo (lazy-init repo first)
    local repo_inner = rawget(M.repo, "_inner")
    if not repo_inner then
      -- Trigger repo initialization
      local _ = M.repo.ensure_workspace
      repo_inner = rawget(M.repo, "_inner")
    end
    local db = repo_inner and repo_inner.db
    if not db then
      local DB = require("vdsl.runtime.db")
      db = DB.open()
    end
    _sync_instance = SyncEngine.new(db, opts)
    return _sync_instance
  end

  --- Set a custom sync backend (e.g. Rust/mlua).
  -- @param backend table or nil to reset
  function M.set_sync_backend(backend)
    local SyncEngine = require("vdsl.runtime.sync")
    SyncEngine.set_backend(backend)
  end
end

--- Lazy-loaded training module.
-- vdsl.training.archetype() → define training concept
-- vdsl.training.grid.auto() → dataset diversity
-- vdsl.training.method("kohya") → training config generation
-- vdsl.training.verify.plan() → post-training verification
M.training = setmetatable({}, {
  __index = function(t, k)
    local mod = require("vdsl.training")
    for mk, mv in pairs(mod) do rawset(t, mk, mv) end
    return t[k]
  end,
})

-- ============================================================
-- Execution layer
-- ============================================================

function M.render(opts)
  return compiler.compile(opts)
end

--- Analyze prompt token usage without building a graph.
-- Returns diagnostics: estimated token counts, chunk allocation,
-- budget breakdown by category, warnings, and suggestions.
-- @param opts table render options (same as vdsl.render)
-- @return table diagnostics
function M.check(opts)
  return compiler.check(opts)
end

function M.connect(url, opts)
  local Registry = require("vdsl.runtime.registry")
  return Registry.connect(url, opts)
end

function M.from_object_info(info, url, headers)
  local Registry = require("vdsl.runtime.registry")
  return Registry.from_object_info(info, url, headers)
end

function M.set_matcher(fn)
  local matcher = require("vdsl.util.matcher")
  matcher.set_matcher(fn)
end

--- Set a custom HTTP transport backend.
-- @param backend table { get, post_json, download } or nil to reset
function M.set_transport(backend)
  local transport = require("vdsl.runtime.transport")
  transport.set_backend(backend)
end

--- Full pipeline: compile → queue → poll → download → embed.
-- Convenience wrapper around Registry:run().
-- Render keys and run keys are separated automatically.
-- @param opts table render opts + { url, token, save, save_dir, timeout, interval, embed }
-- @param registry Registry|nil pre-connected Registry (skips connect)
-- @return table { prompt_id, images, files, render }
function M.run(opts, registry)
  local reg = registry
  if not reg then
    local url = opts.url
    if not url then
      error("vdsl.run: url is required (or pass a Registry as 2nd arg)", 2)
    end
    local Registry = require("vdsl.runtime.registry")
    reg = Registry.connect(url, { token = opts.token })
  end

  -- Separate run_opts from render_opts
  local run_keys = { url=true, token=true, save=true, save_dir=true, timeout=true, interval=true, embed=true }
  local render_opts = {}
  local run_opts = {}
  for k, v in pairs(opts) do
    if run_keys[k] then
      run_opts[k] = v
    else
      render_opts[k] = v
    end
  end

  return reg:run(render_opts, run_opts)
end

-- ============================================================
-- Import layer (decode)
-- ============================================================

--- Decode a ComfyUI prompt table into vdsl-compatible info.
-- @param prompt table ComfyUI prompt { node_id = { class_type, inputs } }
-- @return table { world, casts, sampler, stage, post, size, output, global_negatives }
function M.decode(prompt)
  return decode_mod.decode(prompt)
end

--- Read and decode ComfyUI metadata from a PNG file.
-- @param filepath string path to PNG image
-- @return table|nil { prompt, workflow } parsed metadata
-- @return string|nil error message
function M.read_png(filepath)
  return png_mod.read_comfy(filepath)
end

--- Full import: PNG file → decoded vdsl info.
-- If PNG contains a "vdsl" recipe chunk, returns full semantic entities.
-- Otherwise falls back to structural decode from "prompt" chunk.
-- @param filepath string path to PNG image
-- @return table|nil decoded info or render opts (if recipe present)
-- @return string|nil error message
-- @return boolean has_recipe true if vdsl recipe was found
function M.import_png(filepath)
  -- Read all text chunks
  local chunks, err = png_mod.read_text(filepath)
  if not chunks then return nil, err, false end

  -- Prefer vdsl recipe (full semantic round-trip)
  if chunks["vdsl"] then
    local ok, opts = pcall(serializer.deserialize, chunks["vdsl"])
    if ok then
      return opts, nil, true
    end
    -- Fall through to structural decode if recipe is corrupted
  end

  -- Fallback: structural decode from ComfyUI prompt
  if chunks["prompt"] then
    local ok, prompt = pcall(json_mod.decode, chunks["prompt"])
    if ok then
      return decode_mod.decode(prompt), nil, false
    end
  end

  return nil, "import_png: no usable metadata in PNG", false
end

-- ============================================================
-- Embed layer (PNG write)
-- ============================================================

--- Embed vdsl recipe + compiled prompt into a PNG file.
-- Compiles render opts, then injects both "vdsl" (semantic recipe)
-- and "prompt" (ComfyUI workflow) tEXt chunks.
-- @param filepath string path to PNG file (modified in-place)
-- @param render_opts table original render options
-- @return boolean success
-- @return string|nil error message
function M.embed(filepath, render_opts)
  local recipe_json = serializer.serialize(render_opts)
  local result = compiler.compile(render_opts)
  local prompt_json = json_mod.encode(result.prompt)
  return png_mod.inject_text(filepath, { vdsl = recipe_json, prompt = prompt_json })
end

--- Embed vdsl recipe + compiled prompt into a copy of a PNG file (non-destructive).
-- @param src_path string source PNG
-- @param dst_path string destination PNG
-- @param render_opts table original render options
-- @return boolean success
-- @return string|nil error message
function M.embed_to(src_path, dst_path, render_opts)
  local recipe_json = serializer.serialize(render_opts)
  local result = compiler.compile(render_opts)
  local prompt_json = json_mod.encode(result.prompt)
  return png_mod.inject_text_to(src_path, dst_path, { vdsl = recipe_json, prompt = prompt_json })
end

--- Render and embed: compile + serialize recipe for later embedding.
-- Returns render result with recipe field attached.
-- @param opts table render options
-- @return table render result with .recipe (JSON string)
function M.render_with_recipe(opts)
  local result = compiler.compile(opts)
  result.recipe = serializer.serialize(opts)
  return result
end

--- Emit compiled workflow via runtime/emit backend.
-- Delegates to runtime/emit.lua which supports DI via set_backend().
-- Default backend writes to VDSL_OUT_DIR; no-op when unset (standalone mode).
-- @param name string  output filename stem (e.g. "01_gothic_lolita")
-- @param result table  return value from vdsl.render()
-- @param render_opts table|nil  original render opts (for recipe serialization)
-- @return boolean true if written, false if skipped
function M.emit(name, result, render_opts)
  local ok = emit_mod.write(name, result.json)
  if not ok then return false end

  -- Recipe sidecar: serialize render_opts for DB persistence
  local recipe_src = render_opts or (result and result.recipe and render_opts)
  if not recipe_src and result and result.recipe then
    -- result.recipe is already a JSON string (from render_with_recipe)
    emit_mod.write_recipe(name, result.recipe)
  elseif recipe_src then
    local ser_ok, recipe_json = pcall(serializer.serialize, recipe_src)
    if ser_ok then
      emit_mod.write_recipe(name, recipe_json)
    end
  end

  return true
end

return M
