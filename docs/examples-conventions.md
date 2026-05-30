# Example-Authoring Conventions

`examples/` ships in a public repo. Examples are read, copied, and pasted by
strangers, so they must be self-contained, safe, and must not pin anyone to a
specific machine or a hard-to-find model.

## 1. The generation model must be injectable

Never freeze a checkpoint name into an example's generation path. Read it from
an environment variable with a sensible default:

```lua
local w = vdsl.world {
  model = os.getenv("VDSL_MODEL") or "waiIllustrious_v16.safetensors",
  clip_skip = 2,
}
```

- **Why injectable**: the reader almost certainly has a different checkpoint
  installed. `os.getenv("VDSL_MODEL")` lets them run the example unchanged
  (`VDSL_MODEL=my_ckpt.safetensors lua examples/...`), and it stops "whatever
  model I happened to be testing" from getting frozen in as the canonical one.
- **Canonical default**: use `waiIllustrious_v16.safetensors` for generic /
  character examples. It is a widely available SFW Illustrious-family SDXL
  checkpoint, so the default actually resolves for most readers.
- **Domain showcases keep their domain model** as the default (still
  injectable): e.g. the Z-Image examples default to
  `z_image_turbo_fp16.safetensors` because the example is specifically about
  that model family. The rule is *injectable*, not *one fixed name*.

### Exception: Profile DSL examples

Profile DSL examples (`vdsl.profile{...}`) declare a pod's model manifest —
there the checkpoint name (`models[].dst` / `src`, vLLM `model` path) is the
*subject* of the demonstration, not a generation knob, so it stays literal.

## 2. No machine- or user-specific references

Examples (and all committed public-repo content) must not contain:

- **Absolute home paths** — `/Users/<name>/...` and the like. Use relative
  paths or environment variables.
- **Private or local-only tooling paths** — anything that points at a
  personal machine's local tooling layout rather than something a reader can
  reproduce. Describe behavior abstractly instead of citing a private path.
- **Personal identities** — do not hard-code a specific real or personal
  identity as the subject. Use a neutral generic identity
  (`vdsl.subject("1girl, solo, 20 years old")`) for examples.

## 3. SFW only

`examples/` and the framework are SFW. Do not put explicit NSFW vocabulary in a
*positive* prompt. Negative-prompting such terms to suppress them (e.g.
`negative = vdsl.trait("...")`) is fine and expected — that is how you keep
output SFW.

## See also

- `docs/cam-and-identity.md` — cam / identity model (uses a generic identity)
