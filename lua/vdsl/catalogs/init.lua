--- Built-in Catalogs: curated Trait dictionaries for prompt construction.
--
-- == Management Policy ==
--
-- 1. Target baseline: SDXL 1.0 (base, not refiner)
--    Tags MUST produce observable effect on base SDXL without finetunes or LoRAs.
--    Tags that only work on specific finetunes (Illustrious, Animagine, Pony)
--    are allowed but MUST be annotated as "model-dependent" in comments.
--
-- 2. No cargo-cult tags
--    Every tag must have evidence of effectiveness:
--    - Community A/B test results, or
--    - Published research (CLIP interrogation, attention analysis), or
--    - Verifiable prompt-to-output correlation.
--    Rejected examples: "8k uhd" (no SDXL training data), "absurdres",
--    "trending on artstation" (proven ineffective in 1.5M prompt analysis).
--
-- 3. Emphasis policy
--    Primary concept tag: emphasis 1.1-1.2 (via Trait.new second argument).
--    Supplementary tags: no emphasis (default 1.0).
--    Never exceed 1.3 — diminishing returns and artifact risk.
--
-- 4. Descriptive over referential
--    Prefer descriptive phrases ("sunlight filtering through leaves")
--    over jargon names ("dappled light") when the descriptive form
--    produces more stable results.
--    Exception: well-known technique names (e.g. "Rembrandt lighting")
--    that SDXL recognizes reliably.
--
-- 5. No physics simulation claims
--    Diffusion models do NOT simulate optics.
--    Focal length numbers (85mm, 35mm) have stylistic association only.
--    f-stop numbers (f/1.4, f/11) are non-functional for DOF control
--    (ref: Bokeh Diffusion, SIGGRAPH Asia 2025).
--    Document these limitations in comments.
--
-- 6. Negative tags
--    Kept in quality catalog (neg_default, neg_anatomy, neg_face).
--    Themes reference these instead of duplicating.
--    Single source of truth for negative vocabulary.
--
-- 7. Hints
--    Traits carry hints (hires, color, sharpen, face) where the tag
--    implies post-processing needs. Hints are consumed by Post/Stage
--    compilation — they do NOT affect prompt text.
--
-- 8. Adding new entries
--    - Verify tag effectiveness (rule 2)
--    - Use emphasis within 1.0-1.2 range (rule 3)
--    - Add hint metadata where applicable (rule 7)
--    - Run full test suite: all catalog integration tests
--    - Annotate model-dependent entries (rule 1)
--
-- == Structure ==
--
-- Root access is lazy-loaded via __index. Packs are eager-loaded internally,
-- so pairs() enumerates sub-catalogs once a pack is accessed.
--
--   (1) Top-level: quality, style, camera, lighting, effect, material
--   (2) Packs:     figure/, environment/, color/
--
-- == Usage ==
--
--   local C = require("vdsl.catalogs")
--   C.camera.closeup                  -- direct Trait access
--   C.figure.pose.standing            -- pack → sub-catalog → Trait
--   for k, v in pairs(C.figure) do   -- enumerates: pose, expression, body, ...
--   for k, v in pairs(C.camera) do   -- enumerates: closeup, bust_shot, ...
--

local M = setmetatable({}, {
  __index = function(t, name)
    local ok, cat = pcall(require, "vdsl.catalogs." .. name)
    if ok then
      rawset(t, name, cat)
      return cat
    end
    return nil
  end,
})

return M
