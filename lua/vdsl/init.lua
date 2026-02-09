--- vdsl V2: Visual DSL for ComfyUI
-- Public API facade. Core entities + execution layer.
--
-- Usage:
--   local vdsl = require("vdsl")
--   local walking = vdsl.trait("walking pose, full body")
--   local cat = vdsl.subject("cat"):with(walking):quality("high"):style("anime")
--   local ugly = vdsl.trait("blurry, ugly")
--   local w = vdsl.world { model = "sd_xl_base_1.0" }
--   local c = vdsl.cast { subject = cat, negative = ugly,
--                          lora = { vdsl.lora("detail", vdsl.weight.heavy) } }
--   local r = vdsl.render { world = w, cast = { c }, theme = vdsl.themes.cinema }
--   print(r.json)

local Entity   = require("vdsl.entity")
local Trait    = require("vdsl.trait")
local Subject  = require("vdsl.subject")
local Weight   = require("vdsl.weight")
local World    = require("vdsl.world")
local Cast     = require("vdsl.cast")
local Stage    = require("vdsl.stage")
local Post       = require("vdsl.post")
local Catalog    = require("vdsl.catalog")
local Theme      = require("vdsl.theme")
local compiler   = require("vdsl.compiler")
local decode_mod = require("vdsl.decode")
local png_mod    = require("vdsl.png")
local recipe_mod = require("vdsl.recipe")
local json_mod   = require("vdsl.json")
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

--- Create a Theme (named Catalog with metadata and negatives).
-- @param def table { name, category, tags, traits, negatives }
-- @return Theme
function M.theme(def)
  return Theme.new(def)
end

--- Create a LoRA config (convenience for Cast.lora entries).
-- @param name string LoRA filename
-- @param weight number|Weight|nil weight (default 1.0)
-- @return table { name, weight }
function M.lora(name, weight)
  if type(name) ~= "string" or name == "" then
    error("vdsl.lora: name is required", 2)
  end
  return { name = name, weight = weight or 1.0 }
end

--- Semantic weight values.
M.weight = Weight

-- ============================================================
-- Built-in themes (lazy-loaded)
-- ============================================================

M.themes = setmetatable({}, {
  __index = function(t, name)
    local ok, theme = pcall(require, "vdsl.themes." .. name)
    if ok then
      rawset(t, name, theme)
      return theme
    end
    return nil
  end,
})

-- ============================================================
-- Type system (exposed for advanced usage)
-- ============================================================

M.entity = Entity

-- ============================================================
-- Execution layer
-- ============================================================

function M.render(opts)
  return compiler.compile(opts)
end

function M.connect(url, opts)
  local Registry = require("vdsl.registry")
  return Registry.connect(url, opts)
end

function M.from_object_info(info, url, headers)
  local Registry = require("vdsl.registry")
  return Registry.from_object_info(info, url, headers)
end

function M.set_matcher(fn)
  local matcher = require("vdsl.matcher")
  matcher.set_matcher(fn)
end

--- Set a custom HTTP transport backend.
-- @param backend table { get, post_json, download } or nil to reset
function M.set_transport(backend)
  local transport = require("vdsl.transport")
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
    local Registry = require("vdsl.registry")
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
    local ok, opts = pcall(recipe_mod.deserialize, chunks["vdsl"])
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
  local recipe_json = recipe_mod.serialize(render_opts)
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
  local recipe_json = recipe_mod.serialize(render_opts)
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
  result.recipe = recipe_mod.serialize(opts)
  return result
end

return M
