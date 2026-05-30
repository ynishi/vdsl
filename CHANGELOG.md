# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Removed

- **Anchor entity** (`vdsl.anchor`) — the identity-bearing registry layer added
  in 0.4.0 is removed. Identity reuse is now a plain `Subject` plus
  `entity:serialize()` / `Entity.deserialize` (the application owns storage and
  version history). Dropped `lua/vdsl/anchor.lua`, `tests/test_anchor.lua`,
  `docs/anchor-design.md`, `examples/14_anchor.lua`, and the `Cast{anchor=A}`
  adapter. See `docs/entity-architecture.md` §"Why there is no Anchor type" and
  `examples/15_identity_reuse.lua` for the migration. The next release's
  rockspec drops the `vdsl.anchor` module entry accordingly. (`843f085`)

### Added

- **`vdsl.cam{ world, base, shots, negative?, common? }`** — renders a sequence
  of shots through one fixed identity `Subject`. Each shot overlays its per-shot
  `trait` (optionally combined with a shared `common` framing trait) on top of
  the identity via `Subject:with`, then renders and emits one image per shot.
  The render/cast loop shape now lives in exactly one place
  (`lua/vdsl/cam.lua`) instead of being string-templated by host tools. See
  `docs/cam-and-identity.md` and `examples/16_cam_sequence.lua`.
  (`dd0dcb4`, `de61a6e`)

## [0.4.0] - 2026-05-16

### Highlights

Anchor entity — identity-bearing layer that pins a Subject + Variation set
into a named, versioned registry. `train` / `revert` provide append-only
versioning; `Cast{anchor=A}` resolves subject / lora / ipadapter from the
registry's current anchor. JSON roundtrip fidelity via `emit("anchor")` and
`vdsl.anchor.from(t)`.

### Added

- **Anchor entity** (`vdsl.anchor`) — identity-bearing layer that pins a
  Subject + Variation set into a named, versioned registry.
  `AnchorRegistry` maintains an append-only `versions[]` chain;
  `Registry:train(spec)` appends a new `vN` snapshot without mutating
  prior entries; `Registry:revert(tag)` moves only the current pointer.
  (`bb9a850`, `649357a`)
- **`vdsl.anchor.from(t)`** — deserialize a plain table (e.g. loaded from
  JSON) back into a full `AnchorRegistry` with all `SubjectSpec`,
  `AssetSpec`, `variations`, and `training_record` fields intact.
  (`bb9a850`)
- **`Anchor:render(name?)`** — produce a `vdsl.Subject` by applying
  variation overlays through `Subject:with`; direct field assignment that
  bypasses Subject's composition logic is prohibited by design.
  (`bb9a850`)
- **`vdsl.emit("anchor", reg)`** — serialize an `AnchorRegistry` to a
  canonical JSON file (`<name>.json`) via the existing emit backend.
  `from(decode(emit(reg)))` produces a deep-equal Registry (JSON roundtrip
  fidelity). (`8a332c7`)
- **`Cast{anchor=A}` adapter** — pass an `AnchorRegistry` directly to
  `vdsl.cast`; `subject`, `lora`, and `ipadapter` are auto-resolved from
  the registry's current anchor. Explicitly-provided fields take
  precedence (override semantics). (`8a332c7`)
- **`lua/vdsl/anchor.lua`** — single-file implementation of
  `AnchorRegistry` / `Anchor` entities and `M.to_table` / `M.from_table`
  serialization helpers. (`bb9a850`)
- **`tests/test_anchor.lua`** — integration tests: Registry construction,
  `train` / `revert` append-only invariants, `render` via `Subject:with`,
  JSON roundtrip (`from` ↔ `emit`), `Cast{anchor=A}` adapter, and
  backward-compatibility of existing Cast / Subject tests. (`bb9a850`,
  `8a332c7`, `649357a`)
- **`docs/anchor-design.md`** — Core Anchor entity design spec.
  (`d0fbfdf`)

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
