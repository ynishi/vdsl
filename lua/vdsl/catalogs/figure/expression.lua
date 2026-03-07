--- Catalog: Expression / Emotion.
-- Facial expression Traits. SDXL-effective tags only.
-- Target: SDXL 1.0 Base and above.
--
-- IMPORTANT LIMITATION:
--   SDXL base model has WEAKER facial expression control compared to
--   anime finetunes (Illustrious, Pony). Basic emotions (smile, angry,
--   serious) work reliably. Subtle intensity variations (faint smile vs
--   wide grin) are inconsistent on base SDXL.
--
--   For best results, pair expression tags with close-up camera framing
--   (camera.closeup or camera.bust_shot). Full-body shots have
--   insufficient facial pixel density for expression control.
--
-- Note on face restoration:
--   Expression tags do NOT carry face hints. Use camera.closeup
--   (which carries hint:face) when facial detail matters.
--   Double-hinting is avoided by design.
--
-- Sources:
--   Civitai expression guides, PirateDiffusion facial expression study,
--   OpenArt SD expression prompts, Danbooru tag analysis for Pony/Illustrious.

local Trait   = require("vdsl.trait")
local Catalog = require("vdsl.catalog")
local K       = Trait  -- tag key constants

return Catalog.new {
  -- === Positive ===
  smile = Trait.new("smiling, smile")
    :tag(K.CONFLICTS, "angry, crying"),

  gentle_smile = Trait.new("gentle smile", 1.1)
    + Trait.new("soft expression, warm smile"),

  -- laughing: ":d" opens mouth wide, increasing teeth artifact risk.
  -- Dropped ":d" in favor of "open mouth" which is more controlled.
  laughing = Trait.new("laughing, open mouth, happy"),

  grin = Trait.new("grin, wide smile"),

  smirk = Trait.new("smirk, slight smile, one side of mouth raised"),

  -- fang: Danbooru "fang" = single cute canine tooth.
  -- "sharp_teeth" produces ALL teeth jagged (shark-like) — avoided.
  -- "open mouth" increases teeth artifact risk — avoided.
  -- Use "fang_out" for closed-mouth fang peeking over lip.
  fang = Trait.new("fang", 1.1),

  fang_out = Trait.new("fang out, closed mouth", 1.1),

  happy = Trait.new("happy, joyful expression")
    :tag(K.CONFLICTS, "sad, angry"),

  excited = Trait.new("excited", 1.1)
    + Trait.new("enthusiastic, eyes wide with excitement"),

  -- === Negative ===
  angry = Trait.new("angry, furrowed brows")
    :tag(K.CONFLICTS, "smiling, happy"),

  furious = Trait.new("furious", 1.1)
    + Trait.new("rage, intense anger, clenched teeth"),

  sad = Trait.new("sad", 1.1)
    + Trait.new("sorrowful, downcast eyes")
    :tag(K.CONFLICTS, "happy, laughing"),

  crying = Trait.new("crying", 1.2)
    + Trait.new("tears, tears streaming down face")
    :tag(K.CONFLICTS, "smiling, laughing"),

  scared = Trait.new("scared", 1.1)
    + Trait.new("frightened, fearful expression"),

  screaming = Trait.new("screaming, mouth wide open, shouting"),

  -- === Neutral / Composed ===
  serious = Trait.new("serious, stern expression"),

  determined = Trait.new("determined, resolute expression"),

  confident = Trait.new("confident", 1.1)
    + Trait.new("self-assured, strong gaze"),

  expressionless = Trait.new("expressionless, blank stare, neutral face"),

  -- === Compound expressions (multiple tags for nuanced emotion) ===
  -- Combining tags produces more nuanced faces than single tags.
  -- Source: Civitai Danbooru Complex Facial Expressions guide.
  shy_smile = Trait.new("blush, smile", 1.1),

  tearful_smile = Trait.new("teary eyes, smile", 1.1),

  toothy_smile = Trait.new("toothy smile, showing teeth"),

  embarrassed_smile = Trait.new("embarrassed", 1.1)
    + Trait.new("blush, smile, looking away"),

  -- === Micro-expression components ===
  -- Atomic parts for free combination with `+` operator.
  -- Tested in expression_range.lua (seed=7070, novaAnimeXL).
  --
  -- Usage:
  --   C.figure.expression.wink + C.figure.expression.grin
  --   C.figure.expression.puffed_cheeks + C.figure.expression.pout + C.figure.expression.blush

  -- Eye components
  wink = Trait.new("one eye closed"),

  half_closed_eyes = Trait.new("half-closed eyes"),

  -- Mouth components
  pout = Trait.new("pout"),

  parted_lips = Trait.new("parted lips"),

  open_mouth = Trait.new("open mouth"),

  -- Skin / cheek
  blush = Trait.new("blush"),

  puffed_cheeks = Trait.new("puffed cheeks"),

  -- Gaze direction (distinct from pose.looking_away; these are eye-only)
  side_glance = Trait.new("side glance, looking to the side"),

  -- Brow (weaker on SDXL base; more effective on Illustrious/Pony)
  raised_eyebrow = Trait.new("raised eyebrow"),

  furrowed_brow = Trait.new("furrowed brow"),

  -- === Eye state ===
  -- NOTE: closed_eyes is UNRELIABLE on SDXL base. Works better on
  -- anime finetunes. ADetailer may override closed eyes to open.
  -- Consider LoRA assistance for reliable closed-eye generation.
  closed_eyes = Trait.new("closed eyes", 1.2)
    :tag(K.CONFLICTS, "wide eyes"),

  wide_eyes = Trait.new("wide eyes, eyes wide open")
    :tag(K.CONFLICTS, "closed eyes"),

  teary_eyes = Trait.new("teary eyes, watery eyes, glistening eyes", 1.1),

  -- === Quality negatives (for Cast.negative) ===
  -- Teeth/mouth artifact suppression
  bad_teeth = Trait.new("bad teeth, ugly teeth, broken teeth, missing teeth"),

  -- Eye artifact suppression
  bad_eyes = Trait.new("cross-eyed, asymmetrical eyes, uneven eyes"),

  -- Combined face quality negative (covers teeth + eyes + general)
  bad_face = Trait.new("bad teeth, ugly teeth, broken teeth")
    + Trait.new("cross-eyed, asymmetrical eyes")
    + Trait.new("bad mouth, deformed face"),
}
