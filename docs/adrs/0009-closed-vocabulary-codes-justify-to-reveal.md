# ADR-0009 — Closed vocabulary; every code must justify itself to the reveal

## Context

The death of a tool like this is scope creep (§2), and the WordPerfect pain being avoided is open "code soup." The constraint — a tiny, closed vocabulary the writer thinks in — is the art, not a limitation. New codes are cheap to add and expensive to live with, since every code shows up as an addressable object in the reveal ([ADR-0006](0006-reveal-is-a-projection-and-slicing-surface.md)).

## Decision

Fix the vocabulary: block set = Paragraph, SceneBreak, SetPiece; inline = italic; structure = chapter cut. Any addition must justify itself to the reveal before it enters the vocabulary.

## Consequences

- Keeps the reveal legible and the product focused; resists code-soup.
- Some writers will want more (small-caps, centered one-offs); these are handled as rare per-block presentation overrides, not vocabulary growth.
- The override hatch is itself bounded: modeled as a small **closed** `PresentationOverride` enum on `Block` (overview §4), empty by default, so "rare override" can't quietly become an open style system. Adding a case demands the same justification as any new code.
- Because italic is named inline vocabulary, an **explicit** italic mark (`Run.italic`) is itself a code and therefore surfaces in the reveal as addressable `[i]`/`[/i]` chips ([ADR-0006](0006-reveal-is-a-projection-and-slicing-surface.md): every code is an object). This is distinct from **derived** italic — a set-piece is italic by *kind*, not by a run mark, so it carries no `[i]` chips (matching the §7 verse example). The rule: only marks stored on the model are revealed; presentation derived from a block kind is not.

## Session

ca5fff (2026-06-05) — extracted from overview §12, ADR-009.

54ff60 (2026-06-05) — added the explicit-vs-derived italic consequence after Phase 4's `revealProjection` made the distinction concrete (`[i]`/`[/i]` chips for `Run.italic`; none for kind-derived italic).
