--- Catalog: Camera / Shot type / Lens / Composition.
-- Photography-oriented Traits. SDXL-effective tags only.
-- Traits carry hints where the framing implies post-processing needs.
-- Target: SDXL and above.
--
-- Note: Focal length numbers (85mm, 35mm) have indirect stylistic effect
-- but do NOT simulate actual lens physics. f-stop numbers are non-functional
-- for DOF control on diffusion models (Bokeh Diffusion, SIGGRAPH Asia 2025).

local Trait   = require("vdsl.trait")
local Catalog = require("vdsl.catalog")

return Catalog.new {
  -- === Shot types ===
  extreme_closeup = Trait.new("extreme close-up", 1.2)
    + Trait.new("macro, face detail, skin texture")
    :hint("face", { fidelity = 0.7 }),

  closeup = Trait.new("close-up", 1.1)
    + Trait.new("face, portrait")
    :hint("face", { fidelity = 0.6 }),

  bust_shot = Trait.new("upper body", 1.1)
    :hint("face", { fidelity = 0.5 }),

  medium_shot = Trait.new("medium shot, waist up, upper body"),

  cowboy_shot = Trait.new("cowboy shot"),

  full_body = Trait.new("full body"),

  wide_shot = Trait.new("wide shot"),

  -- === Angles ===
  eye_level = Trait.new("eye level, straight on, front view"),

  low_angle = Trait.new("low angle", 1.1)
    + Trait.new("from below"),

  high_angle = Trait.new("high angle", 1.1)
    + Trait.new("from above"),

  dutch_angle = Trait.new("dutch angle, tilted camera, dynamic angle"),

  birds_eye = Trait.new("from above, top-down, aerial view")
    :hint("hires", { scale = 1.5, denoise = 0.35 }),

  -- === Lens (stylistic influence, not physics simulation) ===
  portrait_lens = Trait.new("85mm", 1.1)
    + Trait.new("shallow depth of field, portrait photography, bokeh"),

  wide_angle = Trait.new("35mm, wide angle lens, wide field of view"),

  telephoto = Trait.new("200mm, telephoto, compressed background, background separation"),

  macro = Trait.new("macro lens, extreme magnification, sharp detail")
    :hint("sharpen", { radius = 1, sigma = 0.8 }),

  tilt_shift = Trait.new("tilt-shift, selective focus, miniature effect"),

  -- === Depth of field (stylistic, not physically accurate) ===
  shallow_dof = Trait.new("shallow depth of field", 1.1)
    + Trait.new("bokeh, blurred background"),

  deep_dof = Trait.new("deep depth of field, everything in focus"),

  -- === Focus (directs viewer attention to specific area) ===
  -- Danbooru composition tags. Combine with framing for portrait work.
  face_focus = Trait.new("face focus", 1.1),

  eye_focus = Trait.new("eye focus", 1.1),

  -- === Face angle (head orientation, distinct from camera angle) ===
  -- profile = complete side view (one side only).
  -- from_side (below) = observer position (45-90 degrees).
  profile = Trait.new("profile", 1.1),

  three_quarter_view = Trait.new("three quarter view"),

  -- === Viewpoint (observer position relative to subject) ===
  -- Distinct from Angles (camera tilt). These control which side of
  -- the subject is visible, essential for candid/snap compositions.
  from_side = Trait.new("from side", 1.1),

  from_behind = Trait.new("from behind", 1.1),

  over_shoulder = Trait.new("over shoulder shot, over-the-shoulder"),

  -- === Composition ===
  rule_of_thirds = Trait.new("rule of thirds, off-center subject"),

  centered = Trait.new("centered composition, symmetrical framing"),

  symmetrical = Trait.new("perfect symmetry, mirror composition, balanced"),

  dynamic = Trait.new("dynamic composition, diagonal lines, motion, action pose"),

  negative_space = Trait.new("negative space, minimalist composition, isolated subject"),

  leading_lines = Trait.new("leading lines, perspective, vanishing point, depth"),
}
