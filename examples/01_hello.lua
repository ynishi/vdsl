--- 01_hello.lua: Minimal vdsl example
-- Compile a single image workflow. No server required.
--
-- Model is resolved from config (workspaces/config.lua, .vdsl/config.lua, or VDSL_MODEL env).
-- Or pass explicitly: vdsl.world { model = "your_model.safetensors" }
--
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;'..package.path" examples/01_hello.lua

local vdsl = require("vdsl")

-- World: generative foundation (model, VAE, CLIP skip)
local w = vdsl.world {
  clip_skip = 2,
}

-- Cast: who/what appears in the image
local hero = vdsl.cast {
  subject  = "warrior woman, silver armor, dynamic pose, detailed face",
  negative = "blurry, low quality, deformed, ugly",
}

-- Render: compile to ComfyUI workflow JSON
local result = vdsl.render {
  world   = w,
  cast    = { hero },
  sampler = "euler_ancestral",
  steps   = 30,
  cfg     = 7.5,
  seed    = 42,
  size    = { 1024, 1024 },
}

vdsl.emit("warrior_scene", result)

print("=== Hello vdsl ===")
print(string.format("  model: %s", w.model))
print(string.format("  nodes: %d", result.graph:size()))
print(string.format("  seed:  %d", 42))
print("\nWorkflow JSON compiled. Pass to ComfyUI or use scripts/runner.lua to execute.")
