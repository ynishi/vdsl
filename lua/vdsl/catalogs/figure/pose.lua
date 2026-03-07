--- Catalog: Pose / Stance / Gaze / Gesture.
-- Body position and orientation Traits. SDXL-effective tags only.
-- Target: SDXL 1.0 Base and above.
--
-- Note on camera pairing:
--   Full-body poses (standing, walking, lying) are most effective when
--   paired with camera.full_body or camera.wide_shot.
--   Gaze/gesture tags work across all framings.
--
-- Note on dynamic poses:
--   Complex or unusual poses are inherently unstable on SDXL.
--   ControlNet OpenPose is recommended for precise pose control.
--   Tags here provide "best effort" prompt-based influence.
--
-- Sources:
--   Civitai SDXL/Pony pose guides, Danbooru tag analysis,
--   Tensor.Art posture tag study, community A/B testing.

local Trait   = require("vdsl.trait")
local Catalog = require("vdsl.catalog")

return Catalog.new {
  -- === Standing ===
  standing = Trait.new("standing"),

  arms_crossed = Trait.new("arms crossed, crossed arms"),

  hand_on_hip = Trait.new("hand on hip"),

  hands_in_pockets = Trait.new("hands in pockets"),

  arms_at_sides = Trait.new("arms at sides"),

  leaning = Trait.new("leaning against wall", 1.1)
    + Trait.new("leaning, casual pose"),

  -- model-dependent: anime finetunes (Pony/Illustrious) recognize
  -- contrapposto reliably. SDXL base is inconsistent.
  contrapposto = Trait.new("contrapposto", 1.1)
    + Trait.new("weight shift, S-curve pose"),

  -- === Sitting ===
  sitting = Trait.new("sitting"),

  kneeling = Trait.new("kneeling"),

  crouching = Trait.new("crouching, squatting"),

  -- model-dependent: strong on anime finetunes, weaker on SDXL base.
  seiza = Trait.new("seiza, kneeling on floor, formal sitting"),

  -- === Action / Dynamic ===
  walking = Trait.new("walking"),

  running = Trait.new("running", 1.1),

  jumping = Trait.new("jumping", 1.1)
    + Trait.new("mid-air, in the air"),

  dynamic_pose = Trait.new("dynamic pose", 1.1)
    + Trait.new("action pose, motion"),

  dancing = Trait.new("dancing"),

  stretching = Trait.new("stretching, stretching arms"),

  fighting_stance = Trait.new("fighting stance", 1.1)
    + Trait.new("combat ready, martial arts pose"),

  -- === Lying / Reclining ===
  lying_down = Trait.new("lying down"),

  lying_on_back = Trait.new("lying on back, supine"),

  lying_on_side = Trait.new("lying on side", 1.1),

  sleeping = Trait.new("sleeping, asleep, eyes closed"),

  reclining = Trait.new("reclining, leaning back"),

  -- === Gaze direction ===
  -- These control head/eye orientation, not camera position.
  looking_at_viewer = Trait.new("looking at viewer"),

  looking_back = Trait.new("looking back, looking over shoulder"),

  looking_up = Trait.new("looking up"),

  looking_down = Trait.new("looking down"),

  looking_away = Trait.new("looking away, averting eyes"),

  looking_to_the_side = Trait.new("looking to the side"),

  facing_viewer = Trait.new("facing viewer"),

  facing_away = Trait.new("facing away"),

  -- === Gesture ===
  head_tilt = Trait.new("head tilt"),

  arms_behind_back = Trait.new("arms behind back"),

  -- model-dependent: anime finetunes recognize this as V-sign gesture.
  -- SDXL base may produce finger-count errors.
  peace_sign = Trait.new("peace sign, v sign"),

  open_arms = Trait.new("open arms, arms spread", 1.1),

  -- === Candid / Daily life gestures ===
  -- Natural, unposed actions. Key for snap/street photography style.
  chin_rest = Trait.new("chin rest, head on hand"),

  adjusting_hair = Trait.new("adjusting hair, hair tucking"),

  waving = Trait.new("waving, waving hand"),
}
