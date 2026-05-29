# Entity Architecture

How VDSL models a scene as composable, serializable entities — and why there is
no dedicated "Anchor" type for identity/versioning.

## 1. The model in one paragraph

A render is built from **entities**: small immutable value objects (`Trait`,
`Subject`, `World`, `Cast`, `Stage`, `Post`) and one aggregate root (`Shot`).
Every entity can be **composed** (`clone` / `with`), compared (`equals`), and
**serialized** to a plain table that round-trips losslessly through JSON. The
framework owns *what an entity is* and *how it turns into a ComfyUI workflow* —
nothing else. Persistence, versioning, and training orchestration live in the
**application layer**.

## 2. Two base families

`entity.lua` provides one shared lifecycle (`serialize` / `deserialize` /
`clone` / `with` / `equals`) over two derivation families:

| Family | `__index` | Lifecycle access | Used by |
|--------|-----------|------------------|---------|
| **Core** (value / aggregate) | method dispatch | `x:serialize()` | World, Cast, Stage, Subject, Trait, Post, **Shot** |
| **Collection** | member lookup (`catalog.portrait`) | `Collection.serialize(c)` static | Catalog |

`Entity.define_core(name)` registers a type and attaches the lifecycle methods;
`Entity.define_collection(name)` keeps `__index` free for member lookup and
exposes the lifecycle as statics.

## 3. Entity catalog

| Concept | Entity | ComfyUI mapping |
|---------|--------|-----------------|
| Universe rules | **World** | Checkpoint, VAE, CLIP skip |
| Who / what | **Cast** | CLIP encode, LoRA, IPAdapter |
| Where / how | **Stage** | ControlNet, img2img (`latent_image`) |
| Post-processing | **Post** | Upscale, face restore, color |
| Atomic prompt | **Trait** | Prompt text fragment |
| Identity | **Subject** | Composed Trait chain |
| Reusable vocabulary | **Catalog** | Named Trait dictionary (Collection) |
| Finished image | **Shot** | Full render recipe (World + Cast + Stage + Post) |

`Shot` is the aggregate root: one finished deliverable image. How many passes
produce it is a compiler concern, not part of the `Shot` definition.

## 4. Serialize / deserialize is the persistence boundary

This is the single mechanism that makes "just save it and load it back" work,
and it is the reason no versioning type is needed.

- `entity:serialize()` walks the instance and projects it to a plain table,
  tagging every entity-typed sub-table with a `_type` field (so nested entities
  — e.g. a `Stage` inside a `Shot`, a `Trait` inside a `Subject` — are captured).
- `Entity.deserialize(type, plain)` rebuilds the instance, restoring metatables
  from the `_type` tags recursively.

```lua
local sub      = vdsl.subject("warrior woman"):with(vdsl.trait("ornate armor"))
local wire     = json.encode(sub:serialize())          -- entity -> Data
-- ... store `wire` anywhere: a file, a SQLite row, a B2 object ...
local restored = Entity.deserialize("subject", json.decode(wire))  -- Data -> entity
assert(restored:resolve() == sub:resolve())            -- lossless
```

Because the round-trip is lossless, **what to version is just what you choose to
serialize**: a `Subject` to reuse an identity, or a whole `Shot` to reproduce a
complete look (ControlNet included, because the `Stage` rides inside the `Shot`).

## 5. Responsibility split

```
vdsl framework owns                      application owns
─────────────────────                    ─────────────────
entity definitions                       persistence backend (file / SQLite / B2 / ...)
composition (clone / with / equals)      version list + "current" pointer + revert
lossless serialize / deserialize         training orchestration (RunPod, ...)
compile entity tree -> ComfyUI JSON      WHICH entity to serialize (Subject vs Shot)
```

The framework deliberately never touches storage. The application is free to
pick any backend and any history scheme.

## 6. Recommended patterns

See `examples/15_identity_reuse.lua` for a runnable end-to-end version.

### Identity reuse
An identity is a `Subject`. Save it with `serialize`, load it with
`Entity.deserialize("subject", ...)`. There is no special "anchor" object.

### Variations
A variation is a `Subject:with(...)` overlay. The base `Subject` is immutable, so
overlays never mutate it:

```lua
local close_up = identity:with(vdsl.trait("close-up of face"))
local wide     = identity:with(vdsl.trait("full body, wide angle"))
```

### Look reuse
A whole look (the full recipe, ControlNet and all) is a `Shot`. Derive variants
with `clone` / `with`:

```lua
local base_shot = vdsl.shot { world = w, cast = { c }, seed = 42, steps = 25 }
local reroll    = base_shot:with { seed = 99 }   -- same look, new seed
```

### Versioning
A version history is an application-owned list of serialized snapshots:

```
versions = { v1 = wire_v1, v2 = wire_v2, ... };  current = "v2"
```

- **train** = produce a new snapshot (e.g. attach a freshly trained LoRA to the
  Subject/Cast) and append it to the list.
- **revert** = load an older snapshot.

None of this is framework code — it is a few lines wherever you keep your data.

## 7. Why there is no Anchor type

A previous `vdsl.anchor{}` registry conflated three orthogonal concerns into one
entity: **identity** (a Subject template), **versioning** (a snapshot chain), and
a narrow **render projection** (it only produced a `Subject`). That last point
caused the original bug: ControlNet lives on `Stage`, never on the anchored
`Subject`, so versioning an anchor never captured ControlNet.

Separating the concerns dissolves the bug instead of patching it:

- Identity → a `Subject` you serialize. ControlNet is *not* identity (it is
  per-scene pose), so it correctly stays out.
- Full-look reproducibility → a `Shot` you serialize. ControlNet *is* captured,
  because `Stage` rides inside the `Shot`.
- Versioning → an application-layer list of snapshots, over whichever entity you
  chose.

With no "box that versions only the Subject", there is no box for ControlNet to
leak out of. The metamethod complexity that the old registry needed (to make
`reg.current` behave as both a string field and a method) also disappears.

## 8. Migration note (downstream consumers)

`vdsl.anchor{...}`, `AnchorRegistry`, `Anchor:render`, the `Cast{anchor=A}`
adapter, and the `_anchor_*.json` emit sidecar were removed. Code that generated
or consumed `vdsl.anchor{...}` (for example a host that builds Lua snippets for a
camera/persona pipeline) must move to:

- build a `Subject` directly (base text + Trait chain), and
- persist/load it via `serialize` / `Entity.deserialize`,
- supplying ControlNet/pose per render through `Stage`, not through the identity.
