#!/usr/bin/env bash
# scripts/new_profile.sh NAME [OUT_PATH]
#
# DEPRECATED (2026-05-06): use the MCP tool `vdsl_profile_init` instead.
#   vdsl_profile_init(name = "<name>")
#     -> <root>/profiles/<name>.lua
#   Root resolution + scaffold body are identical (Rust port of this
#   bash heredoc, see vdsl-mcp domain/profile.rs::scaffold_profile).
#   This bash script is kept as a fallback for users without an MCP
#   client and will be removed in a future release.
#
# Scaffold a new Profile DSL file with the standing prohibition
# header pre-baked. Use this instead of copy-pasting from an existing
# profile so the "no secrets / no DSL-bypass" comments cannot be
# forgotten. See docs/profile-and-orchestration.md §2.4 + §2.5.
#
# Examples:
#   scripts/new_profile.sh my_profile
#     -> projects/profiles/my_profile.lua
#
#   scripts/new_profile.sh my_profile /tmp/scratch.lua
#     -> /tmp/scratch.lua
#
# The scaffolder deliberately omits any credentials / tokens and
# refuses to overwrite an existing file.

set -euo pipefail

if [[ $# -lt 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

NAME="$1"
OUT="${2:-projects/profiles/${NAME}.lua}"

if [[ -e "$OUT" ]]; then
  echo "refuse to overwrite existing file: $OUT" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"

cat > "$OUT" <<LUA
--- ${OUT}
-- <one-line purpose of this profile>
--
-- Standing prohibitions (identical to every profile in this dir):
--   - SECRETS: never declare. MCP auto-injects at apply time.
--   - NO DSL-BYPASS: never hand-roll \`mv\`/\`cp\`/\`rclone\`/\`wget\`/\`curl\`
--     via \`vdsl_exec\` / \`vdsl_task_run\` to paper over DSL gaps.
--     Extend \`lua/vdsl/runtime/profile.lua\` + \`vdsl-mcp
--     profile_service.rs\` instead. See docs/profile-and-orchestration.md
--     §2.4 (secrets) and §2.5 (bypass). Run
--     \`scripts/check_profile_ops.sh\` before committing pod-op changes.
--
-- Target image:
--   runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04
--
-- Staging:
--   List required B2 objects here. User profiles reference
--   \`b2://<bucket>/...\` sources only — stage upstream assets into B2
--   first (never hand-roll wget/curl inside this profile; see §2.5).
--
-- Apply:
--   vdsl_profile_apply(
--     manifest = "${OUT}",
--     pod_id   = "<ephemeral pod id>",
--   )
--
-- Compile check:
--   lua -e "package.path='lua/?.lua;lua/?/init.lua;'..package.path" \\
--       ${OUT}

local vdsl = require("vdsl")

local B2_ROOT = "b2://run-pod-ZQyB"

local profile = vdsl.profile {
  name = "${NAME}",

  comfyui = {
    repo = "comfyanonymous/ComfyUI",
    ref  = "master",
    args = {},
  },

  python = {
    version = "3.12",
    deps    = {},
  },

  system = {
    apt = { "git-lfs" },
  },

  custom_nodes = {
    { repo = "ltdrdata/ComfyUI-Manager" },
    -- add more custom nodes here
  },

  models = {
    -- { kind = "checkpoint",
    --   dst  = "<name>.safetensors",
    --   src  = B2_ROOT .. "/models/checkpoints/<name>.safetensors" },
  },

  -- No \`env\` block: user profiles never carry credentials. Add only
  -- non-secret runtime config (e.g. DEBUG = "1"). Keys matching
  -- KEY/SECRET/TOKEN/PASSWORD/PWD/AUTH/CRED/APIKEY are rejected at
  -- normalize time.

  sync = {
    push = {
      -- "/workspace/ComfyUI/output/ → b2://run-pod-ZQyB/output/{pod_id}/",
    },
  },

  hooks = {
    post_install = [[
python -c "import torch; print('cuda=' + str(torch.cuda.is_available()))"
]],
  },
}

print(profile:manifest_json(true))

return profile
LUA

echo "wrote $OUT"
echo "next:"
echo "  lua -e \"package.path='lua/?.lua;lua/?/init.lua;'..package.path\" $OUT"
