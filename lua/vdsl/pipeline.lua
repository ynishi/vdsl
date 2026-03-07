--- Pipeline: multi-pass workflow orchestration.
--
-- Compiles multiple passes × variations into workflow JSONs and a
-- _pipeline.json manifest. The manifest tells the MCP executor how
-- to batch-submit passes sequentially, transfer output→input images
-- between passes, and track per-variation failures.
--
-- Lua is compile-only. Execution (ComfyUI submit, polling, file
-- transfer) is handled entirely by the MCP vdsl_run tool.
--
-- Diff detection: Each compile writes _manifest.json to the output
-- run directory (output/{save_dir}/{timestamp}/). On subsequent
-- compiles, the latest manifest is loaded from the output directory
-- to skip unchanged workflows (hash-based diff). No separate cache
-- directory is needed — everything lives with the output.
-- Cascade invalidation ensures child passes are regenerated when
-- their parent pass output changes.
--
-- Usage:
--   local vdsl     = require("vdsl")
--   local pipeline = require("vdsl.pipeline")
--
--   local pipe = pipeline.new("klimt_3pass", {
--     save_dir  = "klimt_v9",
--     seed_base = 60100,
--     size      = { 832, 1216 },
--   })
--
--   pipe:pass("p1", function(v, ctx)
--     return {
--       world = vdsl.world { model = "base_model.safetensors" },
--       cast  = { build_cast(v) },
--       steps = 30, cfg = 6.0, seed = ctx.seed,
--     }
--   end)
--
--   pipe:pass("p2", {
--     sweep = { denoise = { 0.5, 0.6, 0.7, 0.8 } }
--   }, function(v, ctx)
--     return {
--       world   = vdsl.world { model = "refiner.safetensors" },
--       cast    = { build_cast(v) },
--       stage   = vdsl.stage { latent_image = ctx.prev_output },
--       denoise = v.sweep.denoise,
--       seed    = ctx.seed,
--     }
--   end)
--
--   pipe:compile(variations)
--   -- Default mode="cached": skip unchanged, writes to VDSL_OUT_DIR
--
--   -- Force regenerate all (ignore manifest):
--   pipe:compile(variations, { mode = "full" })
--
--   -- Only specific variations:
--   pipe:compile(variations, { only = { "onsen_towel" } })

local compiler = require("vdsl.compiler")
local json     = require("vdsl.util.json")
local fs       = require("vdsl.runtime.fs")

local Pipeline = {}
Pipeline.__index = Pipeline

-- ============================================================
-- Construction
-- ============================================================

--- Create a new Pipeline.
-- @param name string pipeline name (used for manifest and logging)
-- @param opts table { save_dir, seed_base, size, ... }
-- @return Pipeline
function Pipeline.new(name, opts)
  if type(name) ~= "string" or name == "" then
    error("pipeline.new: name is required", 2)
  end
  opts = opts or {}
  local self = setmetatable({}, Pipeline)
  self._name      = name
  self._save_dir  = opts.save_dir or name
  self._seed_base = opts.seed_base or 0
  self._size      = opts.size
  self._passes    = {}  -- ordered list of { name, opts, fn }
  self._gates     = {}  -- gates[pass_name] = { type = "pick"|"judge", fn = eval_fn }
  return self
end

-- ============================================================
-- Pass definition
-- ============================================================

--- Define a pass.
-- @param name string pass name (e.g. "p1", "p2")
-- @param opts_or_fn table|function pass options or compile function
-- @param fn function|nil compile function if opts_or_fn is a table
-- @return Pipeline self (for chaining)
function Pipeline:pass(name, opts_or_fn, fn)
  if type(name) ~= "string" or name == "" then
    error("pipeline:pass: name is required", 2)
  end
  -- Check duplicate pass name
  for _, p in ipairs(self._passes) do
    if p.name == name then
      error("pipeline:pass: duplicate pass name '" .. name .. "'", 2)
    end
  end

  local pass_opts, pass_fn
  if type(opts_or_fn) == "function" then
    pass_opts = {}
    pass_fn   = opts_or_fn
  elseif type(opts_or_fn) == "table" then
    pass_opts = opts_or_fn
    pass_fn   = fn
  else
    error("pipeline:pass: expected function or table, got " .. type(opts_or_fn), 2)
  end
  if type(pass_fn) ~= "function" then
    error("pipeline:pass: compile function is required", 2)
  end

  self._passes[#self._passes + 1] = {
    name  = name,
    opts  = pass_opts,
    fn    = pass_fn,
  }
  return self
end

--- Define a pick gate after the most recently defined pass.
-- The evaluator receives candidate info and returns the selected
-- sweep suffix, or nil if outputs are not yet available.
-- @param eval_fn function(candidates, base_var) → suffix|nil
-- @return Pipeline self (for chaining)
function Pipeline:pick(eval_fn)
  if type(eval_fn) ~= "function" then
    error("pipeline:pick: evaluator function required", 2)
  end
  local last_pass = self._passes[#self._passes]
  if not last_pass then
    error("pipeline:pick: must follow a pass definition", 2)
  end
  if self._gates[last_pass.name] then
    error("pipeline:pick: gate already defined for '" .. last_pass.name .. "'", 2)
  end
  self._gates[last_pass.name] = { type = "pick", fn = eval_fn }
  return self
end

--- Define a judge gate after the most recently defined pass.
-- Unlike pick (N→1), judge allows N→K survival with ranking.
-- The evaluator receives candidate info and returns survivors.
-- @param eval_fn function(candidates, base_var) → survivors
--   Return formats:
--     string        → single survivor (pick-compatible)
--     string[]      → ordered list of survivor suffixes
--     { survivors, pruned?, scores? } → full result with metadata
--     nil           → unresolved (outputs not available yet)
-- @return Pipeline self (for chaining)
function Pipeline:judge(eval_fn)
  if type(eval_fn) ~= "function" then
    error("pipeline:judge: evaluator function required", 2)
  end
  local last_pass = self._passes[#self._passes]
  if not last_pass then
    error("pipeline:judge: must follow a pass definition", 2)
  end
  if self._gates[last_pass.name] then
    error("pipeline:judge: gate already defined for '" .. last_pass.name .. "'", 2)
  end
  self._gates[last_pass.name] = { type = "judge", fn = eval_fn }
  return self
end

-- ============================================================
-- Sweep expansion (cross product)
-- ============================================================

--- Resolve sweep spec for a base variation.
-- @param sweep_spec table|function|nil
-- @param base_variation table
-- @return table|nil  sweep parameter map { key = { val1, val2, ... } }
local function resolve_sweep(sweep_spec, base_variation)
  if sweep_spec == nil then
    return nil
  end
  if type(sweep_spec) == "function" then
    return sweep_spec(base_variation)
  end
  if type(sweep_spec) == "table" then
    return sweep_spec
  end
  error("sweep must be a table or function, got " .. type(sweep_spec), 3)
end

--- Compute the cross product of sweep parameter axes.
-- { denoise = {0.5, 0.7}, cfg = {4, 6} } → 4 combinations
-- @param sweep_params table { axis_name = { values... }, ... }
-- @return table array of { key_suffix, values_map }
local function cross_product(sweep_params)
  if not sweep_params then return nil end

  -- Collect axes in deterministic order
  local axes = {}
  for k in pairs(sweep_params) do
    axes[#axes + 1] = k
  end
  table.sort(axes)

  if #axes == 0 then return nil end

  -- Build combinations recursively
  local combos = { { suffix_parts = {}, values = {} } }
  for _, axis in ipairs(axes) do
    local values = sweep_params[axis]
    if type(values) ~= "table" or #values == 0 then
      error("sweep axis '" .. axis .. "' must be a non-empty array", 3)
    end
    local expanded = {}
    for _, combo in ipairs(combos) do
      for _, val in ipairs(values) do
        local new_parts  = {}
        local new_values = {}
        for i, p in ipairs(combo.suffix_parts) do new_parts[i] = p end
        for k, v in pairs(combo.values) do new_values[k] = v end

        -- Build key suffix: axis initial + value
        local val_str
        if type(val) == "number" then
          -- 0.65 → "65", 4.0 → "4"
          if val == math.floor(val) then
            val_str = tostring(math.floor(val))
          else
            val_str = tostring(val):gsub("%.", "")
          end
        else
          val_str = tostring(val)
        end
        new_parts[#new_parts + 1] = axis:sub(1, 1) .. val_str
        new_values[axis] = val

        expanded[#expanded + 1] = {
          suffix_parts = new_parts,
          values       = new_values,
        }
      end
    end
    combos = expanded
  end

  return combos
end

-- ============================================================
-- Variation set expansion
-- ============================================================

--- Build the expanded variation set for a pass.
-- @param prev_variations table array of expanded variations from previous pass
-- @param sweep_spec table|function|nil
-- @return table array of expanded variations
local function expand_variations(prev_variations, sweep_spec)
  local result = {}
  for _, pv in ipairs(prev_variations) do
    local sweep_params = resolve_sweep(sweep_spec, pv.base)
    local combos = cross_product(sweep_params)
    if combos then
      for _, combo in ipairs(combos) do
        local suffix = table.concat(combo.suffix_parts, "_")
        result[#result + 1] = {
          key       = pv.key .. "__" .. suffix,
          base      = pv.base,
          sweep     = combo.values,
          parent_key = pv.key,
          index     = #result + 1,
        }
      end
    else
      -- No sweep: carry forward
      result[#result + 1] = {
        key              = pv.key,
        base             = pv.base,
        sweep            = pv.sweep,
        parent_key       = pv.key,
        _prev_output_key = pv._prev_output_key,  -- propagate pick ref
        index            = #result + 1,
      }
    end
  end
  return result
end

--- Convert base variations to the internal expanded format.
-- @param variations table array of { key = "...", ... }
-- @return table array of expanded variations
local function init_variations(variations)
  local result = {}
  for i, v in ipairs(variations) do
    if type(v) ~= "table" or not v.key then
      error("variation[" .. i .. "] must be a table with a 'key' field", 2)
    end
    result[i] = {
      key        = v.key,
      base       = v,
      sweep      = {},
      parent_key = nil,
      index      = i,
    }
  end
  return result
end

-- ============================================================
-- Output filename resolution
-- ============================================================

--- ComfyUI appends _00001_ to the output prefix in a fresh directory.
-- By isolating each run in a timestamped subdirectory, the counter
-- always starts at 00001 and the filename is predictable.
local OUTPUT_SUFFIX = "_00001_.png"

--- Build the expected output filename for a pass + variation key.
-- @param pass_name string
-- @param variation_key string
-- @return string e.g. "p1_char_a_00001_.png"
local function output_filename(pass_name, variation_key)
  return pass_name .. "_" .. variation_key .. OUTPUT_SUFFIX
end

--- Generate a run-level timestamp for directory isolation.
-- @return string e.g. "20260304_170000"
local function generate_run_timestamp()
  return os.date("%Y%m%d_%H%M%S")
end

-- ============================================================
-- Hash utility
-- ============================================================

--- DJB2 hash of a string, returned as 8-char hex.
-- @param s string
-- @return string e.g. "a7b3c1d0"
local function hash_string(s)
  local h = 5381
  for i = 1, #s do
    h = ((h * 33) + s:byte(i)) % 0x100000000
  end
  return string.format("%08x", h)
end

-- ============================================================
-- Manifest persistence (co-located with output)
-- ============================================================

--- Ensure a directory exists (mkdir -p).
-- @param path string
local function ensure_dir(path)
  fs.mkdir(path)
end

--- Load the previous manifest from the latest timestamped output directory.
-- Scans output/{save_dir}/ for YYYYMMDD_HHMMSS subdirectories containing
-- _manifest.json and returns the most recent one.
-- @param save_dir string e.g. "klimt_v9"
-- @return table|nil manifest data
local function load_prev_manifest(save_dir)
  local base = "output/" .. save_dir
  local entries = fs.ls(base)

  -- Find latest timestamped directory
  local latest = nil
  for _, dirname in ipairs(entries) do
    if dirname:match("^%d%d%d%d%d%d%d%d_%d%d%d%d%d%d$") then
      if not latest or dirname > latest then
        latest = dirname
      end
    end
  end

  if not latest then return nil end

  local path = base .. "/" .. latest .. "/_manifest.json"
  local content = fs.read(path)
  if not content then return nil end
  local ok, data = pcall(json.decode, content)
  if not ok then return nil end
  return data
end

--- Save manifest to the output run directory.
-- Written alongside the output PNGs for co-location.
-- @param run_dir string e.g. "klimt_v9/20260304_170000"
-- @param data table manifest data
local function save_manifest(run_dir, data)
  local dir = "output/" .. run_dir
  ensure_dir(dir)
  local path = dir .. "/_manifest.json"
  local encoded = json.encode(data, true)
  pcall(fs.write, path, encoded)
end

--- Build a lookup table from previous cache.
-- @param cache table|nil previous cache data
-- @return table { output_name = { hash, run_dir } }
local function build_cache_lookup(cache)
  local lookup = {}
  if not cache or not cache.entries then
    return lookup
  end
  for output_name, entry in pairs(cache.entries) do
    lookup[output_name] = {
      hash    = entry.hash,
      run_dir = entry.run_dir,
    }
  end
  return lookup
end

--- Build a filter set from an array of keys.
-- @param keys table|nil array of variation keys
-- @return table|nil set { key = true }
local function build_filter_set(keys)
  if not keys then return nil end
  local set = {}
  for _, k in ipairs(keys) do
    set[k] = true
  end
  return set
end

-- ============================================================
-- Pick contraction (sweep N → 1)
-- ============================================================

--- Escape Lua pattern special characters.
local function pattern_escape(s)
  return s:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1")
end

--- Contract sweep-expanded variations by picking one per base variation.
-- Groups by parent_key, calls evaluator per group, returns contracted set.
-- If evaluator returns nil → no contraction (outputs not available yet).
-- @param expanded_vars table sweep-expanded variations
-- @param pick_fn function evaluator
-- @param pass_name string name of the sweep pass
-- @param cache_entries table current cache entries (for output path resolution)
-- @return table contracted variations, or nil if pick unresolved
local function contract_by_pick(expanded_vars, pick_fn, pass_name, cache_entries)
  -- Group by parent_key
  local groups = {}
  local group_order = {}
  for _, ev in ipairs(expanded_vars) do
    local pk = ev.parent_key or ev.key
    if not groups[pk] then
      groups[pk] = {}
      group_order[#group_order + 1] = pk
    end
    groups[pk][#groups[pk] + 1] = ev
  end

  local result = {}
  for _, pk in ipairs(group_order) do
    local candidates = groups[pk]
    if #candidates == 1 then
      -- Not a sweep expansion, pass through
      result[#result + 1] = candidates[1]
    else
      -- Build candidate info for evaluator
      local cand_info = {}
      local pk_escaped = pattern_escape(pk)
      for _, c in ipairs(candidates) do
        local suffix = c.key:match("^" .. pk_escaped .. "__(.+)$") or c.key
        local output_name = pass_name .. "_" .. c.key
        local entry = cache_entries[output_name]
        local output_path = nil
        local exists = false
        if entry then
          output_path = "output/" .. entry.run_dir .. "/"
                        .. output_name .. OUTPUT_SUFFIX
          exists = fs.exists(output_path)
        end
        cand_info[#cand_info + 1] = {
          suffix      = suffix,
          key         = c.key,
          sweep       = c.sweep,
          output_name = output_name,
          output_path = output_path,
          exists      = exists,
        }
      end

      -- Call evaluator
      local selected = pick_fn(cand_info, candidates[1].base)

      if selected == nil then
        -- Pick unresolved (outputs not available yet)
        return nil
      end

      -- Find the picked candidate
      local picked = nil
      for i, c in ipairs(candidates) do
        if cand_info[i].suffix == selected then
          picked = c
          break
        end
      end
      if not picked then
        error(string.format(
          "pick: invalid selection '%s' for variation '%s'",
          tostring(selected), pk), 2)
      end

      -- Contract: revert key to base for naming (p3_a),
      -- _prev_output_key tracks the actual picked output (a__d06).
      result[#result + 1] = {
        key              = pk,
        base             = picked.base,
        sweep            = picked.sweep,
        parent_key       = pk,
        _prev_output_key = picked.key,  -- "a__d06" for transfer resolution
        index            = #result,
      }
    end
  end

  return result
end

-- ============================================================
-- Judge contraction (sweep N → K)
-- ============================================================

--- Normalize a judge evaluator's return value.
-- Accepts: nil, string, array of strings, or table with survivors field.
-- @param raw any raw return value from judge eval_fn
-- @return table|nil  { survivors = string[], pruned = string[]|nil, scores = table|nil }
local function normalize_judge_result(raw)
  if raw == nil then return nil end
  if type(raw) == "string" then
    return { survivors = { raw } }
  end
  if type(raw) == "table" then
    if raw[1] then  -- array of suffix strings
      return { survivors = raw }
    end
    if raw.survivors then return raw end
  end
  error("judge: invalid return value (expected nil, string, array, or {survivors=...})", 3)
end

--- Contract sweep-expanded variations by judging: keep top-K per base variation.
-- Groups by parent_key, calls evaluator per group, returns contracted set.
-- Unlike pick (N→1), judge allows N→K survival with sweep suffix preserved.
-- @param expanded_vars table sweep-expanded variations
-- @param judge_fn function evaluator
-- @param pass_name string name of the sweep pass
-- @param cache_entries table current cache entries (for output path resolution)
-- @return table|nil  { contracted = variations[], info = { survivors, pruned, scores } }
local function contract_by_judge(expanded_vars, judge_fn, pass_name, cache_entries)
  -- Group by parent_key
  local groups = {}
  local group_order = {}
  for _, ev in ipairs(expanded_vars) do
    local pk = ev.parent_key or ev.key
    if not groups[pk] then
      groups[pk] = {}
      group_order[#group_order + 1] = pk
    end
    groups[pk][#groups[pk] + 1] = ev
  end

  local result = {}
  local all_survivors = {}
  local all_pruned = {}
  local all_scores = nil

  for _, pk in ipairs(group_order) do
    local candidates = groups[pk]
    if #candidates == 1 then
      -- Not a sweep expansion, pass through
      result[#result + 1] = candidates[1]
      all_survivors[#all_survivors + 1] = candidates[1].key
    else
      -- Build candidate info for evaluator (same structure as pick)
      local cand_info = {}
      local pk_escaped = pattern_escape(pk)
      for _, c in ipairs(candidates) do
        local suffix = c.key:match("^" .. pk_escaped .. "__(.+)$") or c.key
        local output_name = pass_name .. "_" .. c.key
        local entry = cache_entries[output_name]
        local output_path = nil
        local exists = false
        if entry then
          output_path = "output/" .. entry.run_dir .. "/"
                        .. output_name .. OUTPUT_SUFFIX
          exists = fs.exists(output_path)
        end
        cand_info[#cand_info + 1] = {
          suffix      = suffix,
          key         = c.key,
          sweep       = c.sweep,
          output_name = output_name,
          output_path = output_path,
          exists      = exists,
        }
      end

      -- Call evaluator and normalize
      local raw = judge_fn(cand_info, candidates[1].base)
      local judged = normalize_judge_result(raw)

      if judged == nil then
        return nil  -- unresolved
      end

      -- Merge scores
      if judged.scores then
        all_scores = all_scores or {}
        for k, v in pairs(judged.scores) do all_scores[k] = v end
      end

      -- Merge pruned
      if judged.pruned then
        for _, s in ipairs(judged.pruned) do
          all_pruned[#all_pruned + 1] = s
        end
      end

      -- Build suffix→candidate lookup
      local suffix_to_cand = {}
      for i, c in ipairs(candidates) do
        suffix_to_cand[cand_info[i].suffix] = c
      end

      -- Keep survivors in rank order (key preserved, not reverted)
      for _, suffix in ipairs(judged.survivors) do
        local survivor = suffix_to_cand[suffix]
        if not survivor then
          error(string.format(
            "judge: invalid survivor '%s' for variation '%s'",
            tostring(suffix), pk), 2)
        end
        all_survivors[#all_survivors + 1] = suffix
        result[#result + 1] = {
          key              = survivor.key,
          base             = survivor.base,
          sweep            = survivor.sweep,
          parent_key       = survivor.key,  -- self-referencing for next expand
          _prev_output_key = survivor.key,
          index            = #result,
        }
      end
    end
  end

  return {
    contracted = result,
    info = {
      survivors = all_survivors,
      pruned    = #all_pruned > 0 and all_pruned or nil,
      scores    = all_scores,
    },
  }
end

--- Apply external judge result from VDSL_JUDGE_RESULT env var.
-- Called when the judge function returns nil (pending) but MCP has
-- provided a judge_result to resume compilation.
-- Format: { "<pass_name>": { "survivors": ["suffix1", ...] } }
-- @param expanded_vars table sweep-expanded variations
-- @param pass_name string name of the judge pass
-- @param cache_entries table current cache entries
-- @return table|nil  same shape as contract_by_judge result
local function apply_external_judge(expanded_vars, pass_name, cache_entries)
  local env = os.getenv("VDSL_JUDGE_RESULT")
  if not env then return nil end

  local json = require("vdsl.util.json")
  local ok, data = pcall(json.decode, env)
  if not ok or type(data) ~= "table" then return nil end

  local pass_data = data[pass_name]
  if not pass_data or not pass_data.survivors then return nil end

  local survivor_set = {}
  for _, s in ipairs(pass_data.survivors) do
    survivor_set[s] = true
  end

  -- Group by parent_key (same logic as contract_by_judge)
  local groups = {}
  local group_order = {}
  for _, ev in ipairs(expanded_vars) do
    local pk = ev.parent_key or ev.key
    if not groups[pk] then
      groups[pk] = {}
      group_order[#group_order + 1] = pk
    end
    groups[pk][#groups[pk] + 1] = ev
  end

  local result = {}
  local all_survivors = {}
  local all_pruned = {}

  for _, pk in ipairs(group_order) do
    local candidates = groups[pk]
    if #candidates == 1 then
      result[#result + 1] = candidates[1]
      all_survivors[#all_survivors + 1] = candidates[1].key
    else
      local pk_escaped = pattern_escape(pk)
      for _, c in ipairs(candidates) do
        local suffix = c.key:match("^" .. pk_escaped .. "__(.+)$") or c.key
        if survivor_set[suffix] then
          all_survivors[#all_survivors + 1] = suffix
          result[#result + 1] = {
            key        = c.key,
            base       = c.base,
            sweep      = c.sweep,
            parent_key = c.parent_key,
          }
        else
          all_pruned[#all_pruned + 1] = suffix
        end
      end
    end
  end

  if #result == 0 then return nil end

  return {
    contracted = result,
    info = {
      survivors = all_survivors,
      pruned    = #all_pruned > 0 and all_pruned or nil,
    },
  }
end

-- ============================================================
-- Helpers
-- ============================================================

--- Count total workflows across all passes.
-- @param manifest table
-- @return number
local function count_workflows(manifest)
  local n = 0
  for _, p in ipairs(manifest.passes) do
    n = n + #p.workflows
  end
  return n
end

-- ============================================================
-- Compile
-- ============================================================

--- Compile all passes × variations into workflow JSONs + manifest.
-- Writes to VDSL_OUT_DIR when set, otherwise returns the manifest table.
--
-- compile_opts (optional):
--   mode   = "cached"   -- (default) Hash-based diff, skip unchanged
--   mode   = "full"     -- Force regenerate all, ignore manifest
--   only   = { "key" }  -- Only compile these variation keys
--   except = { "key" }  -- Skip these variation keys
--
-- @param self Pipeline
-- @param variations table array of base variations (each must have .key)
-- @param compile_opts table|nil optional compile options
-- @return table manifest
function Pipeline:compile(variations, compile_opts)
  if #self._passes == 0 then
    error("pipeline:compile: no passes defined", 2)
  end
  if type(variations) ~= "table" or #variations == 0 then
    error("pipeline:compile: variations must be a non-empty array", 2)
  end

  compile_opts = compile_opts or {}
  local mode = compile_opts.mode or "cached"
  local use_cache = (mode == "cached")
  local only_set  = build_filter_set(compile_opts.only)
  local except_set = build_filter_set(compile_opts.except)

  local out_dir = os.getenv("VDSL_OUT_DIR")

  -- Load previous manifest for diff detection
  local prev_manifest = use_cache and load_prev_manifest(self._save_dir) or nil
  local prev_lookup = build_cache_lookup(prev_manifest)

  -- Generate timestamped run directory for isolation.
  -- Each compile produces a unique subdirectory so ComfyUI's
  -- auto-increment counter always starts at _00001_.
  local run_ts  = generate_run_timestamp()
  local run_dir = self._save_dir .. "/" .. run_ts

  local manifest = {
    version  = 1,
    name     = self._name,
    save_dir = self._save_dir,
    run_dir  = run_dir,
    passes   = json.array(),
  }

  -- Cache entries for persistence (tracks all workflows, including skipped)
  local cache_entries = {}

  -- Track which variations were regenerated per pass (for cascade)
  local regenerated = {}  -- regenerated[pass_name] = { variation_key = true }

  local current_vars = init_variations(variations)
  local total_compiled = 0
  local total_skipped  = 0

  for pass_idx, pass_def in ipairs(self._passes) do
    local prev_pass = self._passes[pass_idx - 1]

    -- Expand variations with sweep
    current_vars = expand_variations(current_vars, pass_def.opts.sweep)

    regenerated[pass_def.name] = {}

    local pass_manifest = {
      name            = pass_def.name,
      depends_on      = prev_pass and prev_pass.name or nil,
      variation_count = #current_vars,
      workflows       = json.array(),
      transfers       = json.array(),
    }

    -- Collect unique parent keys for transfers, with their source run_dir
    local transfer_parents = {}
    local seen_parents = {}

    for _, ev in ipairs(current_vars) do
      local output_name = pass_def.name .. "_" .. ev.key

      -- Apply variation filter (only/except operate on base key)
      local base_key = ev.base.key
      if only_set and not only_set[base_key] then
        goto continue_variation
      end
      if except_set and except_set[base_key] then
        goto continue_variation
      end

      -- Build context
      local ctx = {
        seed        = self._seed_base + ev.index,
        pass_name   = pass_def.name,
        pass_index  = pass_idx,
        save_dir    = self._save_dir,
        size        = self._size,
      }
      if prev_pass then
        local prev_key  = ev._prev_output_key or ev.parent_key
        ctx.prev_pass   = prev_pass.name
        ctx.prev_output = output_filename(prev_pass.name, prev_key)
      end

      -- Build the variation view passed to user function
      local v = {
        key   = ev.key,
        base  = ev.base,
        sweep = ev.sweep or {},
        index = ev.index,
      }
      -- Copy base fields to top level for convenience
      for k, val in pairs(ev.base) do
        if k ~= "key" and v[k] == nil then
          v[k] = val
        end
      end

      -- Call user compile function
      local render_opts = pass_def.fn(v, ctx)
      if type(render_opts) ~= "table" then
        error(string.format(
          "pipeline: pass '%s' fn must return a table for variation '%s'",
          pass_def.name, ev.key), 2)
      end

      -- Apply pipeline defaults
      if not render_opts.size and self._size then
        render_opts.size = self._size
      end
      if not render_opts.save_dir then
        render_opts.save_dir = self._save_dir
      end
      if not render_opts.output then
        render_opts.output = run_dir .. "/" .. output_name
      end

      -- Compile to ComfyUI workflow JSON
      local result = compiler.compile(render_opts)
      -- Normalize run_dir (contains timestamp) before hashing so that
      -- the same logical workflow produces the same hash across runs.
      local hash_json = result.json:gsub(run_dir, "__RUN__")
      local workflow_hash = hash_string(hash_json)

      -- Diff detection: should we skip this workflow?
      local should_skip = false
      if use_cache then
        local prev = prev_lookup[output_name]
        if prev and prev.hash == workflow_hash then
          -- Hash matches — check cascade: was parent regenerated?
          local cascaded = false
          if prev_pass and ev.parent_key then
            local parent_output = prev_pass.name .. "_" .. ev.parent_key
            if regenerated[prev_pass.name][ev.parent_key] then
              cascaded = true
            end
          end
          if not cascaded then
            -- Hash matches and no cascade — skip recompilation.
            -- In compile-only mode (no generation yet), PNGs may not
            -- exist; that is fine because re-emitting identical JSON
            -- is wasteful. The runner/MCP will generate from the
            -- latest manifest regardless.
            should_skip = true
          end
        end
      end

      if should_skip then
        -- Reuse previous manifest entry (output exists in old run_dir)
        local prev = prev_lookup[output_name]

        cache_entries[output_name] = {
          hash    = workflow_hash,
          run_dir = prev.run_dir,
          pass    = pass_def.name,
          key     = ev.key,
        }
        total_skipped = total_skipped + 1
        io.write(string.format("  [skip] %s (unchanged)\n", output_name))
      else
        -- Write JSON to VDSL_OUT_DIR
        local json_filename = output_name .. ".json"
        if out_dir then
          local path = out_dir .. "/" .. json_filename
          fs.write(path, result.json)
        end

        pass_manifest.workflows[#pass_manifest.workflows + 1] = json_filename

        -- Mark as regenerated for cascade tracking
        regenerated[pass_def.name][ev.key] = true

        -- Cache entry with new run_dir
        cache_entries[output_name] = {
          hash    = workflow_hash,
          run_dir = run_dir,
          pass    = pass_def.name,
          key     = ev.key,
        }
        total_compiled = total_compiled + 1
        if use_cache then
          io.write(string.format("  [emit] %s\n", output_name))
        end
      end

      -- Track transfers (unique parent keys only)
      local xfer_key = ev._prev_output_key or ev.parent_key
      if prev_pass and xfer_key and not seen_parents[xfer_key] then
        seen_parents[xfer_key] = true
        -- Resolve the source run_dir for this parent's output
        local parent_output_name = prev_pass.name .. "_" .. xfer_key
        local parent_entry = cache_entries[parent_output_name]
        local source_run_dir = parent_entry and parent_entry.run_dir or run_dir
        transfer_parents[#transfer_parents + 1] = {
          parent_key  = xfer_key,
          source_dir  = source_run_dir,
        }
      end

      ::continue_variation::
    end

    -- Build transfer list
    if prev_pass then
      table.sort(transfer_parents, function(a, b)
        return a.parent_key < b.parent_key
      end)
      for _, tp in ipairs(transfer_parents) do
        local filename = output_filename(prev_pass.name, tp.parent_key)
        pass_manifest.transfers[#pass_manifest.transfers + 1] = {
          filename = filename,
          from     = "output/" .. tp.source_dir .. "/" .. filename,
          to       = "input/" .. filename,
        }
      end
    end

    manifest.passes[#manifest.passes + 1] = pass_manifest

    -- Gate: contract sweep expansion if pick/judge defined
    local gate = self._gates[pass_def.name]
    if gate then
      if gate.type == "pick" then
        local contracted = contract_by_pick(
          current_vars, gate.fn, pass_def.name, cache_entries)
        if contracted then
          -- Pick resolved → contract variations for subsequent passes
          io.write(string.format(
            "[pick] %s: %d → %d variations\n",
            pass_def.name, #current_vars, #contracted))
          current_vars = contracted
          manifest.pick_resolved = true
        else
          -- Pick unresolved → stop compilation here, mark pick gate
          manifest.pick_gate = {
            after_pass = pass_def.name,
            status     = "pending",
          }
          io.write(string.format(
            "[pick] %s: pending (outputs not available)\n", pass_def.name))
          break  -- stop compiling further passes
        end
      elseif gate.type == "judge" then
        local judge_result = contract_by_judge(
          current_vars, gate.fn, pass_def.name, cache_entries)
        if judge_result then
          local cv   = judge_result.contracted
          local info = judge_result.info
          local pruned_count = info.pruned and #info.pruned or 0
          io.write(string.format(
            "[judge] %s: %d → %d survived, %d pruned\n",
            pass_def.name, #current_vars, #cv, pruned_count))
          if info.scores then
            -- Log ranked survivors with scores
            for i, s in ipairs(info.survivors) do
              if info.scores[s] then
                io.write(string.format(
                  "  [rank %d] %s  score=%.1f\n", i, s, info.scores[s]))
              end
            end
            if info.pruned then
              for _, s in ipairs(info.pruned) do
                if info.scores[s] then
                  io.write(string.format(
                    "  [pruned] %s  score=%.1f\n", s, info.scores[s]))
                end
              end
            end
          end
          current_vars = cv
          manifest.judge_gate = {
            after_pass = pass_def.name,
            status     = "resolved",
            survivors  = info.survivors,
            pruned     = info.pruned,
            scores     = info.scores,
          }
        else
          -- Judge unresolved — check for external judge_result (MCP resume)
          local ext = apply_external_judge(
            current_vars, pass_def.name, cache_entries)
          if ext then
            local cv   = ext.contracted
            local info = ext.info
            local pruned_count = info.pruned and #info.pruned or 0
            io.write(string.format(
              "[judge] %s: %d → %d survived, %d pruned (external)\n",
              pass_def.name, #current_vars, #cv, pruned_count))
            current_vars = cv
            manifest.judge_gate = {
              after_pass = pass_def.name,
              status     = "resolved",
              survivors  = info.survivors,
              pruned     = info.pruned,
            }
          else
            -- No external result → stop compilation
            manifest.pick_gate = {
              after_pass = pass_def.name,
              status     = "pending",
              type       = "judge",
            }
            io.write(string.format(
              "[judge] %s: pending (outputs not available)\n", pass_def.name))
            break
          end
        end
      end
    end
  end

  -- Write _pipeline.json manifest (only includes workflows to run)
  if out_dir then
    local path = out_dir .. "/_pipeline.json"
    fs.write(path, json.encode(manifest, true))

    local total = total_compiled + total_skipped
    if use_cache and total_skipped > 0 then
      io.write(string.format(
        "[pipeline] %s: %d passes, %d/%d compiled (%d skipped) → %s\n",
        self._name, #self._passes,
        total_compiled, total, total_skipped, out_dir))
    else
      io.write(string.format(
        "[pipeline] %s: %d passes, %d total workflows → %s\n",
        self._name, #self._passes, total_compiled, out_dir))
    end
  end

  -- Persist manifest to output run directory for future diff detection
  if use_cache then
    local manifest_data = {
      version   = 2,
      name      = self._name,
      save_dir  = self._save_dir,
      timestamp = run_ts,
      entries   = cache_entries,
    }
    save_manifest(run_dir, manifest_data)
    io.write(string.format(
      "[manifest] output/%s/_manifest.json\n", run_dir))
  end

  return manifest
end

-- ============================================================
-- Module
-- ============================================================

local M = {}

function M.new(name, opts)
  return Pipeline.new(name, opts)
end

--- Interactive STDIN prompt for pick selection.
-- Displays candidates with index numbers and sweep values,
-- waits for user input via io.read().
-- @param candidates table array of { suffix, sweep, output_path, exists }
-- @return string selected suffix
function M.prompt(candidates)
  io.write("\n  Pick:\n")
  for i, c in ipairs(candidates) do
    local parts = {}
    local sorted_keys = {}
    for k in pairs(c.sweep) do sorted_keys[#sorted_keys + 1] = k end
    table.sort(sorted_keys)
    for _, k in ipairs(sorted_keys) do
      parts[#parts + 1] = k .. "=" .. tostring(c.sweep[k])
    end
    local status = c.exists and "" or " (not yet)"
    io.write(string.format(
      "    [%d] %s  %s%s\n", i, c.suffix, table.concat(parts, ", "), status))
  end
  io.write("  > ")
  io.flush()
  local input = io.read("*l")
  if not input then return nil end

  -- Accept index number
  local idx = tonumber(input)
  if idx and candidates[idx] then
    return candidates[idx].suffix
  end

  -- Accept suffix string
  for _, c in ipairs(candidates) do
    if c.suffix == input then return c.suffix end
  end

  error("pick: invalid selection '" .. tostring(input) .. "'", 2)
end

return M
