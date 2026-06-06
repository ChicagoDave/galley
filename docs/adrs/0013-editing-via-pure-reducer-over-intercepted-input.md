# ADR-0013 — Editing translates intercepted input into a pure model reducer

## Context

Build step 2, Phase 3 wires real editing. The §4 model is the source of truth
([ADR-0004](0004-own-model-is-source-of-truth.md)) and chapter cuts anchor to
stable block identities ([ADR-0010](0010-cut-anchoring-via-stable-block-ids.md)),
so every keystroke must mutate the *model*, never a detached text buffer. Three
ways to connect `NSTextView` to the model were considered: intercept input and
drive a reducer; let the text view edit freely and re-`parse` its string on every
change; or back the view with a TextKit 2 `NSTextElementProvider`.

## Decision

Intercept the text view's primitive editing actions and translate each into a
model-coordinate `InputEvent`, applied by a pure reducer:

- **`InputEvent`** (core) names editing intents in model coordinates — a
  `BlockID` and a character offset — never text-view positions.
- **`applyInput(_:to:) -> Document`** (core) is a pure, total reducer: it maps an
  event to a new document, delegating structural edits to the block-lifecycle
  operations (ADR-0010) so cut anchoring is preserved, and returning the document
  unchanged for an event that does not apply. It is unit-tested headless.
- **`InputController`** (shell) is an `NSTextView` subclass that overrides
  `insertText` / `insertNewline` / `deleteBackward` and the italic shortcut, maps
  the caret to `(blockID, offset)` via **`EditorLayout`**, applies the event
  through `DocumentModel`, then re-derives the whole rendered string from the
  model and restores the caret. It never edits the text storage as a source of
  truth — the storage is a render target.

Smart typography (curly quotes, em dash, ellipsis) is a pure core helper
(`smartTypography`) applied inside the reducer, so it is identical everywhere and
tested without a view.

The rejected alternatives: re-`parse` on every edit re-mints block IDs, rotting
every cut anchor on each keystroke (violates ADR-0010); a full
`NSTextElementProvider` is the most idiomatic TextKit 2 design but a large surface
to land before basic editing is proven — deferred.

## Consequences

- The editing logic — the risky part — is pure and headlessly tested; the
  reducer has behavioral tests asserting on resulting document state for every
  event, including rejection.
- The model can never drift from the view: the view is a pure function of the
  model, re-derived after each edit.
- Two known costs, both carrying a manual smoke check rather than a unit test:
  the caret ↔ model offset mapping (`EditorLayout`) is AppKit glue, and replacing
  the TextKit 2 content storage wholesale does not auto-repaint — the view is
  forced to re-lay-out the viewport after each render.
- Whole-document re-render per keystroke is acceptable at a scene's scale;
  incremental rendering is a later optimization.
- Phase 3 scope: paragraphs, scene-break deletion, italic, and the set-piece
  toggle are wired live; in-set-piece line editing renders but is edited by
  toggling, and creating chapter cuts is Phase 4. Caret after the em-dash /
  ellipsis substitutions may sit one or two places off until refined.

## Session

6baa7e (2026-06-05) — Build step 2, Phase 3.
