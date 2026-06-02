# Dedup lint (Warn + Fix)

`vdsl.lint.dedup` removes verbatim duplicate clauses from a prompt. Unlike the
over-prompt lint (which only *warns*), dedup follows the ESLint model: it both
**reports** duplicates (a warning in the check pass) and **fixes** them (drops
the repeats in the compile path). The fix is on by default and can be disabled
per render with `no_lint_fix = true`.

## Why dedup

Composing a Subject from many catalog traits can stack the same token twice —
e.g. `portrait_lens` and `shallow_dof` both contribute `bokeh`, or two negative
sources both contribute `deformed face`. A repeated token adds no meaning to a
CLIP prompt; it just spends tokens (and very mildly over-weights the term). The
dedup fix keeps the first occurrence and drops the rest.

## What counts as a duplicate

A *clause* is one comma-separated prompt token. Comparison is **exact and
case-insensitive**, keep-first.

- `bokeh` and `bokeh` → duplicate (second dropped)
- `Bokeh` and `bokeh` → duplicate (case-insensitive)
- `bokeh` and `(bokeh:1.2)` → **distinct** — emphasis is part of the clause text,
  and we never reinterpret a weight as intensity (see `over-prompt-lint.md`).
  Only verbatim repeats are removed, so the fix is meaning-preserving.

## Paren-aware splitting

Splitting into clauses is parenthesis-aware: a weighted group such as
`(warm tones, warm color palette:1.1)` carries an internal comma but is a single
clause, so commas inside parentheses do not split it.

## Warn vs Fix

| | mechanism | when |
|---|---|---|
| **Warn** | `dedup.check(grouped)` → findings (`kind = "duplicate"`) surfaced in `diag.warnings` | `vdsl.check()` / check pass |
| **Fix** | `dedup.fix(text)` applied to the assembled positive / negative prompt | compile path (`vdsl.render()`) |

A clean (no-duplicate) prompt is returned byte-identical by the fix — comma
spacing is never re-normalized unless a duplicate was actually removed.

## Disabling the fix: `no_lint_fix`

```lua
vdsl.render {
  world = w,
  cast  = { vdsl.cast { subject = s } },
  no_lint_fix = true,   -- keep duplicates verbatim (skip the autofix)
}
```

Use this when a duplicate is intentional (e.g. deliberate repetition for
emphasis). `no_lint_fix` controls the **fix** only; the **warning** is silenced
separately via intents (below).

## Silencing the warning: intents

Like over-prompt, the dedup warning is silenced through the intents mechanism:

```lua
-- Shot form
shot:intent("dedup")

-- raw opts form
vdsl.check { world = w, cast = { ... }, intents = { dedup = true } }
```

## Limitations

- Exact-match only. Near-duplicates (`bokeh` vs `soft bokeh`, singular vs plural)
  are not collapsed — that would require semantic judgement.
- Emphasis-distinct clauses (`word` vs `(word:1.2)`) are kept separately.
- The warn side operates on `Subject:resolve_grouped()` (pre-atmosphere,
  pre-strategy-reorder); the fix operates on the fully assembled prompt. Both
  catch the same verbatim duplicates.

## Module API

- `dedup.split(text) -> { clause, ... }` — paren-aware comma split
- `dedup.fix(text) -> string` — drop verbatim duplicates (no-op if none)
- `dedup.check(grouped, intents) -> { findings }` — duplicate findings for warnings
- `dedup.format(finding) -> string` — human-readable warning line
