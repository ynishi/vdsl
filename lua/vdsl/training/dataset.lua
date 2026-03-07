--- Dataset: declarative dataset manifest for training pipelines.
--
-- Emits a _dataset.json manifest describing how to organize
-- generated images into a training-ready directory structure.
-- Runner/MCP automatically applies the manifest after download.
--
-- Layouts:
--   "sliders"  — before/after paired dirs (Concept Sliders)
--   "kohya"    — {repeats}_{trigger}/ with caption .txt (sd-scripts, lycoriss, ti)
--
-- Usage:
--   local training = require("vdsl.training")
--
--   local ds = training.dataset {
--     name   = "puni_slider",
--     layout = "sliders",
--     source_dir = "puni_slider_pairs",
--     pairs  = {
--       { name = "01_tube_bed", seed = 91001, ... },
--     },
--   }
--   ds:emit()  -- register manifest; runner applies after download

local json = require("vdsl.util.json")
local fs   = require("vdsl.runtime.fs")

local Dataset = {}
Dataset.__index = Dataset

-- Emit registry: runner/MCP queries this after script execution.
local _emitted = {}

-- ============================================================
-- Layout definitions
-- ============================================================
-- Each layout defines:
--   entries(pairs_def, opts) → array of entry tables
--   structure               → target path templates

local LAYOUTS = {}

--- Sliders: before/after paired directories.
-- Source: gen_before_{name}_00001_.png / gen_after_{name}_00001_.png
-- Target: {root}/before/{name}.png / {root}/after/{name}.png
LAYOUTS.sliders = {
  structure = {
    dirs = { "before", "after" },
  },
  entries = function(pairs_def, opts)
    local result = json.array()
    local pass_name = opts.pass_name or "gen"
    local suffix = opts.output_suffix or "_00001_.png"
    for _, p in ipairs(pairs_def) do
      local name = p.name or p.key
      result[#result + 1] = {
        name   = name,
        before = {
          source = pass_name .. "_before_" .. name .. suffix,
          target = "before/" .. name .. ".png",
        },
        after = {
          source = pass_name .. "_after_" .. name .. suffix,
          target = "after/" .. name .. ".png",
        },
      }
    end
    return result
  end,
}

--- Kohya: {repeats}_{trigger}/ with caption .txt files.
-- Source: gen_{key}_00001_.png
-- Target: {root}/{repeats}_{trigger}/{name}.png + {name}.txt
LAYOUTS.kohya = {
  structure = {
    dirs_fn = function(opts)
      local repeats = opts.repeats or 10
      local trigger = opts.trigger or "trigger"
      return { string.format("%d_%s", repeats, trigger) }
    end,
  },
  entries = function(pairs_def, opts)
    local result = json.array()
    local pass_name = opts.pass_name or "gen"
    local suffix = opts.output_suffix or "_00001_.png"
    local repeats = opts.repeats or 10
    local trigger = opts.trigger or "trigger"
    local subdir = string.format("%d_%s", repeats, trigger)
    for _, p in ipairs(pairs_def) do
      local name = p.name or p.key
      local entry = {
        name   = name,
        image  = {
          source = pass_name .. "_" .. (p.key or name) .. suffix,
          target = subdir .. "/" .. name .. ".png",
        },
      }
      if p.caption then
        entry.caption = {
          content = p.caption,
          target  = subdir .. "/" .. name .. ".txt",
        }
      end
      result[#result + 1] = entry
    end
    return result
  end,
}


-- ============================================================
-- Constructor
-- ============================================================

--- Create a Dataset manifest.
-- @param opts table {
--   name        string    dataset name
--   layout      string    "sliders" | "kohya"
--   source_dir  string    Pipeline save_dir (where PNGs live)
--   pairs       table     array of pair definitions
--   config?     string    training config content (YAML/TOML)
--   pass_name?  string    Pipeline pass name (default "gen")
--   trigger?    string    trigger word (kohya layout)
--   repeats?    number    repeat count (kohya layout, default 10)
-- }
-- @return Dataset
function Dataset.new(opts)
  if type(opts) ~= "table" then
    error("training.dataset: expected a table, got " .. type(opts), 2)
  end
  if not opts.name or opts.name == "" then
    error("training.dataset: 'name' is required", 2)
  end
  if not opts.layout then
    error("training.dataset: 'layout' is required", 2)
  end
  if not LAYOUTS[opts.layout] then
    local available = {}
    for k in pairs(LAYOUTS) do available[#available + 1] = k end
    table.sort(available)
    error("training.dataset: unknown layout '" .. tostring(opts.layout)
      .. "' (available: " .. table.concat(available, ", ") .. ")", 2)
  end
  if not opts.pairs or type(opts.pairs) ~= "table" or #opts.pairs == 0 then
    error("training.dataset: 'pairs' must be a non-empty array", 2)
  end
  if not opts.source_dir or opts.source_dir == "" then
    error("training.dataset: 'source_dir' is required", 2)
  end

  local self = setmetatable({}, Dataset)
  self._name       = opts.name
  self._layout     = opts.layout
  self._source_dir = opts.source_dir
  self._pairs      = opts.pairs
  self._config     = opts.config
  self._opts       = opts
  return self
end

--- Build the manifest table.
-- @return table manifest data
function Dataset:manifest()
  local layout_def = LAYOUTS[self._layout]
  local entries = layout_def.entries(self._pairs, self._opts)

  -- Resolve target directories
  local dirs
  if layout_def.structure.dirs then
    dirs = layout_def.structure.dirs
  elseif layout_def.structure.dirs_fn then
    dirs = layout_def.structure.dirs_fn(self._opts)
  end

  local manifest = {
    version    = 1,
    name       = self._name,
    layout     = self._layout,
    source_dir = "output/" .. self._source_dir,
    target_dir = "output/" .. self._name .. "_dataset",
    dirs       = dirs,
    entries    = entries,
    entry_count = #entries,
  }

  if self._config then
    manifest.config = self._config
  end

  return manifest
end

--- Emit dataset manifest to registry and optionally to VDSL_OUT_DIR.
-- Runner/MCP automatically applies after download completes.
-- @return table manifest data
function Dataset:emit()
  local manifest = self:manifest()

  -- Register in-process (runner/MCP reads this after downloads)
  _emitted[#_emitted + 1] = manifest

  -- Also write to VDSL_OUT_DIR if available (MCP runner path)
  local out_dir = os.getenv("VDSL_OUT_DIR")
  if out_dir then
    local encoded = json.encode(manifest, true)
    local path = out_dir .. "/_dataset.json"
    fs.write(path, encoded)
    io.write(string.format("[dataset] %s: %d entries, layout=%s → %s\n",
      self._name, #manifest.entries, self._layout, path))
  else
    io.write(string.format("[dataset] %s: %d entries, layout=%s (registered)\n",
      self._name, #manifest.entries, self._layout))
  end

  return manifest
end

-- ============================================================
-- Emit registry accessors
-- ============================================================

local function get_emitted()
  return _emitted
end

local function clear_emitted()
  _emitted = {}
end

-- ============================================================
-- Module
-- ============================================================

local M = {}

function M.new(opts)
  return Dataset.new(opts)
end

--- List available layout names.
-- @return table array of layout name strings
function M.available_layouts()
  local names = {}
  for k in pairs(LAYOUTS) do
    names[#names + 1] = k
  end
  table.sort(names)
  return names
end

--- Apply a dataset manifest: copy images + write caption .txt files.
-- Called by runner.lua post-download. Also usable standalone.
-- @param manifest table dataset manifest (from _dataset.json or registry)
-- @return number files copied/written
function M.apply(manifest)
  if type(manifest) ~= "table" then
    error("dataset.apply: expected a table", 2)
  end
  if not manifest.source_dir or not manifest.target_dir then
    error("dataset.apply: manifest missing source_dir/target_dir", 2)
  end

  local source = manifest.source_dir
  local target = manifest.target_dir

  if manifest.dirs then
    for _, dir in ipairs(manifest.dirs) do
      fs.mkdir(target .. "/" .. dir)
    end
  end

  local copied = 0
  local missing = 0

  for _, entry in ipairs(manifest.entries or {}) do
    for _, mapping in pairs(entry) do
      if type(mapping) == "table" and mapping.source and mapping.target then
        local src = source .. "/" .. mapping.source
        local dst = target .. "/" .. mapping.target
        if fs.exists(src) then
          fs.cp(src, dst)
          copied = copied + 1
        else
          io.write(string.format("  [miss] %s\n", mapping.source))
          missing = missing + 1
        end
      end
      if type(mapping) == "table" and mapping.content and mapping.target then
        local dst = target .. "/" .. mapping.target
        fs.write(dst, mapping.content)
        copied = copied + 1
      end
    end
  end

  io.write(string.format("[dataset] %s: %d files copied to %s",
    manifest.name, copied, target))
  if missing > 0 then
    io.write(string.format(" (%d missing)", missing))
  end
  io.write("\n")

  return copied
end

M.get_emitted   = get_emitted
M.clear_emitted = clear_emitted
M._register     = function(manifest) _emitted[#_emitted + 1] = manifest end

return M
