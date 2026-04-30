--- examples/11_profile.lua
-- Declarative ComfyUI pod configuration via vdsl.profile.
--
-- A Profile captures everything needed to reproduce a ComfyUI environment:
-- ComfyUI version, Python deps, custom nodes, models, env secrets, B2 sync
-- routes, and install hooks. Convergence is done client-side by the MCP
-- tool vdsl_profile_apply — no pod-side convergence script.
--
-- Source schemes are limited to b2:// (Backblaze B2) and file://. Stage
-- external assets into B2 before referencing them here.
--
-- See docs/profile-and-orchestration.md for the orchestration design.
--
-- Usage:
--   lua -e "package.path='lua/?.lua;lua/?/init.lua;'..package.path" \
--       examples/11_profile.lua
--
-- This file just *renders* the manifest; pass it to vdsl_profile_apply
-- via MCP to actually converge a pod.

local vdsl = require("vdsl")

local profile = vdsl.profile {
  name = "fantasy",

  comfyui = {
    ref  = "v0.3.26",
    args = { "--listen", "0.0.0.0", "--port", "8188" },
  },

  python = {
    version = "3.12",
    deps    = { "xformers==0.0.27" },
  },

  system = {
    apt = { "ffmpeg", "git-lfs" },
  },

  custom_nodes = {
    { repo = "ltdrdata/ComfyUI-Manager",    ref = "main" },
    { repo = "Fannovel16/comfyui_controlnet_aux",
      ref  = "main",
      pip  = true },
    { repo = "cubiq/ComfyUI_IPAdapter_plus",
      ref  = "main",
      pip  = true },
  },

  -- Models: kind drives the target subdirectory under ComfyUI/models/.
  -- Every src must be b2:// (pulled via sync) or file:// (already on pod).
  models = {
    { kind = "checkpoint",
      dst  = "sd_xl_base_1.0.safetensors",
      src  = "b2://vdsl-assets/checkpoints/sd_xl_base_1.0.safetensors" },
    { kind = "vae",
      dst  = "sdxl_vae.safetensors",
      src  = "b2://vdsl-assets/vae/sdxl_vae.safetensors" },
    { kind = "lora",
      dst  = "fantasy_style.safetensors",
      src  = "b2://vdsl-assets/loras/fantasy_style.safetensors" },
  },

  -- B2 credentials are MCP-owned and auto-injected into b2:// pull /
  -- push steps at profile_apply time — no `env` block needed here.
  -- (vdsl.secret() was removed 2026-04-21; see lua/vdsl/init.lua.)

  sync = {
    -- Hot cache: bulk-mirror a B2 prefix onto the pod before individual
    -- model steps run. Registered as a sync_route at apply time.
    pull = {
      "b2://vdsl-assets/models/ → /workspace/ComfyUI/models/",
    },
    -- Output offload: registered as a push route; triggered by generation
    -- flows, not by profile apply.
    push = {
      "/workspace/ComfyUI/output/ → b2://vdsl-output/{pod_id}/",
    },
  },

  hooks = {
    post_install = "python -c 'import torch; print(\"cuda=\" .. str(torch.cuda.is_available()))'",
  },
}

-- For inspection / CI: print the canonical manifest in standalone CLI mode.
-- vdsl.profile_emit writes to $VDSL_PROFILE_OUT when invoked via
-- vdsl-mcp's vdsl_profile_apply, otherwise no-op.
vdsl.profile_emit(profile)
print(profile:manifest_json(true))

-- Example: write to disk so a human can eyeball the manifest.
-- profile:write_manifest("/tmp/fantasy_manifest.json")

-- Example: hash used as profile_hash for identity tracking.
-- print(profile:hash_source())

return profile
