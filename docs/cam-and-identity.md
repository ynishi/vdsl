# Cam and Identity

`vdsl.cam` renders a sequence of shots that all share one fixed identity. This
document explains the identity model, the `vdsl.cam` API, the prompt
composition order, and how host tools scaffold cam scripts.

## Identity is a Subject (there is no Anchor type)

An identity is just a `vdsl.subject(...)` with its fixed traits applied via
`Subject:with`. There is no dedicated identity entity — the registry/versioning
layer that earlier releases called `Anchor` was removed. Identity reuse and
versioning are plain `entity:serialize()` -> store -> `Entity.deserialize`, and
the application owns the storage backend and version history. See
`entity-architecture.md` §"Why there is no Anchor type" and
`examples/15_identity_reuse.lua` for the migration.

```lua
local base = vdsl.subject("1girl, solo, 20 years old")
  :with(vdsl.trait("silver hair"))
  :with(vdsl.trait("blue eyes"))
```

That `base` Subject is the identity. It stays fixed across every shot.

## `vdsl.cam{...}`

```lua
vdsl.cam {
  world    = w,            -- required: World (model / clip_skip / ...)
  base     = base,         -- required: the fixed identity Subject
  shots    = {             -- required: non-empty array
    { name = "v1_portrait", seed = 42, trait = C.camera.portrait_lens },
    { name = "v1_wide",     seed = 43, trait = vdsl.trait("full body, wide angle") },
    { name = "v1_plain",    seed = 44 },  -- no per-shot trait: identity + common only
  },
  negative = neg,          -- optional: shared negative prompt (separate channel)
  common   = common_cam,   -- optional: shared trait added to every shot (e.g. framing)
  -- sampler / steps / cfg / size also accepted (see lua/vdsl/cam.lua for defaults)
}
```

For each shot, `vdsl.cam`:

1. overlays the shot's `trait` (combined with `common` when both are present)
   on top of `base` via `Subject:with`,
2. renders through `world`,
3. emits one image under the shot's `name`.

The render/cast loop shape lives in exactly one place (`lua/vdsl/cam.lua`).
Host tools that scaffold cam scripts call `vdsl.cam{...}` instead of
string-templating the loop, so a change to `vdsl.render` / `vdsl.cast` only has
to be reflected in the runtime — not in every generator.

`shots[i].trait` is a real DSL expression: a catalog ref (`C.camera.portrait_lens`)
or a `vdsl.trait("...")` call. A shot may omit `trait` entirely. Passing raw
prompt text where an expression is expected produces invalid Lua.

## Prompt composition order

The positive prompt for each shot is composed left to right in this order:

1. **identity base text** — the Subject's base string (e.g. `1girl, solo, 20 years old`)
2. **identity traits** — traits fixed on the identity via `Subject:with`
3. **per-shot `trait`** — this shot's overlay
4. **shared `common` trait** — framing applied to every shot

The **negative** prompt is a separate channel (the cast's `negative`); it is not
concatenated into the positive prompt. When a shot has neither `trait` nor
`common`, the identity Subject is used as-is (no empty trait is fabricated).

Example resolved positive prompt for shot
`{ trait = vdsl.trait("upper body, close up") }` with the `base` above and
`common = C.camera.medium_shot + C.camera.eye_level`:

```
1girl, solo, 20 years old, silver hair, blue eyes, upper body, close up, medium shot, ..., eye level, ...
```

## Host-tool integration

The vdsl-mcp server's `vdsl_cam_lua_init` tool scaffolds a cam script that
calls `vdsl.cam{...}`. Its `identity` parameter is a flat Subject spec
(`base_text` + `traits` + `negative_traits`); when supplied it is emitted as a
`vdsl.subject(...)` chain and becomes the cam `base` (the response reports
`base_source: "identity"`). When `identity` is omitted, the tool resolves a
persona-specific base subject via a file fallback instead.

## See also

- `examples/16_cam_sequence.lua` — runnable N-shots-through-one-identity example
- `examples/15_identity_reuse.lua` — identity reuse via serialize/deserialize
- `entity-architecture.md` — entity model and why there is no Anchor type
- `lua/vdsl/cam.lua` — implementation and parameter defaults
