# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

## [0.3.0] - 2026-05-06

### Highlights

Profile DSL — declarative ComfyUI / vLLM / Ollama on-pod configuration with
canonical JSON manifest, MCP-driven apply, B2-first sync, and explicit
secret / bypass prohibitions.

### Added

- **Profile DSL** (`vdsl.profile`) — declarative pod configuration:
  ComfyUI ref (optional), Python deps, custom nodes, models, env, B2 sync
  routes, install hooks, restart phase. Produces a canonical JSON
  manifest (sorted keys, stable array order, SHA256 = `profile_hash`).
  Apply is orchestrator-driven: `vdsl_profile_apply` expands the manifest
  into a sequence of MCP tool calls on the client side; the pod runs no
  convergence script of its own. (`f612760`)
- **Model `kind` extended** to cover all 20+ ComfyUI `folder_paths.py`
  directories (checkpoints, loras, vae, diffusion_models, text_encoders,
  audio_encoders, model_patches, photomaker, …). `subdir = "<path>"` is
  the escape hatch for custom directories. Custom-node `pip` filter
  documented. (`62790d9`)
- **`staging.push` primitive** — push host files to pod staging with
  fail-fast secret rejection. Secret-shaped keys
  (KEY/SECRET/TOKEN/PASSWORD/PWD/AUTH/CRED/APIKEY) are rejected at
  `normalize_env`; bypass via shell / task_run is prohibited at the
  policy level. (`f921846`)
- **ComfyUI optional** — Profile no longer requires `comfyui {}` block;
  pure-Python / vLLM / Ollama-only profiles are valid. Polling-style
  `vdsl_profile_apply` documented (background spawn + `task_id` poll;
  SSH 45min stuck mitigation via `exec_bg`). (`51cd595`)
- **`vdsl.profile_emit`** — env-driven manifest output for MCP (replaces
  `vdsl.secret`-style host-side secret embedding). (`8256d2e`)
- **`llm_models[]` + typed services** (`services.vllm`, `services.ollama`)
  — first-class LLM serving alongside ComfyUI image generation.
  (`170c416`)
- **`python.force_reinstall`** pass-through to pip (`6cc00df`)
- **vLLM Profile factory** — `vdsl.profile.vllm{...}` preset builder
  with GPU presets doc (`docs/vllm-gpu-presets.md`). 4090 22.5 GiB args
  tuned for `examples/12_vllm`. (`952b185`, `056e433`)
- **`docs/profile-and-orchestration.md`** — design doc: Profile DSL,
  `vdsl_batch_tools` primitive, `vdsl_profile_apply` composer
  (phase → step mapping, secret resolution, ComfyUI restart +
  `/object_info` health check), cross-repo responsibilities, explicit
  non-scope. Sync routes are URL-scheme (B2/file only, pod ↔ B2 path).
  Restart script uses `ss-wait` + `pkill` self-exclude. (`5a33151`,
  `3b2743e`)
- **Examples** — `examples/11_profile.lua` (fantasy-preset),
  `examples/12_vllm.lua` (vLLM serving). (`4559f73`)
- **Tests** — `tests/test_profile.lua` (DSL validation, hash stability,
  factory shape).

### Changed

- `examples/11_profile.lua` — drop residual `vdsl.secret` calls, switch
  to `profile_emit` (`4559f73`).

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
