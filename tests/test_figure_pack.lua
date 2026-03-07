--- test_figure_pack.lua: Tests for figure/ pack (pose, expression catalogs).
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;tests/?.lua;'..package.path" tests/test_figure_pack.lua

local vdsl     = require("vdsl")
local Entity   = require("vdsl.entity")
local Catalog  = require("vdsl.catalog")
local T        = require("harness")

print("=== Figure Pack Tests ===")

-- ============================================================
-- Pack lazy-load
-- ============================================================
print("\n--- Pack loading ---")

local catalogs = require("vdsl.catalogs")

T.ok("figure pack loads",       catalogs.figure ~= nil)
T.ok("figure.pose loads",       catalogs.figure.pose ~= nil)
T.ok("figure.expression loads", catalogs.figure.expression ~= nil)

-- ============================================================
-- Pose catalog: all entries are Traits
-- ============================================================
print("\n--- Pose catalog ---")

local pose = catalogs.figure.pose

local pose_expected = {
  "standing", "arms_crossed", "hand_on_hip", "hands_in_pockets",
  "arms_at_sides", "leaning", "contrapposto",
  "sitting", "kneeling", "crouching", "seiza",
  "walking", "running", "jumping", "dynamic_pose", "dancing",
  "stretching", "fighting_stance",
  "lying_down", "lying_on_back", "lying_on_side", "sleeping", "reclining",
  "looking_at_viewer", "looking_back", "looking_up", "looking_down", "looking_away",
  "head_tilt", "arms_behind_back", "peace_sign", "open_arms",
}

for _, name in ipairs(pose_expected) do
  T.ok("pose." .. name .. " exists", pose[name] ~= nil)
  T.ok("pose." .. name .. " is trait", Entity.is(pose[name], "trait"))
end

T.eq("pose entry count", #pose_expected, 32)

-- Verify resolve produces non-empty strings
T.ok("pose.standing resolves",  pose.standing:resolve() == "standing")
T.ok("pose.running has emph",   pose.running:resolve():find("%(running:1.1%)") ~= nil)
T.ok("pose.jumping has emph",   pose.jumping:resolve():find("%(jumping:1.1%)") ~= nil)

-- ============================================================
-- Expression catalog: all entries are Traits
-- ============================================================
print("\n--- Expression catalog ---")

local expr = catalogs.figure.expression

local expr_expected = {
  "smile", "gentle_smile", "laughing", "happy", "excited",
  "angry", "furious", "sad", "crying", "scared", "screaming",
  "serious", "determined", "confident", "expressionless",
  "closed_eyes", "wide_eyes", "teary_eyes",
}

for _, name in ipairs(expr_expected) do
  T.ok("expression." .. name .. " exists", expr[name] ~= nil)
  T.ok("expression." .. name .. " is trait", Entity.is(expr[name], "trait"))
end

T.eq("expression entry count", #expr_expected, 18)

-- Verify resolve produces non-empty strings
T.ok("expr.smile resolves",    expr.smile:resolve():find("smiling") ~= nil)
T.ok("expr.crying has emph",   expr.crying:resolve():find("%(crying:1.2%)") ~= nil)
T.ok("expr.angry resolves",    expr.angry:resolve():find("angry") ~= nil)

-- ============================================================
-- Composability with Subject
-- ============================================================
print("\n--- Composability ---")

local s = vdsl.subject("warrior woman")
  :with(pose.standing)
  :with(pose.arms_crossed)
  :with(expr.serious)

local resolved = s:resolve()
T.ok("compose: has subject",    resolved:find("warrior woman") ~= nil)
T.ok("compose: has standing",   resolved:find("standing") ~= nil)
T.ok("compose: has arms",       resolved:find("arms crossed") ~= nil)
T.ok("compose: has serious",    resolved:find("serious") ~= nil)

-- Composability with camera catalog
local camera = catalogs.camera
local s2 = vdsl.subject("portrait of a girl")
  :with(camera.closeup)
  :with(expr.gentle_smile)
  :with(pose.head_tilt)

local r2 = s2:resolve()
T.ok("compose+camera: has closeup", r2:find("close%-up") ~= nil)
T.ok("compose+camera: has smile",   r2:find("gentle smile") ~= nil)
T.ok("compose+camera: has tilt",    r2:find("head tilt") ~= nil)

-- ============================================================
-- Full pipeline with figure pack
-- ============================================================
print("\n--- Pipeline integration ---")

local w = vdsl.world { model = "model.safetensors" }

local hero = vdsl.cast {
  subject = vdsl.subject("knight")
    :with(pose.fighting_stance)
    :with(expr.determined)
    :quality("high"),
}

local result = vdsl.render {
  world = w,
  cast  = { hero },
  seed  = 42,
  steps = 20,
}

T.ok("pipeline: has json",     #result.json > 100)

local found_subject = false
for _, node in pairs(result.prompt) do
  if node.class_type == "CLIPTextEncode" then
    local text = node.inputs.text
    if text:find("knight") and text:find("fighting stance") and text:find("determined") then
      found_subject = true
    end
  end
end
T.ok("pipeline: figure traits in prompt", found_subject)

-- ============================================================
-- Trait combination (+ operator)
-- ============================================================
print("\n--- Trait combination ---")

local combo = pose.looking_at_viewer + expr.smile
T.ok("combo: is trait",   Entity.is(combo, "trait"))
local combo_text = combo:resolve()
T.ok("combo: has gaze",   combo_text:find("looking at viewer") ~= nil)
T.ok("combo: has smile",  combo_text:find("smiling") ~= nil)

-- ============================================================
-- Non-existent entries return nil (no crash)
-- ============================================================
print("\n--- Safety ---")

T.ok("pose.nonexistent is nil",       pose.nonexistent == nil)
T.ok("expression.nonexistent is nil", expr.nonexistent == nil)
T.ok("figure.nonexistent is nil",     catalogs.figure.nonexistent == nil)

T.summary()
