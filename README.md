# vdsl

Visual DSL for ComfyUI. Pure Lua. Zero runtime dependencies for DSL and compilation.
Server execution (`connect`/`run`) requires `curl` or a custom HTTP backend.

Transforms semantic scene composition into ComfyUI node graphs.
Images become portable project files through PNG-embedded recipes.

## Install

```bash
luarocks install vdsl
```

For pod-side orchestration (Profile DSL apply, model sync, batch
generation), [**vdsl-mcp**](https://github.com/ynishi/vdsl-mcp) is
required as the companion MCP server. The Lua side emits canonical
manifests; vdsl-mcp expands them into MCP tool calls (`vdsl_profile_apply`,
`vdsl_project_init`, `vdsl_run_script`, …) on the client side.

## Quick Start

```lua
local vdsl = require("vdsl")

local w = vdsl.world {
  model     = "sd_xl_base_1.0.safetensors",
  clip_skip = 2,
}

local hero = vdsl.cast {
  subject  = "warrior woman, silver armor, dynamic pose",
  negative = "blurry, low quality, deformed",
  lora = {
    { name = "add_detail.safetensors", weight = 0.7 },
  },
}

local result = vdsl.render {
  world = w,
  cast  = { hero },
  steps = 30,
  cfg   = 7.5,
  seed  = 42,
  size  = { 1024, 1024 },
}

print(result.json)
```

## Concepts

| Concept | Entity | ComfyUI Mapping |
|---------|--------|-----------------|
| Universe rules | **World** | Checkpoint, VAE, CLIP Skip |
| Who/what | **Cast** | CLIP Encode, LoRA, IPAdapter |
| Where/how | **Stage** | ControlNet, img2img |
| Post-processing | **Post** | Upscale, Face Restore, Color |
| Atomic prompt | **Trait** | Prompt text fragment |
| Identity | **Subject** | Composed Trait chain |
| Reusable set | **Catalog** | Named Trait dictionary |
| Preset bundle | **Theme** | Defaults + negatives + traits |

All entities are **immutable**. Every mutation returns a new instance.

## Features

- **Compile** -- `vdsl.render()` produces a ComfyUI-compatible prompt JSON
- **Themes** -- Built-in presets (cinema, anime, architecture) with lazy loading
- **Embed** -- `vdsl.embed()` writes recipe + prompt into PNG tEXt chunks
- **Import** -- `vdsl.import_png()` reads back vdsl recipes or decodes ComfyUI prompts
- **Registry** -- `vdsl.connect()` queues jobs to a running ComfyUI instance
- **Run** -- `vdsl.run()` full pipeline: compile, queue, poll, download, embed
- **Profile** -- `vdsl.profile{}` declares the whole pod (ComfyUI / vLLM / Ollama,
  models, custom nodes, sync routes) as a canonical JSON manifest

## Profile DSL (pod configuration)

`vdsl.profile{}` describes a reproducible ComfyUI / vLLM / Ollama pod
declaratively: ComfyUI ref, Python deps, custom nodes, models, B2 sync
routes, env, and install hooks. Output is a canonical JSON manifest
(SHA256 = `profile_hash`).

```lua
local vdsl = require("vdsl")

local profile = vdsl.profile {
  name = "fantasy",

  comfyui = { ref = "v0.3.26" },        -- optional: omit for vLLM/Ollama-only pods
  python  = { version = "3.12", deps = { "xformers==0.0.27" } },

  custom_nodes = {
    { repo = "ltdrdata/ComfyUI-Manager", ref = "main" },
  },

  models = {
    { kind = "checkpoint",
      dst  = "sd_xl_base_1.0.safetensors",
      src  = "b2://vdsl-assets/checkpoints/sd_xl_base_1.0.safetensors" },
  },

  sync = {
    push = { "/workspace/ComfyUI/output/ → b2://vdsl-output/{pod_id}/" },
  },
}

print(profile:manifest_json(true))
```

Convergence is **orchestrator-driven** — the manifest is consumed by the
[vdsl-mcp](https://github.com/ynishi/vdsl-mcp) `vdsl_profile_apply` tool,
which expands it into a sequence of MCP tool calls on the client side.
The pod itself runs no convergence script.

Source schemes for `models[].src` and `sync` routes are limited to
`b2://` (Backblaze B2) and `file://`. Stage external assets into B2
before referencing them. B2 credentials are MCP-owned and auto-injected
at apply time — never declare them in the profile.

See **[examples/11_profile.lua](examples/11_profile.lua)** (ComfyUI),
**[examples/12_vllm_profile.lua](examples/12_vllm_profile.lua)** (vLLM
serving), and **[docs/profile-and-orchestration.md](docs/profile-and-orchestration.md)**
for the full design.

## Documentation

See [SPEC.md](SPEC.md) for the full specification, and
[docs/profile-and-orchestration.md](docs/profile-and-orchestration.md)
for Profile / orchestration design.

## License

[MIT](LICENSE)
