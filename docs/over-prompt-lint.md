# Over-prompt lint

`vdsl.check` runs a warn-only **over-prompt lint** that flags a prompt whose
single category has been piled too high — typically lighting words washing an
image out ("light burn"), or 2D-style words flattening a photoreal subject
("cartoonification"). It never blocks or rewrites; it only emits warnings the
author is free to ignore.

The lint lives in `vdsl.lint.over_prompt` and is invoked automatically inside
the compiler's `check` pass, so it surfaces through every entry point:
`vdsl.check(opts)`, `Shot:check()`, and `compiler.check(opts)`.

## Why category, not length

Over-prompt is not "too many words overall". A clean hand-written prompt and an
over-prompted one often have the same total clause count, quality boosters, and
weights. What differs is **one category overflowing**:

- **light** — illumination / glow / atmosphere words stacked past what the scene
  needs. Predicts a blown-out, washed image.
- **lock** — 2D / flat / line-art words stacked on a subject. Predicts a flat,
  cartoonified result.

The usual cause is *double-anchoring*: a `:quality()` / `:style()` preset already
occupies that dimension, and supplementary words pile on top of it.

## How it classifies

The lint reads `Subject:resolve_grouped()` output. Preset traits land in the
`quality` / `style` groups (the **anchors**); everything else — including bare
`:with()` traits and `vdsl.cam` overlays — collapses into the `detail` group.
Because structural category alone cannot tell a lighting word from a 2D word in
that `detail` bucket, a static **lexicon** classifies each supplementary clause,
and the non-empty `quality` / `style` groups act as the "anchor present" signal.

Each clause is counted once (first matching lexcat wins), and a category warns
when its supplementary count exceeds the budget:

| lexcat  | default budget | predicts        |
|---------|----------------|-----------------|
| light   | 3              | light burn      |
| lock    | 2              | cartoonification|
| quality | 5              | quality bloat   |

## Reading the warnings

Warnings are plain strings in the `warnings` array, prefixed with the cast
locator:

```
cast[1] over-prompt: light x6 supplementary (budget 3) -> warm amber evening light / golden glow / moody / warm tones / autumn atmosphere / soft bokeh
```

The offending clauses are named, so the fix is mechanical: drop or fold the
duplicates back toward the preset anchor.

```lua
local diag = vdsl.check {
  world = w,
  cast  = { vdsl.cast { subject = subj } },
}
for _, w in ipairs(diag.warnings) do
  if w:find("over-prompt", 1, true) then print(w) end
end
```

## Intent: silencing a deliberate over-prompt

Whether a blown-out highlight is a mistake or a deliberate strong look is a
choice only the author can make. `Shot:intent(category)` is the "ignore" side of
warn-and-ignore: it suppresses that category's warning and records the intent on
the Shot as provenance (it survives clone / serialize).

```lua
local shot = vdsl.render { world = w, cast = { vdsl.cast { subject = subj } } }
  :intent("blown-highlight")   -- silence the light over-prompt warning

shot:check()   -- no "over-prompt: light" warning
```

`category` may be a lexcat (`"light"`, `"lock"`, `"quality"`) or a friendly
alias (`"blown-highlight"`, `"stylized"`, ...). Raw opts also work:
`vdsl.check { ..., intents = { light = true } }`.

## Configuration

The default lexicon and budgets are tuned for cam-style photoreal / anime
portraits. They are plain module fields and can be overridden before checking:

```lua
local op = require("vdsl.lint.over_prompt")
op.BUDGET.light = 4                      -- loosen the light budget
op.LEXICON.lock[#op.LEXICON.lock + 1] = "chibi"  -- extend the 2D lexicon
```

## Limitations

- The lexicon is static, not catalog-derived. New vocabulary (synonyms,
  other languages) must be added to `LEXICON`.
- Budgets are calibrated against a photoreal hand-written baseline; an anime
  hand-written clean baseline would tighten the `lock` band.
- Detection is substring-based per clause; it does not understand weights
  (`(word:1.3)`) as intensity.
