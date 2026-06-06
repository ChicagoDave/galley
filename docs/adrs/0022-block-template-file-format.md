# ADR-0022 — Block-template file format: per-file front-matter + body

## Context

The Block Palette track (BP1/BP2, superseding the reverted Phase 6) lets writers define reusable, pre-composed blocks — a centered epigraph, a small-caps dateline, a set-off inscription — and insert them as real, editable blocks from a keyboard-summoned palette (memory: keyboard-first-writing-ux). BP1 builds the headless source for those templates: where they live on disk, how they parse, and the closed presentation vocabulary they may carry.

Two existing patterns constrain the choice. The bible (`bible/*.md`) and snippets (`snippets/*.txt`) already live as **per-file package sources** inside the `.galley` package, loaded by indexes in `GalleyShell` ([ADR-0020](0020-bible-index-in-app-layer.md)), parsed by hand with no external dependency, and edited directly in any text editor. The sidecar already encodes per-block presentation overrides as a **closed token vocabulary** ([ADR-0009](0009-closed-vocabulary-codes-justify-to-reveal.md)) — and a template-inserted block must round-trip through that same sidecar identically, or the template would be able to express a presentation the file format cannot persist.

## Decision

**Templates are per-file package sources at `templates/*.galley-template`** inside the `.galley` package, one template per file, consistent with `bible/` and `snippets/` (ADR-0020). No in-app editor — the writer edits these files directly (deferred, see Consequences).

**File format** — a hand-rolled front-matter followed by body text, analogous to how `BibleIndex` parses `# heading` lines:

- The **front-matter** is the maximal run of leading lines of the form `override: <token>`, one override per line, in order.
- A single **blank line** after the front-matter separates it from the body (consumed; optional when there is no front-matter).
- The **body** is the remaining text verbatim, with only the trailing newline most editors append trimmed (interior blank lines preserved, so a multi-paragraph template body survives).
- A file that begins with prose (no leading `override:` line) has **no front-matter and is all body** — a plain reusable block.

No YAML/TOML/JSON dependency: the parser is a few lines of `String` handling in `GalleyShell.BlockTemplate.parse`, matching the project's hand-rolled-parser precedent (Storage's Fountain-for-prose reader, BibleIndex).

**Override tokens are the *same* closed vocabulary the sidecar uses, decoded through one shared codec.** The token ↔ `PresentationOverride` mapping that was private to `Storage.swift` is lifted to a public `PresentationOverride.token` / `init?(token:)` on the enum in `GalleyCore`. `Storage.swift` (sidecar) and `TemplateIndex` (template front-matter) both decode through it. This is the co-located wire-type-sharing rule (DEVARCH 8b): a single source of truth means the two on-disk formats can never disagree on what `align:center` means, and any future override case lights up both readers in the same commit.

**An unknown override token is a hard rejection, never a silent skip.** `init?(token:)` returns `nil` for any token outside the closed vocabulary; `BlockTemplate.parse` turns that `nil` into a thrown `TemplateParseError.unknownOverrideToken`, rejecting the whole template rather than parsing the recognized overrides and dropping the unknown one. This mirrors `Storage.decodeOverride`'s existing behavior for the sidecar (it throws `ParseError.unknownOverrideToken`) and resolves carry-forward plan-review tension #2. The directory loader (`TemplateIndex.load`) is tolerant at the *file* level — a wholly-malformed file is omitted so one bad template never breaks the writer's whole palette — but the per-file parser is the strict gate, and it is the directly-tested unit.

The `.galley-template` extension (not `.txt`) is deliberate: it disambiguates templates from snippets in the same package mental model and lets the loader filter the directory unambiguously.

## Consequences

- Templates are plain, version-controllable, externally-editable files — no opaque store, consistent with ADR-0007/ADR-0020. A writer can author a template in TextEdit.
- The closed override vocabulary is enforced identically across the sidecar and templates by construction (one codec), so a templated block always round-trips through `serialize`/`parse` losslessly. The BP1 tests assert this both ways (GalleyCore sidecar round-trip; GalleyShell front-matter decode).
- **In-app template editor is deferred.** Templates are files the writer edits directly. A future session must not re-litigate this without cause (noted so it is not re-opened by default).
- **Chapter-heading-as-typed-block is deferred.** An `align:center` + `smallCaps` template already serves as a chapter heading; a hardcoded `chapterHeading` block kind would expand the closed vocabulary beyond justification (ADR-0009).
- The format is line-oriented and additive: a future front-matter directive (should one ever be justified) slots in as a new recognized prefix without breaking existing files. The override directive is the only one defined today.
- BP2 consumes this index: the palette lists `TemplateIndex.entries`, and picking one inserts a block seeded with the template's body and overrides (the insertion op is ADR-0023, BP2).

## Session

bf5f1f (2026-06-06) — Phase BP1. Written alongside the ADR-0009 amendment that adds `blockQuote` to the closed vocabulary (see [ADR-0009](0009-closed-vocabulary-codes-justify-to-reveal.md)). Supersedes the reverted Phase 6 ADR-0022 (chapter-openers-reuse-snippets), which was deleted in the revert; this is a fresh use of the number.
