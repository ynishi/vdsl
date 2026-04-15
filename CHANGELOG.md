# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added

- **Profile DSL** (`vdsl.profile` / `vdsl.secret`) — declarative
  ComfyUI-on-pod configuration: ComfyUI ref, Python deps, custom nodes,
  models, env secrets, B2 sync routes, install hooks. Produces a
  canonical JSON manifest (sorted keys, stable array order). Apply is
  orchestrator-driven: the MCP tool `vdsl_profile_apply` expands the
  manifest into a sequence of existing MCP tool calls on the client
  side; the pod runs no convergence script of its own. Source schemes
  for models and sync routes are limited to `b2://` (Backblaze B2) and
  `file://` — stage external assets into B2 before referencing them.
  Model `kind` covers all 20+ ComfyUI `folder_paths.py` directories
  (checkpoints, loras, vae, diffusion_models, text_encoders,
  audio_encoders, model_patches, photomaker, …); `subdir = "<path>"`
  is the escape hatch for custom directories.
- **`docs/profile-and-orchestration.md`** — design doc covering the
  Profile DSL, the generic `vdsl_batch_tools` primitive, the
  `vdsl_profile_apply` composer (phase → step mapping, secret
  resolution, ComfyUI restart + `/object_info` health check), cross-repo
  responsibilities, and explicit non-scope.
- **`examples/11_profile.lua`** — worked B2-only fantasy-preset profile.
- **`tests/test_profile.lua`** — DSL validation and hash-stability tests.

## [0.4.0] - 2026-04-12

### Highlights

Version aligned with vdsl-mcp 0.4.0. Z-Image compiler, catalog desc() API,
Runtime Store abstraction, and directory restructure.

### Added

- **Z-Image compiler** — Turbo/Base variant support with ZSamplerTurbo2 (`e4c832d`, `29ee3a7`)
- **`desc()` API** — natural language descriptions for Trait and all catalogs (`f37cb54`)
- **3-location file sync engine** — Local/Pod/Cloud (`9b8dd1f`)
- **Trait conflict detection** and resolution strategies (`bef1628`)
- **Fantasy cinema showcase** and RunPod setup script (`e41690e`)
- **Cross-language hash verification tests** (`11f467a`)

### Changed

- **Runtime Store abstraction** — replaced Sync engine (`ee25c04`)
- **Sync separated into Domain and Runtime layers** (`bb1dbc5`)
- **`util/png` moved to `runtime/png_default`** — enforce Runtime boundary (`1db134b`)
- **Directory restructure** — workspaces to projects, output as symlink (`6c616c7`)

## [0.2.0] - 2025-12-15

### Added

- Pipeline engine, catalog system, training framework, and runtime abstraction

## [0.1.0] - 2025-11-01

### Added

- Initial LuaRocks release
- Core DSL: Entity, Trait, Subject, World, Stage, Cast, Post
- ComfyUI compiler with graph builder
- PNG-embedded recipe encode/decode
- Theme system (cinema, anime, architecture)
