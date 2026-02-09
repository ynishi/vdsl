--- Recipe: serialize/deserialize vdsl render opts for embedding.
-- Captures semantic information lost during compilation:
--   Trait structure, emphasis, hints, Subject composition,
--   Theme name, Weight semantic names, render parameters.
--
-- Stored as JSON in PNG tEXt chunk (keyword: "vdsl").
--
-- Usage:
--   local recipe = require("vdsl.recipe")
--   local data = recipe.serialize(render_opts)   -- → JSON string
--   local opts = recipe.deserialize(data)         -- → table

local Entity = require("vdsl.entity")
local json   = require("vdsl.json")
local Weight = require("vdsl.weight")

local M = {}

-- Recipe format version (for future compatibility)
local VERSION = 1

-- ============================================================
-- Serialize helpers: entity → plain table
-- ============================================================

--- Serialize a Trait to a plain table.
local function ser_trait(t)
  if t == nil then return nil end
  if type(t) == "string" then return { _t = "str", v = t } end
  if not Entity.is(t, "trait") then
    return { _t = "str", v = Entity.resolve_text(t) }
  end

  local result = { _t = "trait" }

  if t._parts then
    -- Composite trait
    result.parts = {}
    for _, p in ipairs(t._parts) do
      result.parts[#result.parts + 1] = { text = p.text, emphasis = p.emphasis }
    end
  else
    result.text = t.text
    result.emphasis = t.emphasis
  end

  if t._hints then
    result.hints = {}
    for k, v in pairs(t._hints) do
      result.hints[k] = v
    end
  end

  return result
end

--- Serialize a Subject to a plain table.
local function ser_subject(s)
  if s == nil then return nil end
  if type(s) == "string" then return { _t = "str", v = s } end
  if not Entity.is(s, "subject") then
    return { _t = "str", v = Entity.resolve_text(s) }
  end

  local result = { _t = "subject", traits = {} }
  for _, t in ipairs(s._traits) do
    result.traits[#result.traits + 1] = ser_trait(t)
  end
  return result
end

--- Serialize a Weight value.
local function ser_weight(w)
  if w == nil then return nil end
  if type(w) == "number" then return w end
  if Weight.is_weight(w) then
    return { _kind = "weight", mode = w.mode, value = w.value,
             min = w.min, max = w.max, step = w.step }
  end
  return w
end

--- Serialize a Cast to a plain table.
local function ser_cast(c)
  if not Entity.is(c, "cast") then return nil end

  local result = {
    subject  = ser_subject(c.subject),
    negative = ser_trait(c.negative),
  }

  if c.lora then
    result.lora = {}
    for _, l in ipairs(c.lora) do
      result.lora[#result.lora + 1] = {
        name   = l.name,
        weight = ser_weight(l.weight),
      }
    end
  end

  if c.ipadapter then
    result.ipadapter = {
      image  = c.ipadapter.image,
      weight = ser_weight(c.ipadapter.weight),
    }
  end

  return result
end

--- Serialize a Stage to a plain table.
local function ser_stage(s)
  if not Entity.is(s, "stage") then return nil end

  local result = {}
  if s.controlnet then
    result.controlnet = {}
    for _, cn in ipairs(s.controlnet) do
      result.controlnet[#result.controlnet + 1] = {
        type     = cn.type,
        image    = cn.image,
        strength = cn.strength,
      }
    end
  end
  if s.latent_image then
    result.latent_image = s.latent_image
  end
  return result
end

--- Serialize a Post to a plain table.
local function ser_post(p)
  if not Entity.is(p, "post") then return nil end
  local ops = {}
  for _, op in ipairs(p:ops()) do
    ops[#ops + 1] = { type = op.type, params = op.params }
  end
  return ops
end

--- Serialize a Theme reference (name only; themes are built-in/loadable).
local function ser_theme(t)
  if t == nil then return nil end
  if Entity.is(t, "theme") then
    return { name = t.name, category = t.category }
  end
  return nil
end

-- ============================================================
-- Main serialize
-- ============================================================

--- Serialize render opts into a JSON string for embedding.
-- @param opts table render options (same as passed to vdsl.render)
-- @return string JSON
function M.serialize(opts)
  if type(opts) ~= "table" then
    error("recipe.serialize: expected a table", 2)
  end

  local recipe = {
    _v = VERSION,
    world = nil,
    cast  = nil,
  }

  -- World
  if opts.world and Entity.is(opts.world, "world") then
    recipe.world = {
      model     = opts.world.model,
      vae       = opts.world.vae,
      clip_skip = opts.world.clip_skip,
    }
  end

  -- Casts
  if opts.cast then
    recipe.cast = {}
    for _, c in ipairs(opts.cast) do
      recipe.cast[#recipe.cast + 1] = ser_cast(c)
    end
  end

  -- Stage
  if opts.stage then
    recipe.stage = ser_stage(opts.stage)
  end

  -- Post
  if opts.post then
    recipe.post = ser_post(opts.post)
  end

  -- Theme (name reference only)
  recipe.theme = ser_theme(opts.theme)

  -- Global negative
  if opts.negative then
    recipe.negative = ser_trait(opts.negative)
  end

  -- Render params
  recipe.seed      = opts.seed
  recipe.steps     = opts.steps
  recipe.cfg       = opts.cfg
  recipe.sampler   = opts.sampler
  recipe.scheduler = opts.scheduler
  recipe.denoise   = opts.denoise
  recipe.size      = opts.size
  recipe.output    = opts.output
  recipe.auto_post = opts.auto_post

  return json.encode(recipe, false)
end

-- ============================================================
-- Deserialize helpers: plain table → reconstructable opts
-- ============================================================

--- Deserialize a trait table back to a Trait entity.
local function deser_trait(data)
  if data == nil then return nil end
  if data._t == "str" then return data.v end

  local Trait = require("vdsl.trait")

  if data._t == "trait" then
    local t
    if data.parts then
      -- Composite: rebuild via +
      t = Trait.new(data.parts[1].text, data.parts[1].emphasis)
      for i = 2, #data.parts do
        t = t + Trait.new(data.parts[i].text, data.parts[i].emphasis)
      end
    else
      t = Trait.new(data.text, data.emphasis)
    end

    -- Restore hints
    if data.hints then
      for op_type, params in pairs(data.hints) do
        t = t:hint(op_type, params)
      end
    end

    return t
  end

  return nil
end

--- Deserialize a subject table back to a Subject entity.
local function deser_subject(data)
  if data == nil then return nil end
  if data._t == "str" then return data.v end

  local Subject = require("vdsl.subject")

  if data._t == "subject" and data.traits and #data.traits > 0 then
    -- First trait becomes the base
    local first_trait = deser_trait(data.traits[1])
    local subj
    if type(first_trait) == "string" then
      subj = Subject.new(first_trait)
    else
      subj = Subject.from_trait(first_trait)
    end

    for i = 2, #data.traits do
      local t = deser_trait(data.traits[i])
      subj = subj:with(t)
    end
    return subj
  end

  return nil
end

--- Deserialize a cast table.
local function deser_cast(data)
  if data == nil then return nil end
  local Cast = require("vdsl.cast")

  local opts = {
    subject  = deser_subject(data.subject),
    negative = deser_trait(data.negative),
  }

  if data.lora then
    opts.lora = {}
    for _, l in ipairs(data.lora) do
      opts.lora[#opts.lora + 1] = { name = l.name, weight = l.weight }
    end
  end

  if data.ipadapter then
    opts.ipadapter = {
      image  = data.ipadapter.image,
      weight = data.ipadapter.weight,
    }
  end

  return Cast.new(opts)
end

--- Deserialize a stage table.
local function deser_stage(data)
  if data == nil then return nil end
  local Stage = require("vdsl.stage")
  return Stage.new(data)
end

--- Deserialize post ops.
local function deser_post(data)
  if data == nil then return nil end
  local Post = require("vdsl.post")

  if #data == 0 then return nil end
  local p = Post.new(data[1].type, data[1].params)
  for i = 2, #data do
    p = p + Post.new(data[i].type, data[i].params)
  end
  return p
end

-- ============================================================
-- Main deserialize
-- ============================================================

--- Deserialize a JSON string back to render opts.
-- Returns a table that can be passed directly to vdsl.render().
-- Design note: No defensive size/depth limits on decoded JSON.
-- Recipe data is user-managed (embedded in user's own PNG files).
-- @param data string JSON
-- @return table render opts with reconstructed entities
function M.deserialize(data)
  if type(data) ~= "string" then
    error("recipe.deserialize: expected a string", 2)
  end

  local recipe = json.decode(data)
  if type(recipe) ~= "table" then
    error("recipe.deserialize: invalid recipe format", 2)
  end

  local World = require("vdsl.world")

  local opts = {}

  -- World
  if recipe.world then
    opts.world = World.new(recipe.world)
  end

  -- Casts
  if recipe.cast then
    opts.cast = {}
    for _, c in ipairs(recipe.cast) do
      opts.cast[#opts.cast + 1] = deser_cast(c)
    end
  end

  -- Stage
  opts.stage = deser_stage(recipe.stage)

  -- Post
  opts.post = deser_post(recipe.post)

  -- Theme (by name, try to load built-in)
  if recipe.theme and recipe.theme.name then
    local ok, theme = pcall(require, "vdsl.themes." .. recipe.theme.name)
    if ok then
      opts.theme = theme
    end
  end

  -- Global negative
  if recipe.negative then
    opts.negative = deser_trait(recipe.negative)
  end

  -- Render params
  opts.seed      = recipe.seed
  opts.steps     = recipe.steps
  opts.cfg       = recipe.cfg
  opts.sampler   = recipe.sampler
  opts.scheduler = recipe.scheduler
  opts.denoise   = recipe.denoise
  opts.size      = recipe.size
  opts.output    = recipe.output
  opts.auto_post = recipe.auto_post

  return opts
end

return M
