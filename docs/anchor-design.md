# Anchor — Subject fixation and unified variation management

Core entity design for the **subject fixation + variation set + LoRA-bake integration** layer that VDSL provides. Anchor sits one level above `Subject` (the 1-shot scene-side primitive) as an identity-bearing layer that is **domain-neutral**: it applies uniformly to personas, mechanical motifs, fixed backgrounds, or any other identity that needs to be stabilized across multiple renders.

This document is scoped to the **Core (Lua module) entity design**. Application-layer concerns (cam / persona-camera / domain-specific entities) and MCP-side persistence infrastructure are intentionally out of scope.

## 1. Background and motivation

VDSL is by construction **scene-oriented, entity-free, and 1-shot-complete**.

- `Subject` (`lua/vdsl/subject.lua`) is an immutable Trait chain — a one-shot subject expression.
- `Cast` (`lua/vdsl/cast.lua`) exposes LoRA / IPAdapter slots, but injection is ad-hoc and not bound to any persistent identity.
- `lua/vdsl/training/` provides training DSLs (kohya / leco / sliders / TI / lycoris) but does not define where the produced weights are stored or how they are recalled.
- There is no higher-level concept that aggregates **(a) a Subject factory tied to a stable identity, (b) baked LoRA weights owned by that identity, (c) a variation set indexed by that identity, and (d) a portable serialization surface** into a single Entity.

The `Anchor` entity covers exactly these four roles. It is designed to be **domain-neutral**: nothing about its shape is persona-specific. The same entity is used for character anchors, mechanical-motif anchors, background anchors, or any future identity.

## 2. Entity design

### 2.1 AnchorRegistry

A mutable container that holds, for one identity, an **append-only chain of versions** plus a **current pointer**. All version creation and revert operations go through the registry; individual `Anchor.vN` snapshots are never mutated in place.

```
AnchorRegistry
├ name      : string           -- identity name ("shi" / "machine-A" / ...)
├ current   : string           -- active version tag (e.g. "v2")
├ versions  : Anchor[]         -- append-only snapshot list
└ methods   : :train, :revert, :current, :latest, :emit
```

- `versions` is strictly append-only. `revert("v1")` moves the `current` pointer only; it never rewrites or removes elements.
- `current` is a **string tag** (`"v1"`, `"v2"`, ...). Integer indices were rejected because tag strings are more readable in revert logs / persisted rows, and they leave room for future branch names such as `"v2-alt"`.
- The only mutable state is the `current` pointer. `versions[]` and each `Anchor` element are immutable.

### 2.2 Anchor (per-version, immutable snapshot)

```
Anchor.vN
├ version           : string                       -- "v1", "v2", ...
├ base              : SubjectSpec                  -- { base_text, traits[] }
├ assets            : {
│     loras[]       : AssetSpec[]                  -- multiple LoRAs as an array
│     ipadapter_image? : string
│     i2i_ref?      : string
│   }
├ variations        : { name -> Trait[] }          -- overlay trait deltas
├ training_record?  : TrainingRecord               -- spec that produced this version; null for hand-authored
└ created_at?       : ISO8601 string               -- optional; MCP-side may set, Lua does not require
```

Each version is a **self-contained snapshot**, not a diff against the previous one. `base`, `assets`, and `variations` are fully materialized at every version, so `revert("v3")` is an O(1) pointer move with no diff replay.

### 2.3 Supporting value objects

```
SubjectSpec       = { base_text: string, traits: Trait[] }
Trait             = { text, emphasis?, hint?, tag?, desc? }     -- same shape as the existing Trait
AssetSpec         = { path: string, weight: number, trigger?: string }
TrainingRecord    = { spec: TrainingSpec, output_path: string, method: string }
TrainingSpec      = { method, dataset: DatasetRef, params: table, output_tag? }
DatasetRef        = { type: "path" | "id", value: string }      -- VDSL holds the reference only
```

`DatasetRef` is intentionally a value object that carries a path or id and nothing more. The dataset contents themselves (images, annotations) are owned by the application layer.

## 3. Workflows (5)

| # | Workflow (JTBD)               | Required signals                                | Implementation |
|---|-------------------------------|-------------------------------------------------|----------------|
| 1 | Anchor authoring (in-source)   | base Subject / assets / variations              | Lua DSL `vdsl.anchor { ... }` or `vdsl.anchor.from(table)` |
| 2 | Variation render               | Anchor instance + optional variation name       | `Anchor:render(name?) -> vdsl.Subject` (composes via `Subject:with(trait_delta)`) |
| 3 | Assets flow into `Cast`         | Anchor.assets transferred to Cast slots          | `Cast{ anchor = A }` adapter expands `assets.loras` / `ipadapter` automatically |
| 4 | Training (LoRA bake)            | TrainingSpec (method / dataset / params)        | `Registry:train(spec)` invokes `training/<method>.run(spec)`, receives `lora_path`, appends `vN+1` |
| 5 | Persistence (application layer) | Serializable form                               | `vdsl.emit("anchor", reg)` writes JSON to `$VDSL_OUT_DIR`; `vdsl.anchor.from(table)` reconstructs |

WF1, 2, 3, and 5 are recombinations of existing assets (`Subject`, `Cast`, `training/`, `runtime/emit`). The **only genuinely new design surface is WF4** — wiring the `training/` output back into `Anchor.assets`.

## 4. Public API

```lua
-- Construction (entry point)
local reg = vdsl.anchor.from {                         -- pure constructor; receives a plain table from outside
  name = "shi",
  current = "v1",
  versions = {
    { version = "v1",
      base = { base_text = "young woman", traits = { ... } },
      assets = { loras = {{ path = "...", weight = 0.8 }} },
      variations = { evening = { ... trait deltas ... } },
    },
  },
}

-- Registry operations
reg:current()                                          -- -> Anchor.vN at the current pointer
reg:latest()                                           -- -> Anchor.vN at versions[-1]
reg:revert("v1")                                       -- -> Registry (current pointer moves; versions unchanged)
reg:train(training_spec)                               -- -> Registry (appends vN+1, sets current = vN+1)

-- Variation projection
local subj = reg:current():render("evening")           -- -> vdsl.Subject (1-shot projection)
                                                       -- render(nil) returns the base subject alone

-- Exit
vdsl.emit("anchor", reg)                               -- -> $VDSL_OUT_DIR/<name>.json
```

The symmetric pair `vdsl.anchor.from(table)` / `vdsl.emit("anchor", reg)` defines the boundary between Core and the application layer.

## 5. Serializable schema

All fields are JSON-pure (no Lua functions, no userdata). Only `string`, `number`, `boolean`, `table`, and `array` are used.

```
AnchorRegistry (root)
├ name        : string
├ current     : string                       -- version tag
└ versions[]  : Anchor                       -- each element matches §2.2

Anchor                                       -- as in §2.2
SubjectSpec / Trait / AssetSpec / TrainingRecord / TrainingSpec / DatasetRef
                                             -- as in §2.3
```

Size envelope: one `Anchor.vN` is roughly a few KB, so ten versions sit in a few tens of KB. This fits inside a single mini-app row, a single B2 object, or a single on-disk file — the application layer chooses.

## 6. Responsibility boundary

### 6.1 What VDSL (Lua) owns

- Entity shape (Registry / Anchor / supporting value objects)
- Immutable-copy semantics for `Anchor` and its parts
- The `:train` / `:revert` / `:render` / `vdsl.anchor.from` / `vdsl.emit` API surface
- Invoking `training/<method>` and treating the return value as a path-only result
- Composing variation overlays onto the base subject when projecting to `vdsl.Subject`

### 6.2 What VDSL does **not** own

- Choice or operation of any storage backend (mini-app / B2 / file / database)
- A wall-clock source (`created_at` is set by the application layer if at all)
- An `Anchor:load(name)` API — VDSL does not know about file paths or database keys. Instead, **the application layer reads the serializable table out-of-band and passes it through `vdsl.anchor.from(table)`** (pure construction).
- Persona / character / motif domain entities — these consume `Anchor`, they are not `Anchor`.

### 6.3 What the application layer owns (out of scope for this doc)

mini-app / B2 / file storage of registries, fetch and reconstruction, and any domain-specific entity such as `Persona` are all the responsibility of the application layer (MCP, separate Lua packages, or skills). From the application side, `Anchor` is consumed as an **identity-bearing portable entity**.

## 7. Feasibility summary

| Required material | Where it lives today | How Anchor uses it |
|---|---|---|
| Subject construction | `lua/vdsl/subject.lua` | Held as `Anchor.base.SubjectSpec`; `Anchor:render` rebuilds via `vdsl.subject(base_text):with(...)` |
| LoRA / IPAdapter slots | `lua/vdsl/cast.lua` (ad-hoc) | Expanded through a `Cast{ anchor = A }` adapter; the legacy ad-hoc path stays for backward compatibility |
| Training pipelines | `lua/vdsl/training/<method>` | Invoked from `Registry:train(spec)`; the only return value is `output_path` (training stays unaware of Anchor) |
| Emit / serialize | `lua/vdsl/runtime/emit.lua`, `runtime/serializer.lua` | `vdsl.emit("anchor", reg)` reuses the existing emit channel |

The from-scratch surface is small: **new entity files (`lua/vdsl/anchor.lua` and friends), a Cast adapter, and an emit type extension**. Everything else is recomposition.

## 8. Deferred items (out of MVP)

| Item | Reason for deferral | Expected revisit |
|---|---|---|
| Branch / fork (e.g. `v2-alt`) | Validate UX with a linear chain first | After MVP |
| Cross-anchor references (Anchor A referencing Anchor B) | Single-identity fixation comes first | Later, requirements permitting |
| Animation / motion variations (time-indexed overlays) | Still-image variations are the priority | Phase 2 onward |

## 9. References

- `lua/vdsl/subject.lua` — existing Subject entity that `Anchor.base` carries as `SubjectSpec`.
- `lua/vdsl/cast.lua` — destination for the assets flow described in WF3.
- `lua/vdsl/training/` — training DSL invoked by `Registry:train`.
- `lua/vdsl/runtime/emit.lua`, `runtime/serializer.lua` — the channel used by `vdsl.emit("anchor", ...)`.
- `docs/state-boundaries.md` — portable / environment-bound / workflow-state axes between vdsl and vdsl-mcp. Anchor lives strictly in the portable layer.

## 10. Decision log

| Decision | Adopted option | Rejected alternatives and why |
|---|---|---|
| Make Persona a VDSL first-class entity | No — Persona stays in the application layer | A persona-typed entity in Core would break the "scene-oriented / entity-free / 1-shot" invariant. With a domain-neutral `Anchor`, no Persona type is needed inside VDSL. |
| Core entity name | `Anchor` | `Series` foregrounds variation rather than identity fixation. `Fixture` carries an engineering tone that reads awkwardly for character anchors. `Pinned` is too verb-like and reads poorly on `Pinned:train`. `Subject` is already taken. |
| Versioning | Append-only versions + `current` pointer (string tags `vN`) | Diff-based storage forces replay on revert. Integer indices reduce readability of revert logs. |
| Training binding | `Registry:train(spec) -> vN+1`; `training/` is a path-returning function | Inverting the dependency (training knowing about Anchor) would create a two-way coupling between the entity and a method-specific module. |
| Persistence | Application-layer agnostic; only the `from` / `emit` boundary lives in VDSL | If VDSL had to know about files or databases, the Core would become environment-bound and lose its portable-layer property. |
| Style presets (WAI / anime / playful) | Not on `Anchor`; this is a World / checkpoint concern | Style is orthogonal to identity. Putting it on `Anchor` would cause the same persona to split into multiple anchors per style — a clear role conflict. |
| Branch / fork | Deferred from MVP | Validate UX with a linear chain first; introduce branching only if the linear model proves insufficient. |
