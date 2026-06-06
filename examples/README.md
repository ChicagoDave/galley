# Examples

## `GrayHarbor.galley`

A sample Galley project package demonstrating the reference system (§9). On macOS,
Finder presents the `.galley` directory as a single document (it is registered as a
package, ADR-0019); other tools see a plain directory.

Layout:

```
GrayHarbor.galley/
  prose.txt              the writer-owned plain-text prose (ADR-0007)
  bible/                 one Markdown file per entity — the read-only bible panel
    aldous-finch.md      name derived from filename; a leading "# Heading" overrides it
    gray-harbor.md
  snippets/              one .txt file per reusable text block — inserted via @
    dateline.txt
    chapter-epigraph.txt
```

(No `sidecar.json` is included — a prose-only package opens fine; the sidecar is
written on first save.)

To try it: build the app (`bash scripts/bundle.sh`) and open the package, then —

- **Bible panel:** press **⌘⇧B**, search, and click an entry to read its note.
- **Snippets:** type `@` in the prose (e.g. `@date`) and pick a snippet to insert
  its text. Multi-line snippets (like `chapter-epigraph`) insert as paragraphs.
- Hold **⌘** to reveal the bottom-bar buttons' keyboard shortcuts.
