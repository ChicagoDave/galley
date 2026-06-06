# ADR-0019 — `.galley` is a macOS package type (complements ADR-0007)

## Context

A `.galley` document is a directory holding `prose.txt` + `sidecar.json` ([ADR-0007](0007-plain-text-files-chapters-in-sidecar.md)). With no document-type registration, the OS treated it as an ordinary folder: Finder opened it inward rather than into Galley, and it presented as a folder of loose files instead of one document. The fix must give the single-document feel users expect **without** abandoning ADR-0007's commitment that the prose stays plain, writer-owned, independently-openable text.

Two ways to make a `.galley` feel like one file:
- **Package** — a directory the OS presents as a single opaque file (as `.pages`, `.rtfd`, `.key`, `.app` do), via an exported UTI conforming to `com.apple.package`. On disk it stays a directory.
- **Container** — a real single file (zip or custom binary) holding the prose and sidecar.

## Decision

Register `.galley` as a **package**. The app declares an exported UTI `com.galley.project` conforming to `com.apple.package` and `public.composite-content`, tagged to the `galley` filename extension, and a `CFBundleDocumentTypes` entry with `LSTypeIsPackage = true` and `LSHandlerRank = Owner`. The **container (zip/binary) option is explicitly rejected.**

This **complements ADR-0007; it does not supersede it.** The on-disk layout is unchanged.

## Consequences

- Finder presents a `.galley` directory as a single file and routes double-click to Galley ([ADR-0018](0018-open-document-routing-via-appdelegate.md)), while `prose.txt` remains a plain text file any editor can open by navigating into the package (Finder ▸ Show Package Contents, or any non-Finder tool). ADR-0007's portability/diffability/ownership properties are fully retained.
- `DocumentBundle` (GalleyShell) needs no change — the package boundary is an OS/Finder perception layer only, not a storage-format change.
- The package decision lives entirely in `Info.plist` (executable/build side), respecting ADR-0011; GalleyCore and GalleyShell are untouched.
- The UTI `com.galley.project` is now a public identity for the format; changing it later would orphan existing Launch Services associations.
- Acceptance is a manual smoke check (Finder single-file presentation + double-click open); the OS registration cannot be verified on the `swift test` spine.

## Session

9ffa6f (2026-06-05) — Build Step 3.5, Phase B2.
