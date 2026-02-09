--- parametric.lua: Parameterized variation example
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;'..package.path" examples/parametric.lua

local vdsl = require("vdsl")

local w = vdsl.world { model = "sd_xl_base_1.0.safetensors", clip_skip = 2 }
local ugly = vdsl.trait("blurry, ugly, deformed")

-- Base subject (immutable template)
local cat = vdsl.subject("cat")
  :with(vdsl.trait("detailed face", 1.3))
  :quality("high")
  :style("anime")

-- Parameterize: poses x styles
local poses  = { "walking", "sitting", "sleeping", "jumping" }
local styles = { "anime", "photo", "pixel" }

print("=== Single axis: poses ===")
for _, pose in ipairs(poses) do
  local variant = cat:with(pose)
  print(string.format("  [%s] %s", pose, variant:resolve()))
end

print("\n=== Grid: pose x style ===")
local jobs = {}
for _, pose in ipairs(poses) do
  for _, style in ipairs(styles) do
    -- subject base is always clean thanks to immutability
    local variant = vdsl.subject("cat"):with(pose):quality("high"):style(style)
    local cast = vdsl.cast { subject = variant, negative = ugly }
    local result = vdsl.render {
      world = w, cast = { cast },
      seed = 42, steps = 20, size = { 1024, 1024 },
    }
    jobs[#jobs + 1] = { pose = pose, style = style, nodes = result.graph:size() }
  end
end

print(string.format("  Generated %d workflows", #jobs))
for _, j in ipairs(jobs) do
  print(string.format("    %s + %s -> %d nodes", j.pose, j.style, j.nodes))
end

-- LoRA weight sweep
print("\n=== Weight sweep: detail LoRA ===")
for w_val = 0.2, 1.0, 0.2 do
  local cast = vdsl.cast {
    subject = cat:with("walking"),
    lora = { vdsl.lora("add_detail.safetensors", w_val) },
  }
  local r = vdsl.render { world = w, cast = { cast }, seed = 42 }
  -- extract actual weight from compiled graph
  for _, node in pairs(r.prompt) do
    if node.class_type == "LoraLoader" then
      print(string.format("  weight=%.1f -> strength_model=%.1f", w_val, node.inputs.strength_model))
    end
  end
end
