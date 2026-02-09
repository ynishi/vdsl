# vdsl V2 Specification

Visual DSL for ComfyUI. Pure Lua. Zero dependencies.

Transforms semantic composition into ComfyUI node graphs.
Images become portable project files through PNG-embedded recipes.

## Table of Contents

- [Core Concepts](#core-concepts)
- [Entity Reference](#entity-reference)
  - [Trait](#trait)
  - [Subject](#subject)
  - [World](#world)
  - [Cast](#cast)
  - [Stage](#stage)
  - [Post](#post)
  - [Weight](#weight)
  - [Catalog](#catalog)
  - [Theme](#theme)
- [Compilation](#compilation)
  - [render()](#render)
  - [Pipeline Order](#pipeline-order)
  - [Auto-Post (Hints)](#auto-post-hints)
  - [Theme Defaults](#theme-defaults)
- [Import / Decode](#import--decode)
  - [import_png()](#import_png)
  - [decode()](#decode)
  - [read_png()](#read_png)
  - [Structural Decode Output](#structural-decode-output)
  - [Decode Limitations](#decode-limitations)
- [Embed](#embed)
  - [embed()](#embed-1)
  - [embed_to()](#embed_to)
  - [render_with_recipe()](#render_with_recipe)
  - [Recipe Format](#recipe-format)
  - [PNG Chunk Layout](#png-chunk-layout)
- [Registry](#registry)
  - [connect()](#connect)
  - [Authentication](#authentication)
  - [Resource Lookup](#resource-lookup)
  - [queue()](#queue)
- [Execution Pipeline](#execution-pipeline)
  - [run() (Registry)](#run-registry)
  - [run() (Convenience)](#run-convenience)
  - [poll()](#poll)
  - [download_image()](#download_image)
  - [Pipeline Flow](#pipeline-flow)
- [Built-in Themes](#built-in-themes)

---

## Core Concepts

vdsl models image generation as a scene composition:

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

---

## Entity Reference

### Trait

Atomic prompt fragment with optional emphasis and compiler hints.

```lua
-- Construction
local t = vdsl.trait("golden hour, warm light")
local t = vdsl.trait("detailed eyes", 1.3)       -- emphasis

-- Composition (+ operator)
local combined = vdsl.trait("left") + vdsl.trait("right")
local combined = t:with("more text")
local combined = t:with(another_trait)

-- Compiler hints (auto-Post generation)
local t = vdsl.trait("portrait"):hint("face", { fidelity = 0.7 })
local t = vdsl.trait("photo"):hint("hires", { scale = 1.5 })
                              :hint("sharpen", { radius = 1 })

-- Resolve to prompt string
t:resolve()  --> "golden hour, warm light"
vdsl.trait("eyes", 1.3):resolve()  --> "(eyes:1.3)"
```

**Fields:**
| Field | Type | Description |
|-------|------|-------------|
| `text` | string | Prompt text (single trait only) |
| `emphasis` | number | Weight multiplier, default 1.0 |

**Methods:**
| Method | Returns | Description |
|--------|---------|-------------|
| `:with(other)` | Trait | Compose with another Trait or string |
| `:hint(op, params)` | Trait | Attach auto-Post hint |
| `:hints()` | table\|nil | Get attached hints |
| `:resolve()` | string | Flatten to prompt text |

**Operators:**
| Op | Description |
|----|-------------|
| `a + b` | Compose two Traits (string auto-coerced) |

### Subject

Composable identity representing "who/what" in the scene.
Built by chaining Traits. Immutable.

```lua
local cat = vdsl.subject("cat")
  :with(vdsl.trait("walking pose"))
  :with(vdsl.trait("detailed face", 1.3))
  :quality("high")
  :style("anime")

-- Derive variant (original unchanged)
local lazy = cat:replace(walking_trait, sitting_trait)

-- From Trait (preserves hints)
local subj = vdsl.subject("base"):with(theme.traits.golden_hour)
```

**Methods:**
| Method | Returns | Description |
|--------|---------|-------------|
| `:with(trait_or_string)` | Subject | Append a Trait |
| `:quality(level)` | Subject | Add quality preset |
| `:style(name)` | Subject | Add style preset |
| `:replace(old, new)` | Subject | Swap a Trait by identity |
| `:hints()` | table\|nil | Merged hints from all Traits |
| `:resolve()` | string | Flatten to comma-separated prompt |

**Quality Presets:**
| Level | Expands to |
|-------|-----------|
| `"high"` | `masterpiece, best quality, highly detailed` |
| `"medium"` | `good quality, detailed` |
| `"draft"` | `sketch, rough, concept art` |

**Style Presets:**
| Name | Expands to |
|------|-----------|
| `"anime"` | `anime style, cel shading, 2D` |
| `"photo"` | `photorealistic, 8k uhd, raw photo` |
| `"oil"` | `oil painting, classical art, brush strokes` |
| `"watercolor"` | `watercolor painting, soft edges, wet media` |
| `"pixel"` | `pixel art, retro game, 8-bit` |
| `"3d"` | `3d render, octane render, unreal engine` |

### World

Generative foundation. Defines the model, VAE, and CLIP configuration.

```lua
local w = vdsl.world {
  model     = "sd_xl_base_1.0.safetensors",  -- required
  vae       = "custom_vae.safetensors",       -- optional
  clip_skip = 2,                               -- optional, default 1
}
```

**Fields:**
| Field | Type | Default | ComfyUI Node |
|-------|------|---------|-------------|
| `model` | string | *required* | CheckpointLoaderSimple |
| `vae` | string\|nil | nil | VAELoader |
| `clip_skip` | number | 1 | CLIPSetLastLayer |

### Cast

Subject definition. Defines who/what appears in the scene, with optional LoRA and IPAdapter.

```lua
local c = vdsl.cast {
  subject   = cat_subject,                     -- required: string, Subject, or Trait
  negative  = vdsl.trait("ugly, blurry"),       -- optional: string or Trait
  lora      = {                                 -- optional
    vdsl.lora("detail.safetensors", 0.6),
    vdsl.lora("style.safetensors", vdsl.weight.heavy),
  },
  ipadapter = {                                 -- optional
    image  = "reference.png",
    weight = 0.8,
  },
}

-- Derive with overrides
local c2 = c:with { subject = another_subject }
```

**Fields:**
| Field | Type | Description |
|-------|------|-------------|
| `subject` | Subject | Auto-coerced from string or Trait |
| `negative` | Trait\|nil | Negative prompt |
| `lora` | table\|nil | List of `{ name, weight }` |
| `ipadapter` | table\|nil | `{ image, weight }` |

**Multiple Casts** are supported. Conditionings are combined via `ConditioningCombine`. Each Cast gets its own CLIPTextEncode pair. All LoRAs from all Casts chain onto the model sequentially.

### Stage

Spatial composition. Defines ControlNet guides and img2img source.

```lua
local s = vdsl.stage {
  controlnet = {                               -- optional
    { type = "depth_model.pth", image = "depth.png", strength = 0.7 },
    { type = "canny_model.pth", image = "edges.png", strength = 0.5 },
  },
  latent_image = "init.png",                   -- optional (enables img2img)
}
```

**Fields:**
| Field | Type | Description |
|-------|------|-------------|
| `controlnet` | table\|nil | List of `{ type, image, strength }` |
| `latent_image` | string\|nil | Init image path (img2img mode) |

When `latent_image` is set, the default denoise drops to 0.7 (overridable).

### Post

Composable post-processing pipeline. Chainable with `+` operator.

```lua
local p = vdsl.post("hires", { scale = 1.5, denoise = 0.4 })
        + vdsl.post("upscale", { model = "4x-UltraSharp.pth" })
        + vdsl.post("face", { fidelity = 0.6 })
        + vdsl.post("color", { contrast = 1.1, gamma = 0.9 })
        + vdsl.post("sharpen", { radius = 1 })

-- Alternative chain syntax
local p = vdsl.post("hires", { scale = 1.5 })
  :then_do("upscale", { model = "4x.pth" })
  :then_do("sharpen", { radius = 2 })
```

**Operations:**

| Op Type | Phase | Params | ComfyUI Node |
|---------|-------|--------|-------------|
| `hires` | latent | `scale`, `method`, `steps`, `cfg`, `sampler`, `scheduler`, `denoise` | LatentUpscaleBy + KSampler |
| `refine` | latent | `steps`, `cfg`, `sampler`, `scheduler`, `denoise` | KSampler (2nd pass) |
| `upscale` | pixel | `model` | UpscaleModelLoader + ImageUpscaleWithModel |
| `face` | pixel | `model`, `fidelity` | FaceRestoreModelLoader + FaceRestoreWithModel |
| `color` | pixel | `brightness`, `contrast`, `saturation`, `gamma` | ColorCorrect |
| `sharpen` | pixel | `radius`, `sigma`, `alpha` | ImageSharpen |
| `resize` | pixel | `scale`, `method` or `width`, `height`, `method`, `crop` | ImageScaleBy or ImageScale |

**Phase ordering**: Latent ops execute before VAEDecode, pixel ops after. This is enforced regardless of declaration order.

### Weight

Semantic weight values. Replaces raw numbers with meaningful levels.

```lua
vdsl.weight.none    -- 0.0
vdsl.weight.subtle  -- 0.2
vdsl.weight.light   -- 0.4
vdsl.weight.medium  -- 0.6
vdsl.weight.heavy   -- 0.8
vdsl.weight.full    -- 1.0

-- Range (for experimentation)
vdsl.weight.range(0.3, 0.8, 0.1)  -- random within range, quantized to step
```

Accepted anywhere a weight is expected (LoRA, IPAdapter, ControlNet strength).

### Catalog

Named dictionary of Traits. Validation wrapper.

```lua
local my_catalog = vdsl.catalog {
  portrait = vdsl.trait("portrait, face closeup"):hint("face", { fidelity = 0.7 }),
  anime_hq = vdsl.trait("anime style"):hint("hires", { scale = 1.5 }),
}

-- Use in Subject composition
local subj = vdsl.subject("warrior"):with(my_catalog.portrait)
```

All values must be Trait entities. All keys must be strings.

### Theme

Named Catalog with metadata, negatives, and render defaults.

```lua
local theme = vdsl.theme {
  name     = "cinema",                           -- required
  category = "photography",                       -- optional
  tags     = { "film", "lighting" },              -- optional
  defaults = {                                    -- optional: render param defaults
    steps = 30, cfg = 7.5, sampler = "euler",
    size = { 1024, 1024 },
  },
  negatives = {                                   -- optional
    default = vdsl.trait("cartoon, anime"),
    quality = vdsl.trait("low quality, blurry"),
  },
  traits = {                                      -- required
    golden_hour = vdsl.trait("golden hour"):hint("color", { gamma = 0.9 }),
    noir        = vdsl.trait("film noir"):hint("color", { contrast = 1.3 }),
  },
}

-- Access
theme.traits.golden_hour   -- Trait entity
theme.negatives.default    -- Trait entity
theme:has_tag("film")      -- true
theme:trait_names()        -- { "golden_hour", "noir" }
```

**Built-in themes** are lazy-loaded via `vdsl.themes.<name>`.

---

## Compilation

### render()

Compiles entities into a ComfyUI node graph.

```lua
local result = vdsl.render {
  world     = vdsl.world { model = "model.safetensors" },  -- required
  cast      = { cast1, cast2 },                             -- required, 1+
  stage     = stage_entity,                                  -- optional
  post      = post_chain,                                    -- optional
  theme     = vdsl.themes.cinema,                            -- optional
  negative  = vdsl.trait("global negative"),                  -- optional
  seed      = 42,                -- optional (random if omitted)
  steps     = 25,                -- optional (default 20, or theme)
  cfg       = 5.5,               -- optional (default 7.0, or theme)
  sampler   = "euler",           -- optional (default "euler", or theme)
  scheduler = "normal",          -- optional (default "normal", or theme)
  denoise   = 1.0,               -- optional (0.7 when img2img)
  size      = { 1024, 1024 },   -- optional (default 512x512, or theme)
  output    = "my_image.png",    -- optional filename prefix
  auto_post = true,              -- optional (default true)
}
```

**Return value:**
| Field | Type | Description |
|-------|------|-------------|
| `result.prompt` | table | ComfyUI API prompt (node graph) |
| `result.json` | string | JSON-encoded prompt |
| `result.graph` | Graph | Internal graph object |

### Pipeline Order

The compiler emits nodes in this fixed order:

```
1. World      → CheckpointLoaderSimple [+ VAELoader] [+ CLIPSetLastLayer]
2. Casts      → LoRA chain → CLIPTextEncode (pos/neg) → ConditioningCombine
3. Negative   → Global negative CLIPTextEncode + ConditioningCombine
4. Stage      → ControlNet chain [+ LoadImage → VAEEncode]
5. Latent     → EmptyLatentImage (or img2img latent)
6. KSampler   → Primary sampling pass
7. Post       → Latent-phase ops (hires, refine)
8. VAEDecode  → Latent to pixels
9. Post       → Pixel-phase ops (upscale, face, color, sharpen, resize)
10. SaveImage → Output
```

### Auto-Post (Hints)

When `post` is not explicitly set and `auto_post ~= false`, the compiler collects hints from all Cast Subjects' Traits and generates a Post pipeline automatically.

```lua
local portrait = vdsl.trait("portrait"):hint("face", { fidelity = 0.7 })
local hq       = vdsl.trait("high res"):hint("hires", { scale = 1.5 })

local subj = vdsl.subject("warrior"):with(portrait):with(hq)
local cast = vdsl.cast { subject = subj }

vdsl.render { world = w, cast = { cast }, seed = 42 }
-- Auto-generates: hires (latent) + face restore (pixel)
```

**Priority**: explicit `post` > auto-post from hints > none.

Hints are collected from all Casts, merged (later wins on conflict), and sorted by pipeline order:
`hires(1) → refine(2) → upscale(3) → face(4) → color(5) → sharpen(6) → resize(7)`

### Theme Defaults

Parameter resolution order: **explicit opts > theme.defaults > hard-coded fallback**.

```lua
-- Theme provides defaults, opts override selectively
vdsl.render {
  theme = vdsl.themes.cinema,  -- steps=30, cfg=7.5, size=1024x1024
  steps = 15,                   -- overrides theme's 30
  -- cfg and size come from theme
}
```

**Global negative** resolution: `opts.negative > theme.negatives.default > none`.

---

## Import / Decode

Two import modes: **recipe** (full semantic round-trip) and **structural decode** (best-effort from ComfyUI prompt).

### import_png()

Primary import function. Prefers embedded vdsl recipe; falls back to structural decode.

```lua
local info, err, has_recipe = vdsl.import_png("output.png")

if has_recipe then
  -- Full semantic entities: info.world, info.cast, info.theme, etc.
  -- Can re-render directly:
  local result = vdsl.render(info)
else
  -- Structural decode: info.world, info.casts, info.sampler, etc.
  -- Plain data tables, not entities
end
```

**Return values:**
| Value | Type | Description |
|-------|------|-------------|
| `info` | table\|nil | Decoded data or render opts |
| `err` | string\|nil | Error message |
| `has_recipe` | boolean | true if vdsl recipe was found |

### decode()

Structural decode from a ComfyUI prompt table.

```lua
local info = vdsl.decode(comfy_prompt)
```

### read_png()

Low-level: read and JSON-decode ComfyUI metadata chunks.

```lua
local meta = vdsl.read_png("output.png")
-- meta.prompt   = ComfyUI prompt table (or nil)
-- meta.workflow = ComfyUI workflow table (or nil)
```

### Structural Decode Output

When no vdsl recipe is available, `import_png()` returns structural data:

```lua
{
  world = {
    model     = "model.safetensors",
    vae       = "custom.safetensors",  -- or nil
    clip_skip = 2,
  },
  casts = {
    {
      prompt   = "warrior woman, detailed",
      negative = "ugly, blurry",
      loras    = { { name = "detail.safetensors", weight = 0.6 } },  -- or nil
      ipadapter = { image = "ref.png", weight = 0.8 },               -- or nil
    },
  },
  sampler = {
    seed = 42, steps = 25, cfg = 5.5,
    sampler = "euler", scheduler = "normal", denoise = 1.0,
  },
  stage = {                              -- or nil
    controlnet   = { { type = "depth.pth", image = "d.png", strength = 0.7 } },
    latent_image = "init.png",           -- or nil
  },
  post = {                               -- or nil
    { type = "hires",   params = { scale = 1.5, denoise = 0.4 } },
    { type = "upscale", params = { model = "4x.pth" } },
  },
  size             = { 1024, 1024 },     -- or nil (img2img)
  output           = "prefix",
  global_negatives = { "extra neg text" }, -- or nil
}
```

### Decode Limitations

Structural decode is **best-effort**. The following semantic information is irrecoverable from the compiled node graph:

| Lost | Reason |
|------|--------|
| Trait boundaries and composition | Flattened to single comma-separated string |
| Emphasis semantics | Baked into `(text:1.3)` syntax in prompt string |
| Weight names (subtle, heavy) | Resolved to plain numbers |
| Subject quality/style presets | Expanded and concatenated |
| Theme identity and metadata | Consumed during compilation |
| LoRA-to-Cast attribution | All LoRAs chain sequentially across Casts |
| Hint provenance | Merged into anonymous Post ops |
| Global vs Cast negative distinction | Heuristic only (structural position) |

Use **embed** to preserve full semantic information.

---

## Embed

Inject vdsl recipes into PNG files. The image becomes a self-contained project file.

Both `embed()` and `embed_to()` compile the render opts and inject **two** tEXt chunks:
- `"vdsl"` — semantic recipe (Trait structure, hints, Theme refs)
- `"prompt"` — compiled ComfyUI node graph JSON

This makes each PNG fully self-consistent: ComfyUI can load the `prompt` directly, while vdsl can restore full semantic entities from the `vdsl` recipe.

### embed()

Compile and write recipe + prompt into existing PNG (in-place).

```lua
local ok, err = vdsl.embed("output.png", render_opts)
```

### embed_to()

Compile and write recipe + prompt into a copy (non-destructive).

```lua
local ok, err = vdsl.embed_to("source.png", "dest.png", render_opts)
```

### render_with_recipe()

Compile and serialize recipe in one call.

```lua
local result = vdsl.render_with_recipe(opts)
-- result.prompt  (ComfyUI node graph)
-- result.json    (JSON string)
-- result.recipe  (vdsl recipe JSON string, for manual embedding)
```

### Recipe Format

The recipe is a JSON object stored in a PNG tEXt chunk with keyword `"vdsl"`.
It captures the full render opts including Trait structure, emphasis, hints, Theme reference, and all parameters.

**Version**: `_v = 1`

Entities are serialized with type markers:
- `{ _t: "trait", text, emphasis, parts, hints }` for Trait
- `{ _t: "subject", traits: [...] }` for Subject
- `{ _t: "str", v: "..." }` for plain strings

Themes are stored by name reference; built-in themes are restored by `require`.

### PNG Chunk Layout

After embedding, a PNG contains:

```
PNG Signature
IHDR (image header)
... (pixel data chunks)
tEXt "prompt"   → ComfyUI node graph JSON (compiled by vdsl.embed, or written by ComfyUI)
tEXt "workflow"  → ComfyUI UI state JSON   (written by ComfyUI, preserved if present)
tEXt "vdsl"      → vdsl recipe JSON        (written by vdsl.embed)
IEND
```

All chunks coexist. When `embed()` writes the `prompt` chunk, it replaces any existing one (e.g. from the original ComfyUI generation) with the newly compiled workflow matching the current render opts.

`import_png()` prefers `"vdsl"` (full semantic), falls back to `"prompt"` (structural decode).

---

## Registry

Server-side resource discovery via ComfyUI `/object_info` API.

### connect()

```lua
-- Local server
local reg = vdsl.connect("http://127.0.0.1:8188")

-- Remote server with authentication
local reg = vdsl.connect("https://host.proxy.runpod.net", {
  token = "your-api-token",
})

-- Custom headers
local reg = vdsl.connect("https://host.example.com", {
  headers = { ["Authorization"] = "Bearer xxx", ["X-Custom"] = "value" },
})
```

### Authentication

The `token` option is a convenience that sets `Authorization: Bearer <token>`.
For other auth schemes, use the `headers` option directly.

Authentication headers are stored on the Registry instance and automatically included in all subsequent API calls: `queue()`, `poll()`, `download_image()`, and `run()`.

### Resource Lookup

Fuzzy-match resources available on the server:

```lua
reg:checkpoint("animagine")  --> "animagine_xl_v3.1.safetensors"
reg:vae("sdxl")              --> "sdxl_vae.safetensors"
reg:lora("detail", 0.6)     --> { name = "add_detail.safetensors", weight = 0.6 }
reg:controlnet("depth")     --> "control_v11f1p_sd15_depth.pth"
reg:upscaler("ultrasharp")  --> "4x-UltraSharp.pth"
```

The default matcher uses multi-strategy scoring: exact > stem > prefix > contains > normalized > tokenized.

Custom matchers can be injected:

```lua
vdsl.set_matcher(function(query, name)
  -- return score (number), 0 = no match
end)
```

### queue()

Submit a render result to the server. Returns a table with `prompt_id`.

```lua
local result = vdsl.render { ... }
local resp = reg:queue(result)
print(resp.prompt_id)
```

---

## Execution Pipeline

Full pipeline: compile → queue → poll → download → embed. One call from DSL to saved PNG.

### run() (Registry)

Execute the full pipeline using a connected Registry.

```lua
local reg = vdsl.connect("http://127.0.0.1:8188", { token = "..." })

local result = reg:run(render_opts, {
  save     = "/path/to/output.png",   -- save first image to this path
  save_dir = "/path/to/dir/",         -- OR save all images to directory
  timeout  = 120,                      -- poll timeout in seconds (default 300)
  interval = 1,                        -- poll interval in seconds (default 1)
  embed    = true,                     -- embed recipe + prompt (default true)
})
```

**Return value:**
| Field | Type | Description |
|-------|------|-------------|
| `result.prompt_id` | string | ComfyUI prompt ID |
| `result.images` | table | Image info from ComfyUI `[{ filename, subfolder, type }]` |
| `result.files` | table | Local file paths of saved images |
| `result.render` | table | Compile result (`.prompt`, `.json`, `.graph`) |

**Save modes:**
- `save = path` — download first output image to the specified path
- `save_dir = dir` — download all output images to the directory (keeps ComfyUI filenames)
- Neither — images are queued and polled but not downloaded

When `embed` is `true` (default), each saved PNG gets both `"vdsl"` (recipe) and `"prompt"` (compiled workflow) tEXt chunks injected after download.

### run() (Convenience)

One-shot wrapper that connects and runs in a single call. Render opts and run opts are mixed in one table.

```lua
local result = vdsl.run {
  -- Connection
  url   = "https://host.proxy.runpod.net",
  token = "your-api-token",              -- optional

  -- Render opts (same as vdsl.render)
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = subj, negative = neg } },
  seed  = 42,
  steps = 25,
  cfg   = 5.5,
  size  = { 1024, 1024 },

  -- Run opts
  save     = "/tmp/output.png",
  timeout  = 120,
}
```

Run-specific keys (`url`, `token`, `save`, `save_dir`, `timeout`, `interval`, `embed`) are separated automatically. Everything else is passed as render opts.

A pre-connected Registry can be passed as the second argument to skip reconnection:

```lua
local reg = vdsl.connect(url, { token = token })
local r1 = vdsl.run({ world = w, cast = { c1 }, save = "a.png" }, reg)
local r2 = vdsl.run({ world = w, cast = { c2 }, save = "b.png" }, reg)
```

### poll()

Poll `/history/{prompt_id}` until the job completes.

```lua
local history = reg:poll(prompt_id, {
  timeout  = 300,   -- seconds (default 300)
  interval = 1,     -- seconds (default 1)
})
```

Raises an error on timeout or if ComfyUI reports an execution error.

### download_image()

Download a single image from the ComfyUI `/view` endpoint.

```lua
reg:download_image(
  { filename = "ComfyUI_00001_.png", subfolder = "", type = "output" },
  "/path/to/local.png"
)
```

### Pipeline Flow

```
vdsl.render(opts)              compile DSL → ComfyUI node graph
       ↓
reg:queue(result)              POST /prompt → prompt_id
       ↓
reg:poll(prompt_id)            GET /history/{id} → wait for completion
       ↓
reg:download_image(info, path) GET /view?filename=... → save PNG
       ↓
png.inject_text(path, {...})   Embed vdsl recipe + compiled prompt
       ↓
vdsl.import_png(path)          Full semantic round-trip for next iteration
```

`reg:run()` and `vdsl.run()` wrap this entire flow in a single call.

---

## Built-in Themes

### cinema

Category: `photography`. Tags: `film`, `lighting`, `mood`, `grading`.

Defaults: steps=30, cfg=7.5, 1024x1024.

| Trait | Prompt | Auto-Post |
|-------|--------|-----------|
| `golden_hour` | golden hour, warm light, sunset glow | color (gamma=0.9, sat=1.1) |
| `blue_hour` | blue hour, twilight, cool ambient | color (sat=1.15, gamma=1.1) |
| `noir` | film noir, high contrast, dramatic | color (contrast=1.3, sat=0.4) |
| `neon` | neon lighting, cyberpunk, vivid | color (sat=1.3, contrast=1.1) |
| `soft_light` | soft diffused light, overcast | color (contrast=0.9) |
| `dramatic` | dramatic lighting, chiaroscuro | color (contrast=1.2) |
| `vintage` | vintage film, grain, faded | color (sat=0.7, gamma=0.95) |
| `bokeh` | shallow depth of field, f/1.4 | none |

Negatives: `default` (cartoon, anime), `quality` (low quality, blurry).

### anime

Category: `illustration`. Tags: `anime`, `manga`, `cel`, `2d`.

Defaults: steps=28, cfg=7.0, 832x1216 (portrait).

| Trait | Prompt | Auto-Post |
|-------|--------|-----------|
| `cel_shade` | anime style, cel shading, clean lineart | sharpen |
| `watercolor` | anime watercolor, soft edges, pastel | color (sat=0.9) |
| `ghibli` | studio ghibli style, lush scenery | color (sat=1.1) |
| `cyberpunk` | cyberpunk anime, neon glow, dark | color (contrast=1.15, sat=1.2) |
| `chibi` | chibi style, super deformed, cute | none |
| `sketch` | pencil sketch, line drawing, rough | none |
| `retro` | 90s anime style, VHS aesthetic | color (sat=0.85, gamma=0.95) |
| `bijutsu` | detailed anime background, scenic | none |

Negatives: `default` (photorealistic, 3d render), `quality` (low quality, blurry).

### architecture

Category: `visualization`. Tags: `archviz`, `procedural`, `3d`, `environment`.

Defaults: steps=35, cfg=7.0, 1024x1024.

| Trait | Prompt | Auto-Post |
|-------|--------|-----------|
| `exterior` | architectural exterior, facade | hires (1.5x) |
| `interior` | interior design, ambient lighting | color |
| `aerial` | aerial view, urban planning | hires (2.0x) |
| `blueprint` | architectural blueprint, wireframe | sharpen |
| `organic` | organic architecture, biomimicry | none |
| `brutalist` | brutalist, raw concrete, monolithic | color (contrast=1.15) |
| `futuristic` | futuristic, sci-fi, glass and metal | color (contrast=1.1) |
| `landscape` | landscape architecture, greenery | color (sat=1.15) |

Negatives: `default` (cartoon, anime, sketch), `quality` (low quality, blurry).

---

## Quick Reference

### Compose + Render (local)

```lua
local vdsl = require("vdsl")

local subj = vdsl.subject("warrior")
  :with(vdsl.trait("detailed face", 1.3))
  :quality("high"):style("anime")

local render_opts = {
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = subj, negative = "ugly" } },
  theme = vdsl.themes.anime,
  seed  = 42,
}

local r = vdsl.render(render_opts)
print(r.json)  -- ComfyUI-ready JSON
```

### Full Pipeline (remote)

```lua
local vdsl = require("vdsl")

local result = vdsl.run {
  url   = "https://host.proxy.runpod.net",
  token = "your-api-token",
  world = vdsl.world { model = "model.safetensors" },
  cast  = { vdsl.cast { subject = subj, negative = neg } },
  seed  = 42,
  steps = 25,
  save  = "/tmp/output.png",
}
-- output.png: generated image + vdsl recipe + compiled prompt
```

### Embed + Import Round-trip

```lua
-- Embed recipe into existing PNG
vdsl.embed("output.png", render_opts)

-- Non-destructive copy with recipe
vdsl.embed_to("source.png", "dest.png", render_opts)

-- Import from PNG (prefers vdsl recipe, falls back to structural decode)
local opts, _, has_recipe = vdsl.import_png("output.png")
if has_recipe then vdsl.render(opts) end
```

### Parametric Generation

```lua
local reg = vdsl.connect(url, { token = token })

for _, season in ipairs(seasons) do
  for _, style in ipairs(styles) do
    reg:run({
      world = w,
      cast  = { vdsl.cast { subject = heroine:with(season.trait), negative = neg } },
      theme = style.theme,
      seed  = 42,
    }, {
      save = dir .. "/" .. season.name .. "_" .. style.name .. ".png",
    })
  end
end
-- Each PNG: generated image + full vdsl recipe for re-import
```

---

## Future: Server-Side Extensions

Design notes for planned Registry extensions. Not yet implemented.

### search()

Server-side resource search. Requires host-side endpoint (ComfyUI extension or standalone).

```lua
Registry:search(query, opts)
-- query: string | Trait | any (Entity.resolve_text compatible)
-- opts:  { category = nil, limit = 10, threshold = 0 }
-- return: table[] sorted by score desc

-- result[i] = {
--   name     = "animagine_xl_v3.safetensors",
--   category = "checkpoint",  -- "checkpoint"|"lora"|"controlnet"|"vae"|"upscaler"
--   score    = 850,
--   tags     = { "sdxl", "anime" },  -- host provides (optional)
-- }

-- Direct use:
local hits = reg:search("anime xl", { limit = 5 })
local w = vdsl.world { model = hits[1].name }
```

Host protocol: `GET /vdsl/search?q=<query>&category=<cat>&limit=<n>` returns JSON array.

### search_themes()

Server-side theme pack search. Host maintains curated theme packs (model + lora + negatives + defaults) queryable by intent.

```lua
Registry:search_themes(query, opts)
-- query: string | Trait | any
-- opts:  { limit = 5 }
-- return: table[] — each element is Theme.new()-compatible

-- result[i] = {
--   name      = "anime_portrait_v2",
--   score     = 920,
--   defaults  = { model = "animagine_xl_v3.safetensors", steps = 28, ... },
--   negatives = { default = Trait("photorealistic, 3d render") },
--   loras     = { { name = "anime_detail.safetensors", weight = 0.7 } },
--   traits    = { ... },  -- optional server-defined Trait catalog
-- }

-- Direct use as Theme:
local packs = reg:search_themes("anime portrait", { limit = 3 })
local theme = vdsl.theme(packs[1])
vdsl.render { theme = theme, cast = { ... }, seed = 42 }
```

Host protocol: `GET /vdsl/themes?q=<query>&limit=<n>` returns JSON array.

Host implementation hint: Python + SQLite/JSON is enough for a working demo. Tables: `resources(name, category, tags[])`, `themes(name, json_blob)`. Full-text search on tags + name, return top-N by score.

### Registry:decode() (host-assisted)

Two-layer design: metadata extraction (host) + entity mapping (vdsl).

**Layer 1: Host-side** — PNG metadata extraction. ComfyUI embeds workflow JSON in PNG tEXt chunks. Extraction requires binary PNG parsing.

```
Host endpoint:
  POST /vdsl/decode  body: { image = "<base64 or path>" }
  → JSON: { prompt = { ... }, workflow = { ... } }

Or local tool:
  python -m vdsl_tools.decode image.png → stdout JSON
```

**Layer 2: vdsl-side** — ComfyUI JSON to entity reconstruction (best-effort).

```lua
local info = reg:decode(comfy_prompt)
-- info.world, info.casts, info.sampler, info.post, info.size
```

Limitations: one-way best-effort, custom nodes skipped, multi-cast separation is heuristic, returns raw data (not vdsl entities).
