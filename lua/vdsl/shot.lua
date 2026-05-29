--- Shot: Core entity that encapsulates a single render invocation.
-- Wraps render opts (world, cast, stage, ...) as a typed, lifecycle-managed value.
-- flat field structure mirrors opts exactly so compiler.compile(shot) and
-- serializer.serialize(shot) work without modification.

local Entity = require("vdsl.entity")

local Shot = Entity.define_core("shot")

-- Known strategy values (mirrors engine.lua STRATEGIES)
local VALID_STRATEGIES = { recommended = true }

-- Known on_conflict values (mirrors engine.lua CONFLICT_STRATEGIES)
local VALID_CONFLICT_STRATEGIES = {
  ignore = true, warn = true, downweight = true, drop = true,
}

-- Flat render fields (everything compiler/serializer may read from opts)
local RENDER_FIELDS = {
  "world", "cast", "stage", "atmosphere", "negative",
  "seed", "steps", "cfg", "sampler", "scheduler",
  "denoise", "size", "strategy", "on_conflict",
  "post", "auto_post", "output",
  "gen_id", "run_id", "workspace_id", "script", "ts",
}

--- Create a Shot entity from render opts.
-- Validates fields the same way engine.lua does (front-loaded).
-- @param opts table render options (same shape as passed to vdsl.render)
-- @return Shot
function Shot.new(opts)
  if type(opts) ~= "table" then
    error("Shot: expected a table, got " .. type(opts), 2)
  end

  -- --- Validation (mirrors engine.lua:756-794) ---

  if not opts.world then
    error("Shot: 'world' is required", 2)
  end
  if not Entity.is(opts.world, "world") then
    error("Shot: 'world' must be a World entity", 2)
  end

  -- cast normalisation: single Cast entity → wrap in array
  local cast = opts.cast
  if Entity.is(cast, "cast") then
    cast = { cast }
  end

  if not cast or #cast == 0 then
    error("Shot: 'cast' requires at least one Cast entity", 2)
  end
  if not Entity.is(cast[1], "cast") then
    error("Shot: 'cast[1]' must be a Cast entity", 2)
  end

  if opts.stage and not Entity.is(opts.stage, "stage") then
    error("Shot: 'stage' must be a Stage entity", 2)
  end
  if opts.post and not Entity.is(opts.post, "post") then
    error("Shot: 'post' must be a Post entity", 2)
  end
  if opts.atmosphere and not Entity.is(opts.atmosphere, "trait") then
    error("Shot: 'atmosphere' must be a Trait entity", 2)
  end
  if opts.strategy then
    if type(opts.strategy) ~= "string" then
      error("Shot: 'strategy' must be a string", 2)
    end
    if not VALID_STRATEGIES[opts.strategy] then
      error("Shot: unknown strategy '" .. opts.strategy
        .. "', available: recommended", 2)
    end
  end

  local conflict_strategy = opts.on_conflict or "warn"
  if not VALID_CONFLICT_STRATEGIES[conflict_strategy] then
    error("Shot: unknown on_conflict strategy '" .. conflict_strategy
      .. "', available: ignore, warn, downweight, drop", 2)
  end

  -- --- Build self with flat field copy ---
  local self = setmetatable({}, Shot)

  for _, key in ipairs(RENDER_FIELDS) do
    self[key] = opts[key]
  end
  -- use normalised cast (may have been wrapped above)
  self.cast = cast

  return self
end

--- Compile this Shot into a ComfyUI workflow.
-- @return table { prompt, json, graph }
function Shot:compile()
  return require("vdsl.compiler").compile(self)
end

--- Analyze token usage without building a graph.
-- @return table diagnostics
function Shot:check()
  return require("vdsl.compiler").check(self)
end

--- Serialize this Shot to a JSON recipe string.
-- Overrides the generic define_core serialize with the recipe format.
-- @return string JSON
function Shot:serialize()
  return require("vdsl.runtime.serializer").serialize(self)
end

--- Reconstruct a Shot from a serialized JSON string (from Shot:serialize()).
-- @param data string JSON produced by Shot:serialize()
-- @return Shot
function Shot.from(data)
  return Shot.new(require("vdsl.runtime.serializer").deserialize(data))
end

-- :clone() / :with(overrides) / :equals(other) are provided by define_core generics.

return Shot
