# ADR-0023 — Applying a template via a single `insertBlock` reducer op

## Context

The Block Palette (BP2) inserts structure at the caret from the keyboard (Cmd-;) — the writer never leaves the keyboard to create a block (memory: keyboard-first-writing-ux). Picking a palette row must produce a **real, editable block** seeded with initial content and the template's presentation overrides, inserted immediately after the current block.

Two ways to apply it were considered:

- **Option A** — a single new `InputEvent.insertBlock(content:overrides:afterBlockID:)` case, handled by a new arm of the pure `applyInput` reducer in `GalleyCore`. One atomic step.
- **Option B** — an app-layer sequence of existing ops (`splitParagraph` + `insertText` + a new `setOverrides` op), composed in the `InputController`.

## Decision

**Option A.** A new `InputEvent.insertBlock(content: BlockContent, overrides: [PresentationOverride], afterBlockID: BlockID)` case, with a reducer arm that mints a fresh block ID (ADR-0010), builds a `Block` with the given content and overrides, and inserts it immediately after `afterBlockID`. Like every other arm it is **pure and total**: an unknown `afterBlockID` returns the document unchanged rather than throwing, so a stale palette event can never crash editing. Cuts are untouched — the new block carries a never-reused ID that no cut anchors to, and inserting *after* an existing anchor never shifts another block's offsets.

The caret is **not** part of the reducer: `Document` has no caret (it is a view concern, ADR-0004). After dispatch, the `InputController` finds the block now sitting after the anchor and places the caret at its start.

### Palette scope refinements (recorded so a future session does not re-litigate)

- **Built-in block types are limited to Scene Break in v1.** The plan listed the set-piece kinds (verse/epigraph/letter) as palette built-ins, but `EditorLayout` marks set-pieces (and scene breaks) **non-editable** — a documented Phase-3 limit. Inserting an empty set-piece the caret cannot enter would violate the palette's "real, editable block" promise. A user template with `align:center` + `smallCaps` already serves the epigraph need as an editable paragraph. Set-pieces re-enter the palette once they are inline-editable. The existing Cmd-Shift-V verse toggle (paragraph → set-piece) is unaffected.
- **All palette insertions go through `insertBlock`, including Scene Break.** The plan's wording suggested built-ins dispatch the existing `makeSceneBreak` / `toggleSetPiece`, but those *transform the current block* (and `makeSceneBreak` would destroy a non-empty paragraph's text). The palette's job is to *insert* structure after the caret, never to overwrite the current block — so every row dispatches `insertBlock`. `makeSceneBreak`/`toggleSetPiece` remain correct for the typing-driven path (`#` on an empty line, the verse toggle).
- **A template is a single editable paragraph in v1.** The inserted block is `.paragraph(runs:)` seeded with the template body; a stray newline is flattened to a space so the block stays one logical paragraph. Multi-paragraph templates are deferred (they would require either a multi-block insert or a fenced block kind — neither justified yet).

## Consequences

- Insertion is one atomic, headlessly-testable step in the pure core, where the `Block`/`Document` invariants (ADR-0010: monotonic IDs, no reuse) are enforced. `InsertBlockTests` asserts position, content, overrides, the advanced counter, the unknown-anchor no-op, and a sidecar round-trip of a palette-inserted `blockQuote` block.
- The reducer's public surface grows by one case. Because `insertBlock` takes a full `BlockContent`, it already supports inserting any block kind (paragraph, scene break, set-piece) — the palette's v1 scope is a UI choice, not a reducer limit, so widening the palette later needs no core change.
- The palette UI (`BlockPalettePopover`, the Cmd-; key path) is a sibling to `SnippetCompletionPopover`, following the project's parallel-surface convention (BibleIndex/SnippetIndex/TemplateIndex) rather than a shared base. It is AppKit-bound; its acceptance is the manual smoke check, backed by the real-path `InsertBlockTests`.
- Build Step 2 is complete with this phase.

## Session

bf5f1f (2026-06-06) — Phase BP2. Option A chosen as planned. Recorded the palette-scope refinements (Scene-Break-only built-in; everything via `insertBlock`; single-paragraph templates) so they are not re-opened by default.
