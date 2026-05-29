--- 16_cam_sequence.lua: vdsl.cam — N shots through one identity Subject.
--
-- vdsl.cam renders a sequence of shots that each overlay a per-shot trait on a
-- FIXED identity Subject (plus an optional shared `common` framing trait), then
-- emit one image per shot. This is the reusable "cam" loop — host tools that
-- scaffold cam scripts call vdsl.cam instead of hand-rolling the render loop, so
-- the render/cast DSL shape lives in exactly one place.
--
-- Run (compile only, no server): lua -e "package.path='lua/?.lua;lua/?/init.lua;'..package.path" examples/16_cam_sequence.lua

local vdsl = require("vdsl")
local C    = vdsl.catalogs

local w = vdsl.world {
  model     = "waiIllustrious_v16.safetensors",
  clip_skip = 2,
}

-- The fixed identity, reused across every shot (just a Subject).
local base = vdsl.subject("1girl, solo, 20 years old")
  :with(vdsl.trait("silver hair, blue eyes"))

-- Shared framing applied to every shot.
local common_cam = C.camera.medium_shot + C.camera.eye_level

local neg = C.quality.neg_default + C.quality.neg_anatomy

-- One identity, three shots. Each shot overlays its own per-shot trait (or none)
-- on top of `base` + `common`, renders, and emits under its `name`.
vdsl.cam {
  world    = w,
  base     = base,
  negative = neg,
  common   = common_cam,
  shots = {
    { name = "cam_v1_portrait", seed = 42, trait = C.camera.portrait_lens },
    { name = "cam_v1_wide",     seed = 43, trait = vdsl.trait("full body, wide angle") },
    { name = "cam_v1_plain",    seed = 44 },  -- no per-shot trait: identity + common only
  },
}

print("=== vdsl.cam: 3 shots through one identity ===")
print("  emitted: cam_v1_portrait / cam_v1_wide / cam_v1_plain")
