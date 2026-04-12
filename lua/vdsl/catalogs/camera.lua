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
    :hint("face", { fidelity = 0.7 })
    :desc("extreme close-up macro shot showing fine skin texture and facial detail"),

  closeup = Trait.new("close-up", 1.1)
    + Trait.new("face, portrait")
    :hint("face", { fidelity = 0.6 })
    :desc("close-up portrait framing focused on the face"),

  bust_shot = Trait.new("upper body", 1.1)
    :hint("face", { fidelity = 0.5 })
    :desc("upper body framing from the waist up"),

  medium_shot = Trait.new("medium shot, waist up, upper body")
    :desc("medium shot framing from the waist up"),

  cowboy_shot = Trait.new("cowboy shot")
    :desc("cowboy shot framing from mid-thigh up"),

  full_body = Trait.new("full body")
    :desc("full body shot showing the entire figure"),

  wide_shot = Trait.new("wide shot")
    :desc("wide shot capturing the subject and surrounding environment"),

  -- === Angles ===
  eye_level = Trait.new("eye level, straight on, front view")
    :desc("shot taken at eye level, looking straight at the subject"),

  low_angle = Trait.new("low angle", 1.1)
    + Trait.new("from below")
    :desc("low angle shot looking up at the subject from below"),

  high_angle = Trait.new("high angle", 1.1)
    + Trait.new("from above")
    :desc("high angle shot looking down at the subject from above"),

  dutch_angle = Trait.new("dutch angle, tilted camera, dynamic angle")
    :desc("tilted dutch angle creating a dynamic diagonal composition"),

  birds_eye = Trait.new("from above, top-down, aerial view")
    :hint("hires", { scale = 1.5, denoise = 0.35 })
    :desc("bird's-eye view looking directly down from above"),

  -- === Lens (stylistic influence, not physics simulation) ===
  portrait_lens = Trait.new("85mm", 1.1)
    + Trait.new("shallow depth of field, portrait photography, bokeh")
    :desc("85mm portrait lens with shallow depth of field and soft bokeh background"),

  wide_angle = Trait.new("35mm, wide angle lens, wide field of view")
    :desc("wide angle lens capturing a broad field of view"),

  telephoto = Trait.new("200mm, telephoto, compressed background, background separation")
    :desc("telephoto lens with compressed background and strong subject separation"),

  macro = Trait.new("macro lens, extreme magnification, sharp detail")
    :hint("sharpen", { radius = 1, sigma = 0.8 })
    :desc("macro lens with extreme magnification revealing sharp fine detail"),

  tilt_shift = Trait.new("tilt-shift, selective focus, miniature effect")
    :desc("tilt-shift lens creating a miniature diorama effect with selective focus"),

  -- === Depth of field (stylistic, not physically accurate) ===
  shallow_dof = Trait.new("shallow depth of field", 1.1)
    + Trait.new("bokeh, blurred background")
    :desc("shallow depth of field with creamy bokeh and softly blurred background"),

  deep_dof = Trait.new("deep depth of field, everything in focus")
    :desc("deep depth of field with everything in sharp focus from foreground to background"),

  -- === Focus (directs viewer attention to specific area) ===
  -- Danbooru composition tags. Combine with framing for portrait work.
  face_focus = Trait.new("face focus", 1.1)
    :desc("focus on the face, sharp facial detail"),

  eye_focus = Trait.new("eye focus", 1.1)
    :desc("focus on the eyes, sharp eye detail with catchlight"),

  -- === Face angle (head orientation, distinct from camera angle) ===
  -- profile = complete side view (one side only).
  -- from_side (below) = observer position (45-90 degrees).
  profile = Trait.new("profile", 1.1)
    :desc("profile view showing the side of the face"),

  three_quarter_view = Trait.new("three quarter view")
    :desc("three-quarter view of the face, turned slightly to one side"),

  -- === Viewpoint (observer position relative to subject) ===
  -- Distinct from Angles (camera tilt). These control which side of
  -- the subject is visible, essential for candid/snap compositions.
  from_side = Trait.new("from side", 1.1)
    :desc("viewed from the side"),

  from_behind = Trait.new("from behind", 1.1)
    :desc("viewed from behind, showing the back of the subject"),

  over_shoulder = Trait.new("over shoulder shot, over-the-shoulder")
    :desc("over-the-shoulder shot looking past the subject"),

  -- === Composition ===
  rule_of_thirds = Trait.new("rule of thirds, off-center subject")
    :desc("composed using rule of thirds with the subject placed off-center"),

  centered = Trait.new("centered composition, symmetrical framing")
    :desc("centered symmetrical composition"),

  symmetrical = Trait.new("perfect symmetry, mirror composition, balanced")
    :desc("perfectly symmetrical mirror composition with balanced framing"),

  dynamic = Trait.new("dynamic composition, diagonal lines, motion, action pose")
    :desc("dynamic composition with diagonal lines conveying motion and energy"),

  negative_space = Trait.new("negative space, minimalist composition, isolated subject")
    :desc("minimalist composition with ample negative space isolating the subject"),

  leading_lines = Trait.new("leading lines, perspective, vanishing point, depth")
    :desc("composition with leading lines drawing the eye toward a vanishing point"),
}
