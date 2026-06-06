# ADR-0017 — Assemble Galley.app with a shell script on the swift build spine

## Context

The shell is a SwiftPM executable launched via `swift run` ([ADR-0011](0011-editor-shell-separate-swiftpm-package.md)), which explicitly deferred "producing a bundled, code-signed `.app`" and noted "this ADR will need a follow-up." That follow-up is now due: registering `.galley` as a macOS package and opening it on double-click (Phase B2) both require a real `.app` bundle with an `Info.plist` that Launch Services can read. SwiftPM does not emit a `.app` bundle.

Three approaches were considered:
- **(A) Shell script** that runs `swift build -c release`, assembles `Galley.app/Contents/{Info.plist,MacOS,PkgInfo}`, and copies the executable in.
- **(B) Xcode project** wrapping the package to manage the bundle.
- **(C) Third-party SwiftPM bundler plugin** (e.g. `swift-bundler`).

## Decision

Use **approach A**: a committed `scripts/bundle.sh` that assembles `Galley.app` from the release build. The `Info.plist` source of truth lives at `app/Packaging/Info.plist` — outside `app/Sources/` so SwiftPM never treats it as an unhandled target resource — and is copied verbatim into the bundle. Output goes to `dist/Galley.app`, which is git-ignored. The `swift run` development path is unchanged.

## Consequences

- The project stays entirely on the `swift build` / `swift run` / `swift test` spine (ADR-0011) — no Xcode project artifact to maintain, no third-party dependency, and the whole assembly is transparent and auditable in ~40 lines.
- The bundle is **ad-hoc code-signed** (`codesign --sign -`) so Launch Services treats it as a stable, registrable app for the Phase B2 double-click flow and Gatekeeper does not flag it as damaged. Distribution signing and notarization are a further deferred concern this script is the natural home for.
- `Info.plist` is hand-maintained at `app/Packaging/Info.plist` rather than generated. This is the single place future bundle metadata (icons, version bumps, entitlements) is edited.
- The `.app` is not unit-testable; its acceptance gate is a manual smoke check (`bash scripts/bundle.sh` then `open dist/Galley.app`). This is the project's first acceptance criterion the CI/`swift test` spine cannot verify — an accepted cost of OS-integration work, flagged in plan review.
- This constrains how signing/notarization is added later: it extends `bundle.sh`, not a migration to Xcode.

## Session

9ffa6f (2026-06-05) — Build Step 3.5, Phase B1.
