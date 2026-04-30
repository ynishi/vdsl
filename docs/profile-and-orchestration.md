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
as `vdsl.profile { ... }`. User profiles never declare secrets; MCP
auto-injects credentials into the batch steps that need them (see
§2.4).

### 2.1 Sections

| Section        | Required | Purpose                                           |
|----------------|----------|---------------------------------------------------|
| `name`         | yes      | Profile identifier                                |
| `comfyui`      | no       | `repo`, `ref`, `port`, `args` (Optional since v1.1) |
| `python`       | no       | `version`, `deps[]`                               |
| `system`       | no       | `apt[]`                                           |
| `custom_nodes` | no       | `[{repo, ref, pip, post, name}]`                  |
| `models`       | no       | `[{kind, dst, src}]` — ComfyUI weights, B2 / file |
| `llm_models`   | no       | `[{src, dst_dir, revision}]` — raw LLM weights (HF) |
| `services`     | no       | `[{name, kind, ...}]` — typed daemons (vllm/ollama) |
| `env`          | no       | `{KEY = string|number|boolean}` — non-secret only |
| `sync`         | no       | `{pull = [route], push = [route]}`                |
| `staging`      | no       | `{push = [route]}` — eager pod→B2 one-shot (§2.3) |
| `hooks`        | no       | `{pre_install, post_install, pre_start, post_start}` |

### 2.2 Model kinds

`models[]` is **ComfyUI-only** — entries always stage under
`/workspace/ComfyUI/models/<subdir>/<dst>`. For non-ComfyUI workloads
(vLLM / Ollama / TEI) use `llm_models[]` (§2.7) which targets an
arbitrary `dst_dir` and pulls full HuggingFace repos.

There are two ways to specify the subdirectory:

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
| `face_restore`    | `facerestore_models`    | GFPGAN / CodeFormer weights (`facerestore_cf`) |
| `detector_bbox`   | `ultralytics/bbox`      | Impact Pack YOLO bbox detectors           |
| `detector_segm`   | `ultralytics/segm`      | Impact Pack YOLO segmentation detectors   |

Modern single-weight models (Z-Image Turbo, Flux, SD3 etc.) place UNet
weights under `diffusion_models/` and text encoders under
`text_encoders/` — prefer `diffusion_model` / `text_encoder` kinds over
the legacy `unet` / `clip` paths where the upstream model documents it.

Unknown `kind` values are rejected during normalization. When ComfyUI
adds a new directory that isn't yet in the preset table, use `subdir`
as an immediate escape and file an issue to promote it.

### 2.3 Source schemes

#### `models[].src`

Supports two schemes (ComfyUI weights only):

- `b2://bucket/path` — Backblaze B2 object storage (fetched via `rclone`)
- `file:///absolute/path` — local file already on the pod filesystem (fetched via `cp`)

For HuggingFace pulls (LLM weights), use `llm_models[]` (§2.7) — `models[]`
explicitly rejects `hf://` to keep ComfyUI's canonical layout untainted.

Civitai and direct HTTP(S) are **out of scope** here.
Stage assets into B2 before referencing them from a Profile. Rationale:

- B2 is content-addressed for our pipeline; no separate sha256
  verification is needed at apply time.
- One code path (B2 sync) for all remote assets.
- No per-provider auth / rate-limit handling on the pod.
- Cache locality: the same asset used across pods hits a single B2
  prefix.

#### `sync.pull[]` and `sync.push[]`

Sync routes connect **pod ↔ B2 only**. Both directions use the same two
schemes but pinned by direction:

| Direction     | `src`                          | `dst`                          |
|---------------|--------------------------------|--------------------------------|
| `sync.pull`   | `b2://<bucket>/<path>`         | `/absolute/pod/path`           |
| `sync.push`   | `/absolute/pod/path`           | `b2://<bucket>/<path>`         |

- B2 side **must** use the `b2://` scheme. `file://` is rejected.
- Pod side **must** be an absolute path (`/workspace/...`). Relative
  paths and `..` segments are rejected.
- `{pod_id}` placeholder inside the B2 path is substituted with the
  target pod id at expansion time. Example:
  `"b2://mybucket/output/{pod_id}/"` → `"b2://mybucket/output/<actual_pod_id>/"`.
- No pod-to-pod, pod-to-local, or local-to-local sync is supported
  through Profile. Sync edges that involve the orchestrator's local
  filesystem or another pod use the separate `vdsl_sync` / `sync_route`
  tools directly.

##### Phase 5 execution model

- `sync.pull` runs **at apply time**: each route emits a blocking
  `rclone copyto` step. The pod exits Phase 5 only after every pull
  route has finished. The download is part of pod setup — models and
  input data must be in place before ComfyUI restarts in Phase 9.
- `sync.push` is **registered but not uploaded at apply time**. Each
  route appends a marker line to `/workspace/.vdsl/push_routes.jsonl`
  on the pod. Actual upload happens later (generation flow, output
  flush, scheduled sync), driven by whatever component reads the
  marker file. Apply is for setup; push uploads belong to downstream
  output flows, not bootstrapping.
- `staging.push` runs **eagerly at apply time**, reversed direction
  from `sync.pull`: each route emits a blocking `rclone copyto`
  from the pod absolute path to a `b2://` URI. Distinct from
  `sync.push` on purpose — `staging` is one-shot pre-apply
  upload (HF → pod → B2 staging, ad-hoc artifact capture), while
  `sync.push` is the runtime marker channel. Routes shape:
  `"/workspace/<path> → b2://<bucket>/<path>"`. `{pod_id}` is
  substituted in the B2 path. B2 credentials are emitted as
  `__secret:VDSL_B2_KEY_ID` / `VDSL_B2_KEY` sentinels (§2.4.1).
  All three families share one parallel group (`5_sync_routes`,
  fanout 4); step IDs are `5_sync_pull_N`, `5_sync_push_N`, and
  `5_staging_push_N` respectively.

### 2.4 Secrets are MCP-owned (no sentinel in user Profiles)

**User Profiles never declare secrets. Full stop.** The reason
`vdsl_profile_apply` is an MCP tool — rather than a pure pod-side
script — is exactly so that MCP can look at what a Profile asks for,
figure out which credentials each expanded phase needs, and inject
them itself. Re-deriving that mapping in every user Profile would be
noise at best, a leak vector at worst.

Ownership split:

| Layer       | Knows                                                | Responsibility                                                      |
|-------------|------------------------------------------------------|---------------------------------------------------------------------|
| User Profile| Target stack (models, custom_nodes, env non-secrets) | Declares *what* should end up on the pod                            |
| MCP (Rust)  | Which subprocess needs which credential, and where those credentials live (`.mcp.json` env) | Emits per-step secret sentinels during expansion and resolves them at dispatch |
| Pod         | Nothing about secrets                                | Receives already-resolved values on a single subprocess's env only  |

What user Profiles **may** put in `env`:
- Non-secret runtime config (e.g. `DEBUG = "1"`, `COMFYUI_PORT = 8188`)

What user Profiles **may not** put in `env`:
- Any value via a sentinel helper. `vdsl.secret()` was removed on
  2026-04-21 — there is no helper left, because there is no
  legitimate sentinel to emit from the Lua side.
- Any key containing `KEY`, `SECRET`, `TOKEN`, `PASSWORD`, `PWD`,
  `AUTH`, `CRED`, or `APIKEY` (case-insensitive). Rejected at
  `profile.lua:normalize_env` and (defense in depth) at the
  vdsl-mcp profile_service manifest validator.
- Any pattern that routes credentials off the orchestrator host
  (sourcing `.env`, `grep`-ing keys, inlining values into
  `vdsl_exec` / `vdsl_task_run` commands). If MCP's injection path
  doesn't already cover a credential, the fix is to extend MCP —
  never to bypass it from Lua / shell / task.

### 2.4.1 How MCP injects secrets at apply time

For every expanded BatchPlan step that calls a credential-gated
subprocess, `profile_service` writes sentinels of the form
`{"__secret": "NAME"}` (or the flattened shorthand `__secret:NAME`
inside string values) into that step's `env` only. The current
coverage:

| Phase / step family          | Sentinel(s) emitted                           | Subprocess that consumes them |
|------------------------------|-----------------------------------------------|-------------------------------|
| Phase 7 model pull (b2://)   | `VDSL_B2_KEY_ID`, `VDSL_B2_KEY`               | rclone copyto                 |
| Phase 7b llm_model (hf://)   | `HF_TOKEN` (optional)                         | huggingface-cli download      |
| Phase 5 sync pull (b2://→)   | `VDSL_B2_KEY_ID`, `VDSL_B2_KEY`               | rclone copyto                 |
| Phase 5 staging push (→b2://)| `VDSL_B2_KEY_ID`, `VDSL_B2_KEY`               | rclone copyto                 |
| (future) other schemes       | added here when a new scheme is introduced    | corresponding subprocess      |

The sentinel is the only form that appears in `dry_run` output. On a
real run, `batch_service` replaces each sentinel with
`std::env::var("NAME")` immediately before launching the subprocess
and passes the resolved value through the process env of that single
subprocess — never to `~/.bashrc`, never to a file on the pod, never
to other steps. If any required env var is unset in the MCP process,
the plan fails fast with `MissingSecrets` before the first step
runs.

### 2.4.2 Why not HuggingFace / Civitai tokens?

Out of scope. Stage into B2 beforehand. See §6 Non-scope. This keeps
the secret matrix small (B2 keys only) and avoids a long tail of
per-site auth schemes inside the orchestrator.

### 2.5 No DSL-bypass in apply / setup flow

**Any pod-side file operation that is part of apply / setup /
staging goes through Profile DSL evaluation.** The Profile
(`normalize` in `lua/vdsl/runtime/profile.lua`) and MCP
(`expand_phases` in `vdsl-mcp .../profile_service.rs`) together
define the complete surface of what apply can do on the pod.
Everything else — hand-rolled `mv` / `cp` / `ln` via `vdsl_exec`,
direct `rclone` / `wget` / `curl` calls, piggybacking on
`vdsl_storage_push` by first moving files into its 8 fixed
`MODEL_DIRS` — is prohibited.

Structurally this is the same rule as §2.4 (secrets), seen from a
different angle. §2.4 says "do not control pod from outside the
MCP injection path". §2.5 says "do not control pod file layout
from outside the DSL evaluation path". Both forbid side channels.

If you hit a concrete operation the DSL cannot express, that is
the signal to extend the DSL — not to reach around it. Concrete
examples and their correct routes:

| Symptom                                                        | Do not                                                   | Do                                                                 |
|----------------------------------------------------------------|----------------------------------------------------------|--------------------------------------------------------------------|
| Need to push `/workspace/staging/*` (non-`MODEL_DIRS` path) to B2 | `vdsl_exec mv` into `models/<category>/` then `storage_push` | Extend Profile with a `staging.push` / eager `sync.push` primitive and re-expand Phase 5 |
| Need to pull from a source scheme not yet supported (e.g. `hf://`) | `vdsl_exec wget` / `curl`                                | Extend `models[].src` scheme table in both DSL (`profile.lua`) and MCP (`profile_service.rs`) |
| Model destination dir not in the kind→subdir preset            | `mv` to the nearest preset dir                           | Use `subdir = "relative/path"` escape hatch, or extend `KIND_TO_DIR` |
| Need credentials on the pod other than B2                      | Source `.env` / inline into `vdsl_exec`                  | Extend MCP-side secret injection in `profile_service` and document in §2.4.1 |

Hard rule for AI / Human agents alike: **when a "temporary
workaround" shell sequence suggests itself, stop for 30 seconds and
re-read §2.4 + §2.5 before proceeding.** If the workaround still
feels necessary, that is a design question, not an execution
question — escalate to Human. `scripts/check_profile_ops.sh`
greps staged diffs and the recent git log for the forbidden
patterns and fails loud. Run it before every commit that touches
pod orchestration.

Accident log: 2026-04-21 (see root `.claude/CLAUDE.md` / "Profile
Evaluation Bypass"): an `/workspace/staging/ → B2` push was
attempted by hand-rolling 8 `mv` calls into `MODEL_DIRS` to reuse
`vdsl_storage_push`. Caught at interrupt. Correct fix: add a
`staging.push` primitive to the Profile DSL and let Phase 5
eager-execute it.

### 2.6 Canonical manifest

`profile:manifest_json(pretty)` emits JSON with sorted keys and
stable array order. `profile:hash_source()` returns the compact form
used for identity hashing. Integrity of the manifest is the client's
job; the pod never recomputes it.

### 2.7 LLM models (`llm_models[]`)

Raw weight staging for non-ComfyUI workloads (vLLM / Ollama / TEI etc.).
Independent of `models[]` so ComfyUI's `subdir` / `kind` semantics don't
bleed into LLM staging.

```lua
llm_models = {
  { src = "hf://meta-llama/Llama-3-8B-Instruct",
    dst_dir = "/root/models/llama-3" },
  { src = "hf://Qwen/Qwen3-7B",
    dst_dir = "/root/models/qwen-3",
    revision = "v1.2.0" },  -- optional git ref / branch / tag
}
```

- `src` must use `hf://<org>/<repo>` (only scheme currently supported).
- `dst_dir` must be an absolute pod path. The full HF repo is materialized
  there via `huggingface-cli download --local-dir`.
- `revision` (Optional) passes through to `--revision`.
- `HF_TOKEN` is injected from the MCP process env when set; missing token
  is fine for public repos (private repos fail at `huggingface-cli` time).

### 2.8 Services (typed daemons)

Adjacent daemon services launched in Phase 11. Closed enum design:
each entry selects a `kind` (currently `"vllm"` or `"ollama"`); the
launch shell command is generated from the typed fields. **No
free-form `cmd` string** — adding a new platform requires extending
both `vdsl-mcp::ServicePlatform` and `profile.lua::SERVICE_KIND_NORMALIZERS`.

```lua
services = {
  {
    name                 = "vllm",
    kind                 = "vllm",
    model                = "/root/models/qwen-awq",  -- HF repo id or local path
    port                 = 8188,
    dtype                = "auto",                   -- optional
    tensor_parallel_size = 1,                        -- optional
    extra_args           = { "--max-model-len 16384" },  -- escape hatch
    ready_check = {
      http        = "http://localhost:8188/v1/models",
      timeout_sec = 600,
    },
  },
  {
    name   = "ollama",
    kind   = "ollama",
    port   = 11434,
    models = { "llama3:8b" },  -- pre-pull list (info only; pull is operator's job)
  },
}
```

- Launch step runs `nohup <cmd> > /workspace/.vdsl/service_<name>.log 2>&1 &`,
  then `sleep 1 && kill -0 $pid` to detect immediate-exit failures
  (binary missing, arg parse error).
- `ready_check` (Optional) performs a bounded HTTP poll on `http` URL
  until 200 OK or `timeout_sec` (default 300).
- Service `name` must be unique within the profile (collides on log
  file path otherwise).

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

### 4.0 Dispatch mode: polling (default) vs synchronous dry-run

- `dry_run=true` runs synchronously and returns the compiled
  `BatchPlan` + per-step dry results. No SSH hits the pod.
- `dry_run=false` runs **asynchronously**. The call returns
  `{ task_id, pod_id, status: "running", poll_with }` in under a
  second; the dispatch continues in a background `tokio::spawn`.
  The caller polls with:
  ```
  vdsl_profile_apply_status({ task_id })
    → { status ∈ "running" | "ok" | "failed",
        total_steps, completed_steps,
        current_step,
        results[], started_at_ms, finished_at_ms, error? }
  ```
  Polling is cheap (in-process memory, no SSH). Terminal entries
  persist in the registry for the MCP process lifetime — late
  pollers still read the full result.

Why the split: a cold-pod apply takes 15-20 min (venv + pip +
custom-node installs + multi-GB model pull). Single-call
synchronous dispatch previously blocked the MCP tool for that
entire window, with no progress signal. A dropped SSH channel
would leave the caller stuck for the per-step 3600s timeout even
after the pod-side work finished (see `.claude/CLAUDE.md`
2026-04-22 "45 min stuck" accident record). The polling pattern
decouples the MCP call from the long-running work and lets the
caller verify liveness at any time.

Heavy phases internally dispatch via `exec_bg` (see §4.3), which
launches the step via `runpod-cli task run` (detached) and polls
`task status` from MCP instead of holding a single SSH channel
open for the duration. SSH is only held briefly per launch +
per-status-poll.

### 4.1 Phase → step mapping (default order, `seq` mode)

| # | Phase                    | Tool(s)                   | Notes                                    |
|---|--------------------------|---------------------------|------------------------------------------|
| 1 | `system.apt`             | `exec_bg`                 | single shell line                        |
| 2 | `comfyui` install        | `exec_bg`                 | clone / checkout / venv / requirements.txt |
| 3 | `python.deps`            | `exec_bg`                 | venv pip install                         |
| 4 | `custom_nodes`           | `exec_bg` × N             | one step per node (parallel ≤4); `pip=true` installs `requirements.txt` with torch-family filter (see §4.3) |
| 5 | `sync.pull` / `staging.push` / `sync.push` | `exec_bg` × N (pull / staging) + `exec` (marker) | pull / staging: rclone copyto via detached task; marker: single `printf >> /workspace/.vdsl/push_routes.jsonl` (fast; stays on `exec`) |
| 6 | *(unused)*               | —                         | Phase 6 intentionally vacant; marker-based push has no poll step |
| 7 | `models`                 | `exec_bg` (`rclone` or `cp`) | `b2://` → rclone copyto (serial), `file://` → cp |
| 8 | `hooks.post_install`     | `exec_bg`                 | if present                               |
| 9 | ComfyUI restart          | `exec_bg` (polling)       | kill port listener + nohup relaunch + wait for HTTP |
|10 | health check             | `comfy_api` GET `/object_info` | confirms node graph loaded fully    |
|7b | llm_models pull          | `exec_bg` (serial)        | huggingface-cli download (HF_TOKEN if set) |
|11 | services                 | `exec_bg` (detached) + poll | launches `services[]` from typed platform + polls `ready_check.http` |

`sync.push` upload itself is **not triggered** during apply; only the
marker file is written. Upload belongs to downstream output flows
(generation completion, scheduled flush) that consume the marker.

### 4.2 ComfyUI restart

Phase 9 is a single `exec_bg` step (detached via `task_run`, polled
via `task_status`). The restart script itself polls `curl` on
`localhost:<port>` until the server answers, so when the task
reaches `done` state, the health check in Phase 10 can fire
without a race. The script:

1. Ensure `ss` (iproute2) is installed — auto-installs if missing.
2. Discover the actual port-8188 listener via `ss -ltnpH "sport = :$PORT"`, extract PIDs, send SIGTERM (excluding `$$` and `$PPID`).
3. Wait up to 30 s for the port to free, escalating to SIGKILL at the 10 s mark.
4. `mkdir -p /workspace/.vdsl` — ensure log destination exists.
5. `nohup .venv/bin/python main.py <args> > /workspace/.vdsl/comfyui.log 2>&1 &`.
6. Poll `http://localhost:<port>/` until it responds (bounded 180 s).

Four subtle bugs had to be fixed in this script before it was stable;
the current form encodes all of them:

- **Listener-PID kill over argv pattern.** Pod images often start
  ComfyUI via system python (`/usr/bin/python3.12 main.py ...`, e.g.
  the `runpod-slim` auto-start). An earlier pattern
  `pgrep -f '[.]venv/bin/python main\.py'` missed that entirely —
  the pre-installed ComfyUI survived the restart, grabbed the port
  first, and apply silently pointed at a models-less instance. The
  current form resolves the listener by querying `ss -ltnp` on
  `$PORT`, so any process actually bound to the port is killed
  regardless of how it was launched.
- **Self-exclude from kill.** `$$` (this shell) and `$PPID` (ssh-level
  parent) are filtered out so the script cannot accidentally kill its
  own ancestors.
- **Port-free wait via `ss`, with auto-install.** The RunPod base
  images we target do not all ship `lsof` or `ss` out of the box.
  Earlier loops using `lsof` short-circuited with "command not
  found"; newer pods without iproute2 triggered the same silent skip
  for `ss`. The script now checks `command -v ss` and runs
  `apt-get install -y iproute2` idempotently before the kill loop.
- **SIGKILL escalation.** If a listener ignores SIGTERM (wedged
  install supervisor, runaway venv), the SIGKILL fallback at the
  10 s mark ensures the port frees within the 30 s deadline.

Running the restart as `exec_bg` means the long 180 s HTTP-ready
wait happens on the pod, in a detached task, while MCP only issues
short polling SSH calls. This matters even more post-restart: the
ComfyUI boot fetches ComfyUI-Manager registries and can briefly
wedge SSH on a slow network.

### 4.3 Custom-node pip with torch-family filter

Phase 4 runs, for each node with `pip = true`:

```sh
if [ -f /workspace/ComfyUI/custom_nodes/<name>/requirements.txt ]; then
  grep -viE '^[[:space:]]*(torch|torchvision|torchaudio|xformers|bitsandbytes|triton)([[:space:]=<>~!;]|$)' \
    /workspace/ComfyUI/custom_nodes/<name>/requirements.txt \
    | /workspace/ComfyUI/.venv/bin/pip install -r /dev/stdin;
fi
```

The grep filter drops `torch` / `torchvision` / `torchaudio` /
`xformers` / `bitsandbytes` / `triton` lines before piping to pip.
Rationale: RunPod images ship a CUDA-driver-pinned torch (e.g.
`torch==2.5.1+cu124` on driver 550.127). Unfiltered custom-node
requirements can pull a newer torch (Impact Pack requested
`torch==2.11.0`), which loads fine at import but fails on first CUDA
call with `driver too old (found 12040)` — silently breaking every
downstream sampler. The filter preserves the image's torch while
installing everything else the node actually needs (`segment-anything`,
`ultralytics`, `piexif`, etc.).

If a node genuinely needs a different torch, don't set `pip = true`;
handle it via `hooks.post_install` with an explicit
`--index-url https://download.pytorch.org/whl/cu<major>` pin.

### 4.3 Health check

`comfy_api` hitting `/object_info` (not `/queue`). `/queue` returns
200 as soon as the HTTP server is up, but node classes may still be
loading; `/object_info` does not respond cleanly until the full
registry is populated. A green `/object_info` is the contract for
"ready to accept workflows".

### 4.4 Secret resolution (MCP-internal only)

Sentinels in step `env` are never user-supplied — `profile_service`
emits them during manifest → BatchPlan expansion (see §2.4.1). They
are resolved by `batch_service` right before dispatching each step:

1. For each key whose value matches `{"__secret": "NAME"}` or the
   flat form `"__secret:NAME"`, call `std::env::var("NAME")` on the
   MCP process env.
2. Any missing variable aborts the plan with `MissingSecrets` before
   the first step runs. No partial execution.
3. Resolved values land on the launched subprocess's env and nowhere
   else — not in `~/.bashrc`, not in a file on the pod, not in
   another step's env.
4. `dry_run` shows the sentinel form verbatim. Real runs never echo
   resolved values back through tool output.

User-facing manifests that somehow carry a `__secret` key
(hand-written JSON, third-party loader, etc.) are rejected at
profile_service parse time — defense in depth for the Lua-side
validator in `profile.lua:normalize_env`.

## 5. Cross-repo responsibilities

| Repo       | Owns                                                                 |
|------------|----------------------------------------------------------------------|
| `vdsl`     | Profile DSL, manifest schema, canonical JSON, env-secret rejection at normalize (Lua-side enforcement) |
| `vdsl-mcp` | `batch_tools` primitive, `profile_apply` composer, tool dispatch, **per-step `__secret` sentinel emission + resolution**, env-secret rejection at manifest parse (Rust-side enforcement), restart/health helpers |

Schema changes in `profile.lua` require a matching update in
`vdsl-mcp`'s manifest parser. Follow the cross-repo rule from the
root `CLAUDE.md`: grep for hard-coded `require("vdsl.runtime.profile")`
or JSON-schema string constants and update them in the same PR.

## 5.1 Reference profiles

Reusable profiles live under `projects/profiles/` (gitignored user area;
check in per-project). The expected flow for a new ephemeral pod on the
RunPod pytorch base (`runpod/pytorch:*-devel`) is:

1. `vdsl_pod_create` with the pytorch image + desired GPU.
2. `vdsl_profile_apply(manifest = "projects/profiles/<name>.lua", pod_id = ...)`.
3. `vdsl_connect(pod_id = ..., wait = true)` once the health check passes.

| Profile                                      | Stack                                                              | Notes                                          |
|----------------------------------------------|--------------------------------------------------------------------|------------------------------------------------|
| `projects/profiles/zimage_turbo.lua`         | ComfyUI + ZImagePowerNodes + Z-Image Turbo                          | Mirrors `scripts/infra/setup_comfyui_pod.sh`'s Python-3.12-on-pytorch approach; weights pulled from B2. |
| `projects/profiles/sdxl_illustrious.lua`     | ComfyUI + Impact Pack + Illustrious SDXL checkpoint                 | Base SDXL pod (txt2img + FaceDetailer only). No LoRA/ControlNet/IPAdapter — those layer on via `pipeline_*`. |
| `projects/profiles/pipeline_i2i_sdxl.lua`    | Superset of `sdxl_illustrious` + ControlNet aux + IPAdapter + KJNodes + post-processing | Complex I2I flows: img2img / ControlNet (canny/depth/openpose) / IPAdapter vit-h / 4x-UltraSharp / SAM inpaint. See `projects/profiles/pipeline_i2i_sdxl_staging.md` for the B2 staging map (upstream → `b2://run-pod-ZQyB/...`). |

`pipeline_*` profiles are idempotent supersets: applying
`pipeline_i2i_sdxl.lua` on a pod that already has `sdxl_illustrious`
only adds the extra custom_nodes and model weights. Missing B2 objects
do **not** fail `profile_apply` (models[] is skip-if-exists per file);
the downstream workflow referencing that model fails at runtime
instead. Consult the paired `*_staging.md` before apply.

Profiles replace the legacy `scripts/infra/setup_comfyui_pod.sh` manual
path: that script still works for the pre-seeded network volume case,
but new ephemeral pods should converge via `vdsl_profile_apply`.

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
