# Profile & Orchestration

Declarative ComfyUI-on-pod configuration, applied via MCP
orchestration on the client side.

## 1. Overview

Profile is a declarative manifest describing how a ComfyUI-on-pod
should be set up: ComfyUI repo/ref, Python deps, custom nodes, models,
env secrets, B2 sync routes, install hooks. It is applied by the
client-side composer tool `vdsl_profile_apply`, which expands the
manifest into a sequence of existing MCP tool calls
(`pod_exec_script`, `sync`, `sync_route`, `comfy_api`) via a small
generic primitive `vdsl_batch_tools`.

### Design principles

- **Orchestrator-driven.** Convergence lives on the client. The pod
  is dumb: a `pod_exec_script` target that runs whatever the
  orchestrator sends, and a sync target that pulls what the
  orchestrator tells it to pull. No pod-side convergence script, no
  pod-side `state.json`.
- **B2-first data plane.** Models, datasets, and outputs live in
  Backblaze B2; the pod only needs file-level sync. Profiles reference
  only `b2://` or `file://` sources.
- **Reuse, don't reimplement.** Every phase maps to an existing MCP
  tool (`pod_exec_script`, `sync`, `sync_route`, `comfy_api`) that is
  already idempotent and well-tested. `profile_apply` is a thin
  composer, not a new execution engine.

## 2. Profile DSL

Defined in `lua/vdsl/runtime/profile.lua`. Exposed on the public API
as `vdsl.profile { ... }` and `vdsl.secret("NAME")`.

### 2.1 Sections

| Section        | Required | Purpose                                           |
|----------------|----------|---------------------------------------------------|
| `name`         | yes      | Profile identifier                                |
| `comfyui`      | yes      | `repo`, `ref`, `port`, `args`                     |
| `python`       | no       | `version`, `deps[]`                               |
| `system`       | no       | `apt[]`                                           |
| `custom_nodes` | no       | `[{repo, ref, pip, post, name}]`                  |
| `models`       | no       | `[{kind, dst, src}]` — B2 / file only (see §2.2)  |
| `env`          | no       | `{KEY = string | vdsl.secret("NAME")}`            |
| `sync`         | no       | `{pull = [route], push = [route]}`                |
| `hooks`        | no       | `{pre_install, post_install, pre_start, post_start}` |

### 2.2 Model kinds

Each model entry targets a subdirectory under `ComfyUI/models/`. There
are two ways to specify it:

- `kind = "<preset>"` — pick a preset from the table below.
- `subdir = "<relative/path>"` — escape hatch for directories not in
  the preset list (new ComfyUI folders, custom-node-specific trees,
  etc.). Must be a relative path without `..` or backslashes.

`kind` and `subdir` are mutually exclusive; exactly one is required.

| `kind`            | subdirectory            | typical use                               |
|-------------------|-------------------------|-------------------------------------------|
| `checkpoint`      | `checkpoints`           | Full SD checkpoints (UNet+CLIP+VAE)       |
| `lora`            | `loras`                 | LoRA / LyCORIS                            |
| `vae`             | `vae`                   | VAE                                       |
| `controlnet`      | `controlnet`            | ControlNet / T2I-Adapter                  |
| `clip`            | `clip`                  | CLIP text encoder (legacy path)           |
| `clip_vision`     | `clip_vision`           | CLIP Vision (IPAdapter / Revision)        |
| `upscale`         | `upscale_models`        | ESRGAN / RealESRGAN                       |
| `embedding`       | `embeddings`            | Textual Inversion                         |
| `unet`            | `unet`                  | UNet single weights (legacy path)         |
| `diffusion_model` | `diffusion_models`      | UNet/DiT single weights (Flux, SD3, Z-Image) |
| `text_encoder`    | `text_encoders`         | T5 / CLIP-L / CLIP-G single (Flux, SD3, Z-Image) |
| `gligen`          | `gligen`                | GLIGEN bbox grounding                     |
| `hypernetwork`    | `hypernetworks`         | Hypernetwork (legacy)                     |
| `style`           | `style_models`          | Style adapters (e.g. Flux Redux)          |
| `diffusers`       | `diffusers`             | HF diffusers folder format                |
| `ipadapter`       | `ipadapter`             | IPAdapter weights (custom-node registered)|
| `audio_encoder`   | `audio_encoders`        | Audio encoders (video/audio pipelines)    |
| `model_patch`     | `model_patches`         | Diff-patch weights (e.g. Flux Kontext)    |
| `photomaker`      | `photomaker`            | PhotoMaker ID embeddings                  |
| `vae_approx`      | `vae_approx`            | TAESD / TAESDXL preview VAE               |
| `latent_upscale`  | `latent_upscale_models` | Latent-space upscalers                    |
| `classifier`      | `classifiers`           | Classifiers (NSFW detection etc.)         |
| `config`          | `configs`               | Model YAML configs                        |

Modern single-weight models (Z-Image Turbo, Flux, SD3 etc.) place UNet
weights under `diffusion_models/` and text encoders under
`text_encoders/` — prefer `diffusion_model` / `text_encoder` kinds over
the legacy `unet` / `clip` paths where the upstream model documents it.

Unknown `kind` values are rejected during normalization. When ComfyUI
adds a new directory that isn't yet in the preset table, use `subdir`
as an immediate escape and file an issue to promote it.

### 2.3 Source schemes (models + sync routes)

**Only two schemes are supported**:

- `b2://bucket/path` — Backblaze B2 object storage
- `file://absolute/path` — local file already on the pod filesystem

HuggingFace, Civitai, and direct HTTP(S) are **out of scope**. Stage
assets into B2 before referencing them from a Profile. Rationale:

- B2 is content-addressed for our pipeline; no separate sha256
  verification is needed at apply time.
- One code path (B2 sync) for all remote assets.
- No per-provider auth / rate-limit handling on the pod.
- Cache locality: the same asset used across pods hits a single B2
  prefix.

### 2.4 Secret sentinel

`vdsl.secret("HF_TOKEN")` returns `{ __secret = "HF_TOKEN" }`. The
manifest records the reference, not the value. Resolution happens in
the orchestrator at apply time from the caller's environment (e.g.
RunPod pod-level secrets, a local `.env`, or explicit CLI flags).

### 2.5 Canonical manifest

`profile:manifest_json(pretty)` emits JSON with sorted keys and
stable array order. `profile:hash_source()` returns the compact form
used for identity hashing. Integrity of the manifest is the client's
job; the pod never recomputes it.

## 3. `vdsl_batch_tools` (primitive)

A generic composition tool in `vdsl-mcp`. Not Profile-specific — use
it wherever a sequence of MCP tool calls needs to run as a unit.

```
vdsl_batch_tools({
  mode: "seq" | "dag",
  steps: [
    {
      id: "apt",
      tool: "pod_exec_script",
      args: { ... },
      depends_on: ["..."],     # dag mode only
      validate: {              # optional, post-success check
        file_exists: ["/path/to/file"],
        min_size: 1024,
      },
    },
    ...
  ],
  dry_run: false,
})
→ { results: [{ id, status, output | error }, ...] }
```

### 3.1 Modes

- `seq` (default): execute `steps` strictly in array order, stop on
  first failure.
- `dag`: topological sort on `depends_on`, parallel fan-out where
  independent. Cycles are a usage error.

### 3.2 Validate + retry

Retries are off by default. When a step has a `validate` block, the
runner performs:

1. execute the tool
2. run the validate checks
3. if checks fail: execute the tool once more, re-check, then give up

This is sized for `sync` steps where the underlying transport can
flake mid-stream but the operation is otherwise idempotent. `apt` /
`git clone` style steps do not need this — they are re-run cheaply
but the failure mode is a hard error, not a content check.

Available validators:

- `file_exists: [path, ...]` — all paths must exist on the pod
- `min_size: bytes` — each checked file must be at least this big

Keep validators minimal. Resist adding generic shell checks — if you
want that, write a separate verification step.

### 3.3 Dry-run

`dry_run: true` emits the full plan (each step with its fully
resolved `args`) and exits without executing. Secrets in `env` are
redacted; everything else is shown verbatim.

## 4. `vdsl_profile_apply` (composer)

Reads a Profile manifest and expands it into a `batch_tools` plan.

```
vdsl_profile_apply({
  manifest: "<path> | { ...inline JSON... }",
  pod_id: "...",
  dry_run: false,
})
```

### 4.1 Phase → step mapping (default order, `seq` mode)

| # | Phase                    | Tool(s)                   | Notes                                    |
|---|--------------------------|---------------------------|------------------------------------------|
| 1 | `system.apt`             | `pod_exec_script`         | single shell line                        |
| 2 | `comfyui` install        | `pod_exec_script`         | clone / checkout / venv / requirements.txt |
| 3 | `python.deps`            | `pod_exec_script`         | venv pip install                         |
| 4 | `custom_nodes`           | `pod_exec_script` × N     | one step per node (sequential)           |
| 5 | `sync_route` register    | `sync_route`              | one per `sync.pull` + `sync.push`; idempotent |
| 6 | `sync.pull`              | `sync` × N                | `validate: file_exists` on a canary path |
| 7 | `models`                 | `sync` or `pod_exec_script` (`cp`) | `b2://` → sync, `file://` → cp  |
| 8 | `hooks.post_install`     | `pod_exec_script`         | if present                               |
| 9 | ComfyUI restart          | `pod_exec_script` (polling) | kill + nohup relaunch in one script    |
|10 | health check             | `comfy_api` GET `/object_info` | confirms node graph loaded fully    |

`sync.push` routes are **registered but not triggered** during apply.
Triggering belongs to generation / output flows, not setup.

### 4.2 ComfyUI restart

Pod-side restart is a single `pod_exec_script` invocation that:

1. `pkill -f ComfyUI/main.py || true`
2. waits for the port to free
3. `nohup .venv/bin/python main.py <args> > /workspace/.vdsl/comfyui.log 2>&1 &`
4. polls `http://localhost:<port>/` until it responds

The polling mode of `pod_exec_script` is what makes this a single
step rather than a kill-then-sleep-then-check chain.

### 4.3 Health check

`comfy_api` hitting `/object_info` (not `/queue`). `/queue` returns
200 as soon as the HTTP server is up, but node classes may still be
loading; `/object_info` does not respond cleanly until the full
registry is populated. A green `/object_info` is the contract for
"ready to accept workflows".

### 4.4 Secret resolution

Secrets referenced in `env` are resolved by the orchestrator before
the plan is sent to `batch_tools`:

1. `env[KEY] = { __secret = "NAME" }` → look up `NAME` from the
   orchestrator's environment (caller's secrets store / shell env).
2. If unset, `profile_apply` fails fast before any step runs.
3. Resolved values are inlined into the relevant `pod_exec_script`
   step's env. They never appear in `dry_run` output.

## 5. Cross-repo responsibilities

| Repo       | Owns                                                                 |
|------------|----------------------------------------------------------------------|
| `vdsl`     | Profile DSL, manifest schema, canonical JSON, `vdsl.secret` sentinel |
| `vdsl-mcp` | `batch_tools` primitive, `profile_apply` composer, tool dispatch, secret resolution, restart/health helpers |

Schema changes in `profile.lua` require a matching update in
`vdsl-mcp`'s manifest parser. Follow the cross-repo rule from the
root `CLAUDE.md`: grep for hard-coded `require("vdsl.runtime.profile")`
or JSON-schema string constants and update them in the same PR.

## 6. Non-scope

Explicitly **not** handled by this design:

- HuggingFace / Civitai / direct HTTP(S) downloads. Stage into B2.
- `sha256` field on models. B2 is content-addressable for our needs;
  if cryptographic pinning ever becomes required, add it as an
  explicit validator, not a silent check.
- Pod-side `state.json` / `profile_hash` tracking. The manifest itself
  is the source of truth; re-applying the same manifest is a no-op by
  way of step-level idempotency.
- Starting ComfyUI "for good" as a daemon. `profile_apply` restarts
  ComfyUI as the final step of apply. Long-term supervision (systemd
  / tmux / RunPod start command) is the user's call.
- `pre_start` / `post_start` hooks. They exist in the schema as
  reserved keys but are not run by `profile_apply`. Document when you
  actually wire them.
