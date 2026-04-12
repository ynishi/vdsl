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
  standing = Trait.new("standing")
    :desc("standing upright"),

  arms_crossed = Trait.new("arms crossed, crossed arms")
    :desc("standing with arms crossed"),

  hand_on_hip = Trait.new("hand on hip")
    :desc("standing with one hand on hip"),

  hands_in_pockets = Trait.new("hands in pockets")
    :desc("standing casually with hands in pockets"),

  arms_at_sides = Trait.new("arms at sides")
    :desc("standing with arms relaxed at sides"),

  leaning = Trait.new("leaning against wall", 1.1)
    + Trait.new("leaning, casual pose")
    :desc("leaning casually against a wall"),

  contrapposto = Trait.new("contrapposto", 1.1)
    + Trait.new("weight shift, S-curve pose")
    :desc("contrapposto pose with weight shifted to one leg creating an S-curve"),

  -- === Sitting ===
  sitting = Trait.new("sitting")
    :desc("sitting"),

  kneeling = Trait.new("kneeling")
    :desc("kneeling on the ground"),

  crouching = Trait.new("crouching, squatting")
    :desc("crouching or squatting down"),

  seiza = Trait.new("seiza, kneeling on floor, formal sitting")
    :desc("sitting in formal Japanese seiza position, kneeling on the floor"),

  -- === Action / Dynamic ===
  walking = Trait.new("walking")
    :desc("walking"),

  running = Trait.new("running", 1.1)
    :desc("running in motion"),

  jumping = Trait.new("jumping", 1.1)
    + Trait.new("mid-air, in the air")
    :desc("jumping mid-air"),

  dynamic_pose = Trait.new("dynamic pose", 1.1)
    + Trait.new("action pose, motion")
    :desc("dynamic action pose conveying motion and energy"),

  dancing = Trait.new("dancing")
    :desc("dancing"),

  stretching = Trait.new("stretching, stretching arms")
    :desc("stretching arms upward"),

  fighting_stance = Trait.new("fighting stance", 1.1)
    + Trait.new("combat ready, martial arts pose")
    :desc("combat-ready fighting stance in martial arts pose"),

  -- === Lying / Reclining ===
  lying_down = Trait.new("lying down")
    :desc("lying down"),

  lying_on_back = Trait.new("lying on back, supine")
    :desc("lying on back face up"),

  lying_on_side = Trait.new("lying on side", 1.1)
    :desc("lying on one side"),

  sleeping = Trait.new("sleeping, asleep, eyes closed")
    :desc("sleeping peacefully with eyes closed"),

  reclining = Trait.new("reclining, leaning back")
    :desc("reclining, leaning back in a relaxed position"),

  -- === Gaze direction ===
  looking_at_viewer = Trait.new("looking at viewer")
    :desc("looking directly at the viewer"),

  looking_back = Trait.new("looking back, looking over shoulder")
    :desc("looking back over the shoulder"),

  looking_up = Trait.new("looking up")
    :desc("looking upward"),

  looking_down = Trait.new("looking down")
    :desc("looking downward"),

  looking_away = Trait.new("looking away, averting eyes")
    :desc("looking away with averted eyes"),

  looking_to_the_side = Trait.new("looking to the side")
    :desc("looking to the side"),

  facing_viewer = Trait.new("facing viewer")
    :desc("facing toward the viewer"),

  facing_away = Trait.new("facing away")
    :desc("facing away from the viewer"),

  -- === Gesture ===
  head_tilt = Trait.new("head tilt")
    :desc("tilting head to one side"),

  arms_behind_back = Trait.new("arms behind back")
    :desc("arms held behind the back"),

  peace_sign = Trait.new("peace sign, v sign")
    :desc("making a peace sign with fingers"),

  open_arms = Trait.new("open arms, arms spread", 1.1)
    :desc("arms spread open wide"),

  -- === Candid / Daily life gestures ===
  chin_rest = Trait.new("chin rest, head on hand")
    :desc("resting chin on hand"),

  adjusting_hair = Trait.new("adjusting hair, hair tucking")
    :desc("adjusting hair, tucking a strand behind the ear"),

  waving = Trait.new("waving, waving hand")
    :desc("waving hand in greeting"),
}
