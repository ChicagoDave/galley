# ADR-0018 — Route open-document events through AppDelegate, keep WindowGroup

## Context

Registering `.galley` as a document type ([ADR-0019](0019-galley-as-macos-package-type.md)) means the OS now delivers open-document events to the app: Finder double-click, the `open` CLI, and drag-to-dock. The shell must receive these and open the package in the existing workspace. Two structures were considered:

- **(A) Keep `WindowGroup` + `@NSApplicationDelegateAdaptor`**, and handle `application(_:open:)` / `application(_:openFile:)` in the `AppDelegate`, routing each URL into the already-tested `WorkspaceModel.open(url:)`.
- **(B) Adopt SwiftUI `DocumentGroup`**, restructuring the app around `FileDocument`/`ReferenceFileDocument`.

A complication for either: a Finder double-click can deliver the open event before the SwiftUI scene's `@State` is established, so the workspace cannot be owned solely by view state.

## Decision

Use **approach A**. The `AppDelegate` (already present for the activation-policy fix) gains two thin delegate methods that forward URLs to `WorkspaceModel.open(url:)`. The single `WorkspaceModel` is held in an app-side holder, `AppWorkspace.shared`, which both the delegate and the SwiftUI scene read, so an early open event and the scene act on one store. `DocumentGroup` is rejected.

## Consequences

- The decision logic stays in `WorkspaceModel.open(url:)` — AppKit-free, in GalleyShell, headlessly tested (ADR-0011). The delegate methods do no logic of their own, so the OS-integration surface that cannot be unit-tested is kept as thin as possible.
- `AppWorkspace.shared` is process-wide singleton state. This is acceptable precisely because the app is single-window with exactly one workspace; it is executable glue, not domain state, and does not compromise `WorkspaceModel`'s purity. A future multi-window design would have to revisit this holder.
- Keeping `WindowGroup` preserves the multi-buffer workspace model (Build Step 3) intact; `DocumentGroup` would have forced a window-per-document model that conflicts with it.
- All future file-open entry points (double-click, `open` CLI, drag-to-dock) dispatch through this one path.

## Session

9ffa6f (2026-06-05) — Build Step 3.5, Phase B2.
