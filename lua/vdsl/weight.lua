--- Weight: semantic weight values for LoRA, IPAdapter, ControlNet, etc.
-- Value type (not a full Entity). Replaces raw numbers with meaningful levels.

local M = {}

local function fixed(value)
  return { _kind = "weight", mode = "fixed", value = value }
end

-- Named levels
M.none   = fixed(0.0)
M.subtle = fixed(0.2)
M.light  = fixed(0.4)
M.medium = fixed(0.6)
M.heavy  = fixed(0.8)
M.full   = fixed(1.0)

--- Create a range weight (for experimentation/batch).
-- @param min number lower bound
-- @param max number upper bound
-- @param step number|nil quantization step (nil = continuous)
-- @return table Weight value
function M.range(min, max, step)
  if type(min) ~= "number" then
    error("Weight.range: min must be a number", 2)
  end
  if type(max) ~= "number" then
    error("Weight.range: max must be a number", 2)
  end
  if min > max then
    error("Weight.range: min must be <= max", 2)
  end
  return {
    _kind = "weight",
    mode  = "range",
    min   = min,
    max   = max,
    step  = step,
  }
end

--- Check if a value is a Weight.
-- @param w any
-- @return boolean
function M.is_weight(w)
  return type(w) == "table" and w._kind == "weight"
end

--- Resolve a weight to a concrete number.
-- Accepts: number (passthrough), Weight value, nil (returns default).
-- Range weights use math.random(); when called via compiler.compile(),
-- the RNG is automatically seeded. For standalone usage, the caller
-- is responsible for calling math.randomseed() beforehand.
-- @param w number|table|nil
-- @param default number|nil fallback (default 1.0)
-- @return number
function M.resolve(w, default)
  if w == nil then return default or 1.0 end
  if type(w) == "number" then return w end
  if M.is_weight(w) then
    if w.mode == "fixed" then
      return w.value
    end
    if w.mode == "range" then
      if w.step then
        local steps = math.floor((w.max - w.min) / w.step)
        return w.min + math.random(0, steps) * w.step
      else
        return w.min + math.random() * (w.max - w.min)
      end
    end
  end
  error("Weight: invalid weight: " .. tostring(w), 2)
end

return M
