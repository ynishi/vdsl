# vdsl

Visual DSL for ComfyUI. Pure Lua. Zero runtime dependencies for DSL and compilation.
Server execution (`connect`/`run`) requires `curl` or a custom HTTP backend.

Transforms semantic scene composition into ComfyUI node graphs.
Images become portable project files through PNG-embedded recipes.

## Install

```bash
luarocks install vdsl
```

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

## Documentation

See [SPEC.md](SPEC.md) for the full specification.

## License

[MIT](LICENSE)
