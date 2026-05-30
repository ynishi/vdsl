--- cam.lua: render a sequence of shots through one identity Subject.
--
-- The "cam" pattern is: take one fixed identity (a Subject), then render N
-- shots that each overlay a per-shot trait (pose / clothing / framing) on top
-- of that identity, emitting one image per shot.
--
-- This loop used to be string-templated by host tools (e.g. an MCP server
-- generating Lua source). Keeping the DSL-shape knowledge here, in vdsl, means
-- a change to vdsl.render / vdsl.cast only has to be reflected in one place.
--
-- Wired into the package as `vdsl.cam{...}` (see init.lua). `deps` is injected
-- by init.lua to avoid a circular require (render/cast/emit live on the vdsl
-- module table, not in leaf modules).
--
-- Prompt composition order (positive prompt, left to right):
--   1. identity base text    -- the Subject's base string
--   2. identity traits       -- traits fixed on the identity via Subject:with
--   3. per-shot `trait`       -- this shot's overlay
--   4. shared `common` trait  -- framing applied to every shot
-- The negative prompt is a separate channel (the cast's `negative`); it is not
-- concatenated into the positive prompt. See docs/cam-and-identity.md.

local M = {}

local DEFAULT_SAMPLER = "euler_ancestral"
local DEFAULT_STEPS   = 25
local DEFAULT_CFG     = 6.0
local DEFAULT_SIZE    = { 832, 1216 }

--- Render each shot through `base` and emit one image per shot.
--
-- @param deps table { render, cast, emit } — the vdsl module's primitives.
-- @param opts table {
--   world    = World,                 -- required
--   base     = Subject,               -- required: the fixed identity
--   shots    = { { name=string, seed=number, trait=Trait|nil }, ... }, -- required, non-empty
--   negative = Trait|nil,             -- shared negative prompt
--   common   = Trait|nil,             -- shared trait added to every shot (e.g. camera framing)
--   sampler  = string  (default "euler_ancestral"),
--   steps    = number  (default 25),
--   cfg      = number  (default 6.0),
--   size     = { w, h } (default { 832, 1216 }),
-- }
-- @return table array of render results (one per shot, in order).
function M.run(deps, opts)
  if type(deps) ~= "table" or type(deps.render) ~= "function"
      or type(deps.cast) ~= "function" or type(deps.emit) ~= "function" then
    error("vdsl.cam: deps must provide render/cast/emit functions", 2)
  end
  if type(opts) ~= "table" then
    error("vdsl.cam: expected an options table", 2)
  end
  if opts.world == nil then
    error("vdsl.cam: 'world' is required", 2)
  end
  if opts.base == nil then
    error("vdsl.cam: 'base' (identity Subject) is required", 2)
  end
  if type(opts.shots) ~= "table" or #opts.shots == 0 then
    error("vdsl.cam: 'shots' must be a non-empty array", 2)
  end

  local sampler  = opts.sampler or DEFAULT_SAMPLER
  local steps    = opts.steps or DEFAULT_STEPS
  local cfg      = opts.cfg or DEFAULT_CFG
  local size     = opts.size or DEFAULT_SIZE
  local common   = opts.common
  local negative = opts.negative

  local results = {}
  for i, s in ipairs(opts.shots) do
    if type(s.name) ~= "string" or s.name == "" then
      error("vdsl.cam: shots[" .. i .. "] needs a non-empty name", 2)
    end
    -- Overlay: per-shot trait optionally combined with the shared `common`
    -- trait, applied on top of the fixed identity via :with. When neither is
    -- present the identity is used as-is (no empty trait is fabricated).
    local overlay
    if s.trait and common then
      overlay = s.trait + common
    else
      overlay = s.trait or common
    end
    local subject = overlay and opts.base:with(overlay) or opts.base

    local result = deps.render {
      world   = opts.world,
      cast    = { deps.cast { subject = subject, negative = negative } },
      sampler = sampler,
      steps   = steps,
      cfg     = cfg,
      seed    = s.seed,
      size    = size,
    }
    deps.emit(s.name, result)
    results[#results + 1] = result
  end

  return results
end

return M
