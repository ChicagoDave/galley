# Session Plan: macOS Editor Shell (Build Step 2)

**Created**: 2026-06-05
**Overall scope**: Build the Mac-only editor shell that sits on top of the complete, headless `GalleyCore` library — covering the SwiftUI/AppKit app target, `displayProjection`, typing-simplicity input rules, the reveal pane with chapter-slicing, the reference system (peek + @-bible), and chapter-opener templates. All new code lives in a new app target; `GalleyCore` is imported, never modified to accept UI types (ADR-0002, rule 8).
**Bounded contexts touched**: N/A — infrastructure/app-layer work. The domain model is complete in `GalleyCore`; this build step is a rendering and input layer over it.
**Key domain language**: displayProjection, RevealToken, ChapterCut, TypingRule, BibleEntry, PeekOverlay, TemplateRef

---

## Phases

### Phase 1: App target scaffold + open/save file pair
- **Tier**: Small
- **Budget**: 100 tool calls
- **Domain focus**: Infrastructure prerequisite for all UI phases — establishes the macOS app target, its dependency on `GalleyCore`, and round-trip file I/O through the core's `parse`/`serialize` surface.
- **Entry state**: Build step 1 complete and committed at `83276c2`. `swift build` and `swift test` pass in `core/` (48 tests GREEN). No app target exists in the repo. Working environment is macOS with Swift 6.3; AppKit/SwiftUI are available.
- **Deliverable**:
  - A new SwiftPM executable target (e.g. `Galley` or an `app/` directory with its own `Package.swift` or as a new target in `core/Package.swift`) that declares a dependency on the local `GalleyCore` package.
  - A minimal SwiftUI `App` struct that opens on launch — a single window, plain white, no editing yet.
  - `DocumentModel`: a thin `@Observable` (or `ObservableObject`) wrapper holding a `Document` value; opened/saved via `GalleyCore.parse` and `GalleyCore.serialize`. Wire to `NSOpenPanel`/`NSSavePanel` so the user can open a `.galley` prose+sidecar pair and save it back.
  - The dependency boundary is enforced: `GalleyCore` imports only `Foundation`; the app target imports `SwiftUI`/`AppKit`. No AppKit type leaks into `GalleyCore`.
  - ADR-worthy decision: **app-target structure** — separate SwiftPM package vs. additional target in `core/Package.swift`; record the choice and rationale.
  - Smoke-check verification: launch the app, open a test `.galley` file created by the core tests, close, re-open — document content survives the round-trip.
- **Exit state**: `swift build` succeeds for the app target with zero warnings. The app launches, opens a file, and saves it without data loss. The `GalleyCore` target has no new AppKit imports. Committed.
- **Status**: COMPLETE — separate SwiftPM package `app/` (ADR-0011): `GalleyShell` library (`DocumentBundle` file-pair I/O) + `Galley` `@main` SwiftUI executable (`DocumentModel` open/save via `NSOpenPanel`/`NSSavePanel`, `ContentView`). `.galley` bundle = directory of `prose.txt` + `sidecar.json` (ADR-0007). `swift build` clean (0 warnings); 4 real-path round-trip tests GREEN; app launches (run loop alive, no crash). Core unchanged — no new AppKit imports. (session 6baa7e, 2026-06-05)

---

### Phase 2: `displayProjection` — pure display tokens in core, NSAttributedString attribution in the shell
- **Tier**: Medium
- **Budget**: 250 tool calls
- **Domain focus**: The companion render function to `revealProjection` — the clean reading/writing view. This phase resolves the open design question of where `displayProjection` lives and implements it.
- **Entry state**: Phase 1 exit state — app target builds and launches.
- **Deliverable**:
  - **Design decision (ADR-worthy):** Resolve where `displayProjection` lives.
    - Option A: `GalleyCore` emits a `[DisplayToken]` enum (plain values, no AppKit) — same pattern as `RevealToken`. The shell converts tokens to `NSAttributedString` in a separate attribution step.
    - Option B: `displayProjection` lives entirely in the shell, returns `NSAttributedString` directly.
    - Recommendation for the planner: Option A keeps the core testable headlessly and consistent with `revealProjection`'s pattern (ADR-0004, ADR-0006 both say "two pure render functions"). **Assume Option A unless the user corrects this.** State the assumption explicitly in the ADR.
  - If Option A: `DisplayToken` enum and `displayProjection(_ doc: Document) -> [DisplayToken]` added to `GalleyCore`, with no AppKit imports. Behavioral tests for `displayProjection` in `GalleyCoreTests` — asserting on token sequence for each block type (paragraph typography, scene break, set-piece centering/italic, presentation overrides, chapter cut splice points).
  - An `Attribution` module in the shell that maps `[DisplayToken]` → `NSAttributedString`, applying the closed typographic vocabulary (paragraph indent, verse centering, italic, scene-break ornament). This module is AppKit-only and has no tests in the headless suite; it gets a launch smoke check (described below).
  - Integration Reality Statement produced before closing this phase: the Attribution module is an OWNED dependency of the shell; at least one real-path check (launch the app, open a document, confirm the paragraph/verse/scene-break rendering is visually correct) backs any stub used in development.
  - The `NSTextView` host (`NSViewRepresentable` wrapper per ADR-0003) is scaffolded and wired to `DocumentModel`, displaying the `NSAttributedString` from `Attribution`. Editing is not yet wired — the text view is read-display-only at this phase exit.
  - Smoke-check verification: launch the app, open a document with paragraphs, a scene break, and a verse block; confirm the three block types render distinctly and correctly (centered italic verse, `* * *` ornament, indented paragraph).
- **Exit state**: `GalleyCore` test suite remains at 48+ GREEN (no regressions; new `displayProjection` tests added). App launches and renders a document visually correctly. `displayProjection` design decision recorded as ADR. Committed.
- **Status**: COMPLETE — Option A chosen (ADR-0012): `DisplayToken`/`DisplaySpan` + `Document.displayProjection()` in `GalleyCore` (pure values, chapter-cut splicing incl. mid-paragraph offset splits with italic preserved); 11 behavioral tests added (core now 59 GREEN, 0 warnings). Shell: `Attribution` ([DisplayToken]→NSAttributedString, the closed typographic vocabulary) + `DocumentTextView` (read-only TextKit 2 `NSTextView` via `NSViewRepresentable`, ADR-0003) wired into `ContentView`. App builds clean and launches; sample bundle rendered for manual visual check. (session 6baa7e, 2026-06-05)

---

### Phase 3: Typing-simplicity input rules wired to core lifecycle ops (§8)
- **Tier**: Medium
- **Budget**: 250 tool calls
- **Domain focus**: The §8 typing-simplicity behaviors — input hooks in the `NSTextView` layer that translate user keystrokes into core `Document` mutations, keeping the model as the single source of truth (ADR-0004).
- **Entry state**: Phase 2 exit state — the text view displays documents; the model is the source of truth; `displayProjection` is working. The text view is not yet editable in a model-round-trip sense.
- **Deliverable**:
  - An `InputController` (or `NSTextViewDelegate`/`NSTextContentStorageDelegate` subclass) that intercepts keystrokes and translates them into `Document` mutations:
    - **Enter**: calls `splitBlock(id:atOffset:)` on the model; re-derives the `NSAttributedString` via `displayProjection`; pushes it back to the text view.
    - **Backspace at block boundary**: calls `mergeBlocks(first:second:)`.
    - **Backspace mid-block**: adjusts the run text directly on the model block; calls `adjustCutOffset` if a cut is anchored to that block.
    - **Cmd-I / `_word_` pattern**: toggles `Run.italic` on the selection's run span.
    - **`#` or `***` on an empty line**: replaces the block with a `sceneBreak` block.
    - **Smart typography**: straight-quote → curly, `--` → em dash, `...` → ellipsis, applied to the run text at input time.
    - **Set-piece toggle** (e.g. Cmd-Shift-V for verse): converts the current paragraph block to/from `setPiece(kind: .verse, ...)`.
    - Enter inside a set-piece: appends a new line to the block's `lines` array (a `[line]` code in the domain sense) rather than splitting the block.
  - ADR-worthy decision: **how NSTextView edits are translated to model ops** — whether the controller intercepts at the input level (before layout), the content-storage delegate level, or via a full replace-on-every-keystroke approach. Record the chosen pattern and its tradeoffs.
  - Behavior Statements (rule 12) produced in the conversation for each input rule before tests are written.
  - Behavioral tests for the pure-model translation logic: extract the mapping logic into a testable, AppKit-free function (e.g. `func applyInput(_ input: InputEvent, to doc: Document) -> Document`) and test it headlessly. The AppKit delegation wiring gets a manual smoke check.
  - Smoke-check verification: launch the app, type a paragraph, press Enter, type a second paragraph, press Backspace at the boundary — confirm the model collapses them correctly (check via reveal toggle or log output). Cmd-I toggles italic. `#` on an empty line becomes a scene break.
  - Integration Reality Statement: the `InputController` is OWNED; the real-path check is the manual smoke check above; any unit test that stubs `NSTextView` interaction must reference this.
- **Exit state**: The app supports real editing — type, split, merge, italic toggle, scene break, set-piece entry. Every keystroke mutates the model; the display re-derives from it. Tests for the pure translation logic are GREEN. Committed.
- **Status**: COMPLETE — Architecture: semantic interception + pure reducer (ADR-0013). Core: `InputEvent` + `applyInput(_:to:)` pure reducer (insertText/split/merge/deleteBackward/toggleItalic/makeSceneBreak/toggleSetPiece/breakSetPieceLine) and `smartTypography` helper; 26 behavioral tests (core now 85 GREEN, 0 warnings). Shell: `EditorLayout` (caret↔model map), `InputController` (NSTextView subclass intercepting insert/newline/backspace + Cmd-I), wired into editable `DocumentTextView`/`ContentView`; `DocumentModel.apply(event)`. User-verified live: typing, smart typography (curly quotes, em dash, ellipsis), Enter-split, Backspace-merge, Cmd-I italic. Two bugs found+fixed during verification: blank editable view (TextKit 2 content-storage swap needs forced `layoutViewport()` + needsDisplay) and zero-block seed (model seeds one empty paragraph). (session 6baa7e, 2026-06-05)

---

### Phase 4: Reveal pane + chapter-slicing surface (ADR-0006)
- **Tier**: Medium
- **Budget**: 250 tool calls
- **Domain focus**: The reveal toggle — a second pane that renders `revealProjection()` as code chips — and its dual role as the chapter-slicing surface where `ChapterCut` positions are placed and dragged (ADR-0005, ADR-0006).
- **Entry state**: Phase 3 exit state — the editor supports real typing. `revealProjection` is already implemented and tested in the core. The app has a single `NSTextView`; no reveal pane exists.
- **Deliverable**:
  - A `RevealPane` SwiftUI view that consumes `[RevealToken]` from `revealProjection(doc)` and renders it as a scrollable stream of text segments and code chips. Code chips are visually distinct (e.g. rounded-rect labels). The pane is toggled on/off via a keyboard shortcut (e.g. Cmd-/).
  - **Read-only reveal mode**: the pane scrolls in sync with the main editor's cursor position (approximate — exact sync deferred).
  - **Chapter-edit mode**: a mode toggle (button or keyboard shortcut within the reveal pane) that puts the pane into chapter-slicing mode. In this mode:
    - `[Chapter]` cut chips are draggable along the token stream.
    - Dropping a cut chip at a new token position calls `Document.cuts`-level mutation (update `ChapterCut.blockID` and `ChapterCut.offsetInBlock` to match the drop target token's position in the block stream). This uses the existing `BlockID`/offset model directly — no new core ops needed.
    - A "+" button or gesture places a new `ChapterCut` at the current chip position.
    - A delete gesture removes a cut.
  - ADR-worthy decision: **reveal-pane layout technology** — SwiftUI `Text`/`Label` flow, a custom `NSView`-based token renderer, or a second `NSTextView` with non-editable attributed content. Record the choice; the constraint is that chips must be individually interactive (drag targets) in chapter-edit mode.
  - Behavioral tests: the pure token rendering logic (mapping `[RevealToken]` to view model structs for chip identity, position, label) is testable without AppKit — test it headlessly. The drag/drop interaction gets a manual smoke check.
  - Smoke-check verification: launch, open a document, toggle reveal — confirm all block types show correct chips. Enter chapter-edit mode, drag a `[Chapter]` chip to a new position, toggle reveal off, save, re-open — confirm the cut's position survived the round-trip via the sidecar.
- **Exit state**: Reveal pane works in both read-only and chapter-edit modes. Chapter cuts survive save/load. Headless token-layout tests GREEN. Committed.
- **Status**: COMPLETE — Layout tech: SwiftUI flow layout (ADR-0014). Core: `Document.placeChapterCut`/`removeChapterCut`/`moveChapterCut`/`setChapterCutTitle` (ChapterEditing.swift), 9 tests (core now 94 GREEN). Shell lib: `RevealItem`+`revealItems(from:)` and `ChapterAnchor`+`chapterAnchors(of:)` (RevealRendering.swift), 3 tests (shell-lib 7 GREEN). Shell app: `FlowLayout` (SwiftUI Layout), `RevealPane` (token-stream chips + chapter-slicing editor with cut toggle/title), Cmd-/ toggle wired into split `ContentView`; `DocumentModel` cut methods. User-verified live incl. save→reopen cut round-trip. Cut placement is boundary-only via toggles (drag/mid-block deferred; model already supports mid-block). (session 6baa7e, 2026-06-05)

---

---

## Build Step 3.5: .app bundle + .galley package type registration

**Added**: 2026-06-05
**Relationship to surrounding phases**: Inserted before Build Step 2 Phase 5 (reference system). Phases 5 and 6 remain PENDING and are unaffected. Build Steps W1/W2 are COMPLETE. This track operates entirely on the executable/build side and does not touch `GalleyCore`, `GalleyShell`, or any editing/reveal surface.
**Bounded contexts touched**: N/A — build infrastructure and OS integration only.
**Key domain language**: `.app` bundle, `.galley` package type, UTI, Launch Services, Apple-event open-document, `WorkspaceModel.open(url:)`

### References consulted

- **ADR-0001** (`0001-native-not-html-electron.md`) — macOS-native commitment; all OS integration must be AppKit/Swift, no web layer.
- **ADR-0003** (`0003-textkit2-nstextview-editing-surface.md`) — AppKit/TextKit 2 surface; the open-document flow must deliver a `URL` to `WorkspaceModel.open(url:)` without bypassing the `NSTextView` layer.
- **ADR-0007** (`0007-plain-text-files-chapters-in-sidecar.md`) — on-disk layout is `prose.txt` + `sidecar.json` inside the `.galley` directory; the package-type decision complements but does not supersede this ADR. The prose file stays plain text, independently openable.
- **ADR-0011** (`0011-editor-shell-separate-swiftpm-package.md`) — the executable is the only target that owns AppKit/SwiftUI; packaging artifacts (Info.plist, UTI declaration, build script) live on the executable/build side, never in `GalleyShell`. The ADR explicitly notes that a bundled `.app` is a deferred follow-up to this decision.
- **session-20260605-2234-main.md** — most recent session summary: Build Step 3 (W1+W2) is COMPLETE and committed at dc41fa4; `swift build` clean; 29 GalleyShellTests GREEN; Phases 5 and 6 (reference system, chapter templates) remain PENDING.

---

### Design Decisions (recorded here; ADRs to be written during implementation)

**Bundle-assembly method (ADR-0017 candidate)**: SwiftPM does not natively emit a `.app` bundle with `Info.plist`. Three approaches were considered: (A) a shell script (or Makefile target) that runs `swift build -c release`, creates `Galley.app/Contents/{MacOS,Resources}`, copies the executable, and writes `Info.plist` from a template; (B) wrapping the project in an Xcode project that manages the bundle; (C) using a third-party SwiftPM plugin (e.g. `create-dmg`, `swift-bundler`). Approach A is chosen: it preserves the `swift build`/`swift test` spine (ADR-0011), adds no Xcode artifact to maintain, and keeps the bundle assembly transparent and auditable. The script lives at `scripts/bundle.sh` in the repo root. The `swift run` development path is unchanged. This choice must be recorded as an ADR because it constrains how future packaging (code signing, notarization) is added.

**Open-document routing (ADR-0018 candidate)**: The app uses `WindowGroup` + `@NSApplicationDelegateAdaptor AppDelegate` (not `DocumentGroup`). Two approaches to receive Launch Services open-document events: (A) keep `WindowGroup` and handle `application(_:openFile:)` / `application(_:openURLs:)` in `AppDelegate`, routing into the existing `WorkspaceModel.open(url:)` via the `@MainActor` context; (B) adopt `DocumentGroup`, which would require restructuring the entire app around `FileDocument` or `ReferenceFileDocument`. Approach A is chosen: it is low-risk (the routing function is one method), preserves ADR-0011's separation (no AppKit leaks into `GalleyShell`), and keeps the single-window workspace model intact. The `AppDelegate` already exists for the activation-policy fix; adding one delegate method is additive. This choice must be recorded as an ADR because it determines how all future file-open flows (drag-to-dock, Finder double-click, `open` CLI) are dispatched.

**UTI and package type (complements ADR-0007)**: The `.galley` type is registered as a macOS package — a directory that Finder presents as a single opaque file — via `CFBundleDocumentTypes` and an exported UTI with `UTTypeConformsTo: [com.apple.package, public.composite-content]` and `LSTypeIsPackage: true`. This does NOT change the on-disk layout (`prose.txt` + `sidecar.json` remain plain files inside the directory) and does NOT supersede ADR-0007. A new ADR (0019 candidate) should complement ADR-0007 explicitly, stating: (i) the package boundary is a Finder/OS perception layer only; (ii) `prose.txt` is always independently openable with any text editor; (iii) switching to a zip or binary container is explicitly ruled out.

---

### Phase B1: .app bundle assembly script + Info.plist
- **Tier**: Small
- **Budget**: 100 tool calls
- **Domain focus**: Build infrastructure — produce a real `.app` bundle from the existing SwiftPM executable so the OS can register it, launch it, and deliver Apple events to it.
- **Entry state**: Build Step 3 fully committed at dc41fa4. `swift build` clean. `swift run` launches the app. No `Galley.app` bundle, no `Info.plist`, no UTI declaration exists. macOS 14, Swift 6.2.
- **Deliverable**:
  - `scripts/bundle.sh` — a shell script that: (1) runs `swift build -c release --package-path app/`; (2) assembles `Galley.app/Contents/{MacOS,Resources,Info.plist}` from the release build output; (3) copies `Galley.app/Contents/Resources/Assets.xcassets` placeholder (or a minimal `.icns`) if needed by Launch Services. The script must be idempotent and runnable from the repo root.
  - `app/Sources/Galley/Resources/Info.plist` — embedded in the executable target's resource bundle (or written by the script from a template); contains at minimum: `CFBundleIdentifier`, `CFBundleName`, `CFBundleVersion`, `CFBundleExecutable`, `LSMinimumSystemVersion` (14.0), `NSPrincipalClass` (NSApplication), `CFBundleDocumentTypes` (for the `.galley` type — see Phase B2), and exported UTI declaration (`UTExportedTypeDeclarations`).
  - **ADR-0017** written: bundle-assembly method — shell script on the `swift build` spine vs. Xcode project vs. third-party plugin; record choice and consequences (including the path to future signing/notarization).
  - **Testability note**: `scripts/bundle.sh` is an OWNED build artifact. The REAL-PATH acceptance test for this phase is a manual check: run `bash scripts/bundle.sh`; confirm `Galley.app` appears at the expected path; confirm `open Galley.app` launches the app without crash. No headless unit test exists for the shell script itself; this is the documented Integration Reality for this phase.
- **Exit state**: `bash scripts/bundle.sh` succeeds without error. `Galley.app` is a valid macOS app bundle (passes `codesign --verify` as an ad-hoc unsigned app, or at minimum `open Galley.app` does not produce "damaged or incomplete" error). `swift build` and `swift test` paths are unchanged. ADR-0017 committed. The script is committed but the `.app` output directory is in `.gitignore`.
- **Status**: COMPLETE — `scripts/bundle.sh` assembles `dist/Galley.app/Contents/{Info.plist,MacOS/Galley,PkgInfo}` from `swift build -c release` (bin dir resolved via `--show-bin-path`, arch-agnostic) + ad-hoc `codesign --sign -`. Info.plist source of truth at `app/Packaging/Info.plist` (deviation from the planned `app/Sources/Galley/Resources/` path — kept out of `Sources/` so SwiftPM doesn't flag an unhandled resource; `swift build` stays clean). `/dist/` git-ignored. ADR-0017 written. Real-path gate passed: `plutil -lint` OK, `codesign --verify` passes ("satisfies its Designated Requirement"), `mdls` → `com.apple.application-bundle`, `open dist/Galley.app` launches a live process and quits cleanly. Document-type/UTI keys present as scaffold only — package registration + double-click routing are B2. (session 9ffa6f, 2026-06-05)

---

### Phase B2: .galley UTI registration + Launch Services open-document routing
- **Tier**: Small
- **Budget**: 100 tool calls
- **Domain focus**: OS integration — register `.galley` as a macOS package type so Finder presents it as a single file, and route Launch Services double-click events into the existing `WorkspaceModel.open(url:)`.
- **Entry state**: Phase B1 exit state — `Galley.app` assembles and launches. `Info.plist` exists with placeholders for document type. The `AppDelegate` exists in `app/Sources/Galley/` and already sets the activation policy.
- **Deliverable**:
  - `Info.plist` updated with:
    - `CFBundleDocumentTypes` entry: `CFBundleTypeName = "Galley Project"`, `CFBundleTypeRole = Editor`, `LSHandlerRank = Owner`, `LSItemContentTypes = ["com.galley.project"]`, `LSTypeIsPackage = true`.
    - `UTExportedTypeDeclarations` entry: `UTTypeIdentifier = "com.galley.project"`, `UTTypeConformsTo = ["com.apple.package", "public.composite-content"]`, `UTTypeDescription = "Galley Project"`, `UTTypeTagSpecification = { "public.filename-extension": ["galley"] }`.
  - `AppDelegate` in `app/Sources/Galley/AppDelegate.swift` gains two methods:
    - `application(_:openFile:) -> Bool` — receives a path string from Launch Services, constructs a `URL`, calls `workspace.open(url:)` on the `@MainActor`, returns `true`.
    - `application(_:openURLs:)` — receives `[URL]` from `NSWorkspace` / drag-to-dock; calls `workspace.open(url:)` for each URL.
  - The routing logic (`url -> workspace.open`) is extracted into a testable, AppKit-free function in `GalleyShell` — e.g. `WorkspaceModel.open(url:)` already exists and is headlessly tested; the `AppDelegate` methods are thin callers that do no logic themselves.
  - **ADR-0018** written: `WindowGroup` + `AppDelegate` open-document routing vs. `DocumentGroup` adoption.
  - **ADR-0019** written: `.galley` as a macOS package type, explicitly complementing ADR-0007 — package boundary is a Finder perception layer; `prose.txt` stays plain text and independently openable; zip/binary container ruled out.
  - **Testability note (Integration Reality Statement)**: The `AppDelegate` methods are OWNED entry points for Launch Services events. The REAL-PATH acceptance test is a manual smoke check: (1) run `bash scripts/bundle.sh`; (2) double-click a `.galley` directory in Finder — confirm Finder presents it as a single file with the "Galley Project" label (not as a folder); (3) double-click it — confirm Galley.app opens and `WorkspaceModel` adds the project as a buffer. Any headless test that stubs the Apple event routing must reference this manual check as its REAL-PATH TEST. No headless test substitutes for the Finder/Launch Services integration.
- **Exit state**: Finder presents `.galley` directories as single files. Double-clicking a `.galley` in Finder opens it in `Galley.app` and routes correctly into `WorkspaceModel.open(url:)`. ADR-0017, ADR-0018, and ADR-0019 committed. `swift build` and headless test suite unchanged. Committed.
- **Status**: COMPLETE — Info.plist promoted: exported UTI `com.galley.project` conforms to `com.apple.package` + `public.composite-content`; `CFBundleDocumentTypes` sets `LSTypeIsPackage` + `LSHandlerRank=Owner` + `LSItemContentTypes`. `AppDelegate` extracted to `app/Sources/Galley/AppDelegate.swift` (now `@MainActor`), gains `application(_:open:)` + `application(_:openFile:)` — thin callers into the tested `WorkspaceModel.open(url:)`. Bridged via `AppWorkspace.shared` (one workspace for the delegate's early open events + the SwiftUI scene); `Galley.swift` reads `AppWorkspace.shared`. ADR-0018 (WindowGroup+AppDelegate routing, DocumentGroup rejected) and ADR-0019 (.galley package type complementing ADR-0007, zip rejected) written. `swift build` clean; 29 GalleyShellTests still GREEN. Real-path gate passed: after `bundle.sh` + `lsregister`, a test `.galley` types as `com.galley.project` with `com.apple.package` in its type tree (Finder single-file presentation), and `open <pkg>.galley` (the Launch Services dispatch Finder double-click uses) launches Galley.app. (session 9ffa6f, 2026-06-05)

---

### Phase 5: Reference system — peek overlay + @-bible fuzzy index (ADR-0008, §9)
- **Tier**: Medium
- **Budget**: 250 tool calls
- **Domain focus**: The mechanical reference lookup system — a fuzzy index over the writer's own bible files, surfaced via a peek overlay and `@`-completion inline. No AI, no generation (ADR-0008).
- **Entry state**: Phase 4 exit state — the full editing + reveal surface is working. No reference system exists.
- **Deliverable**:
  - **Bible index**: a `BibleIndex` struct (in the app layer, not `GalleyCore` — it reads files from disk and owns the fuzzy-search logic) that loads bible entries (YAML front-matter + notes, one file per entity) from a configurable directory alongside the prose file. Builds an in-memory fuzzy index (simple prefix/substring match sufficient for v1; no external dependency required unless the planner decides otherwise).
  - **`@`-completion**: intercept `@` (or `[[`) in the `InputController`; present a `NSMenu`-style or custom completion popover listing matching bible entries. `Enter` inserts the canonical entry name into the run text. `Tab` opens the peek overlay for that entry.
  - **Peek overlay**: an `NSPopover` (or overlay child window) that displays a bible entry's full text in read-only form. Dismisses on `Esc` or focus loss; cursor position is unchanged. A "flick-to-last" keybinding re-summons the last peeked entry.
  - **Scene-remembers-its-references**: each scene (contiguous block range before the next `ChapterCut`) quietly records which bible entries were peeked while editing it. Stored in `Document.meta` or a lightweight parallel structure (design decision: record in `Metadata` in the core model or as a separate app-layer annotation). Assumption: store in app-layer annotation to avoid making `GalleyCore` aware of bible files; state this explicitly.
  - ADR-worthy decision: **bible index location** — does `BibleIndex` live in `GalleyCore` (pure value, portable) or in the app layer (has file I/O)? Recommendation: app layer, because file I/O belongs outside the pure domain core. Record the decision.
  - Behavioral tests: `BibleIndex` fuzzy matching logic is AppKit-free and fully testable headlessly. The popover/completion UI gets a manual smoke check.
  - Smoke-check verification: create a bible file, launch the app, type `@`, confirm matching entries appear. `Tab` on a result opens the peek overlay with the entry content. `Esc` returns cursor to position. Flick-to-last re-summons it.
- **Exit state**: `@`-completion and peek overlay work with a real bible directory. `BibleIndex` tests GREEN. Committed.
- **Status**: COMPLETE (design pivoted from the original deliverable; see ADR-0021) — Shipped as two surfaces over per-file package sources. **Headless (GalleyShell):** `FuzzyMatch` (shared humanise + subsequence scorer), `BibleIndex` (loads `bible/*.md`, reuses `GalleyCore.BibleEntry`), `SnippetIndex` (loads `snippets/*.txt`, `Snippet` value); wired into `WorkspaceDocument.reloadIndexes()` (load on open/save). 23 headless tests (suite now 52 GREEN, 0 warnings), incl. real-path bible+snippet directory loads. ADR-0020 (indexes in app layer), ADR-0021 (UX split). **Executable (Galley):** `@`-completion inserts **snippets** (`SnippetCompletionPopover` + `InputController+Snippets`, multi-line bodies → paragraphs, token replace via the pure reducer); the **bible** is a read-only searchable **side panel** (`BiblePane`, Cmd-Shift-B). Bottom-bar buttons reveal shortcuts on ⌘-hold. **Removed** (originally built, then pivoted): inline `@`-bible completion, peek overlay, flick-to-last (Cmd-Y), `SceneReferences`. Two editor bugs fixed during live verification: popovers anchored to bottom-of-screen (`firstRect` returns `.zero` for a caret under TextKit 2 → compute from layout segments) and typing below the last block was dead (clamp caret + start a fresh paragraph). User-verified live: `@`-snippet insert (incl. multi-paragraph), bible panel search/read, ⌘-hold shortcut hints. (session 9ffa6f, 2026-06-06)

---

### Phase 6: Chapter-opener templates (§9, `TemplateRef` on `ChapterCut`)
- **Tier**: Small
- **Budget**: 100 tool calls
- **Domain focus**: The `TemplateRef` field on `ChapterCut` — a saved block arrangement (e.g. epigraph + dateline) that is instantiated at the cut operation, not during drafting (§9). This is the last component of build step 2.
- **Entry state**: Phase 5 exit state — the full reference system is working. `ChapterCut.opener: TemplateRef?` already exists in the domain model (declared in build step 1) but is unused. No template UI exists.
- **Deliverable**:
  - A `TemplateStore`: a simple persistent store (JSON file alongside the prose, or embedded in the sidecar — design decision to record) of named block templates. Each template is a sequence of `BlockContent` values. A template is assigned to a `ChapterCut.opener` by name; the `TemplateRef` type in the core model already holds the name.
  - **Template assignment UI**: in chapter-edit mode (reveal pane), a contextual control on a `[Chapter]` chip lets the writer assign or clear a template for that cut.
  - **Template instantiation at render time**: `displayProjection` (or a separate `chapterOpenProjection`) inserts the template's blocks between the chapter-break splice and the first prose block of the new chapter. This is a pure transform over the model — no new storage. Assumption: template instantiation is computed at render time by `displayProjection`; it is not injected into `Document.blocks`. State this explicitly.
  - **Template editor**: a minimal UI (separate sheet or popover) to create/edit/delete named templates — essentially a small block editor using the same typing rules.
  - ADR-worthy decision: **template storage location** — in the sidecar (extending the existing JSON schema) vs. a separate `.galley-templates` file. Record the choice.
  - Behavioral tests: template instantiation logic (given a `Document` with cuts and `TemplateRef`s, assert the display token sequence contains the template blocks in the right positions) is testable headlessly. The assignment/editor UI gets a smoke check.
  - Smoke-check verification: create a template with an epigraph block, assign it to a chapter cut in the reveal pane, toggle reveal off — confirm the template blocks appear at the chapter boundary in the display view.
- **Exit state**: Templates are assignable to cuts, persist in the file pair, and render at chapter boundaries. Build step 2 is complete. All headless tests GREEN. Committed.
- **Status**: PENDING

---

## Build Step 3: New command + multi-project workspace

**Added**: 2026-06-05
**Relationship to Build Step 2**: Phases 5 and 6 above (reference system, chapter templates) remain PENDING and are unaffected. This track is additive — it replaces the single-model app shell with a workspace container. It adds an AppKit-free `WorkspaceModel` store to `GalleyShell` (headless, testable) while keeping AppKit panel glue in the `Galley` executable; it does not touch `GalleyCore` or the editing/reveal surfaces established in Phases 1–4. Phases 5/6 are unaffected.
**Bounded contexts touched**: N/A — app-layer state and menu infrastructure only.
**Key domain language**: WorkspaceModel (buffer container), WorkspaceDocument (headless buffer state + load/persist), buffer slot, current buffer, unsaved buffer

### References consulted

- **ADR-0002** (`0002-swift-core-mac-first-rust-deferred.md`) — dependency direction constraint: `GalleyCore` must remain UI-free; the dependency edge only points app → core. `WorkspaceModel` and the Cmd-N/O/W command infrastructure are app-layer code and must not introduce any `GalleyCore` imports to the shell that would reverse this edge.
- **ADR-0004** (`0004-own-model-is-source-of-truth.md`) — model-as-truth: each open buffer's state lives in its `DocumentModel` (which wraps the core `Document`); the workspace container (`WorkspaceModel`) owns those models and must not duplicate or shadow their state. Any display derived from the workspace (window title, slot labels) is derived, not stored separately.
- **ADR-0007** (`0007-plain-text-files-chapters-in-sidecar.md`) — persistence format: saving a buffer means writing both the prose file and the sidecar JSON; auto-save-on-switch must call through the existing `DocumentBundle`/`DocumentModel` save path — not a raw write — so the two-artifact invariant is maintained.
- **ADR-0011** (`0011-editor-shell-separate-swiftpm-package.md`) — app-target structure: `GalleyShell` (pure Foundation + GalleyCore) is unit-testable headlessly; the `Galley` executable is the only target that needs a window server. Under fix (a) this means `WorkspaceModel` (AppKit-free container/state + load-persist) lives in `app/Sources/GalleyShell/` and is tested in the existing `GalleyShellTests` target; only the thin panel-runner and SwiftUI command glue (which import AppKit/SwiftUI) live in `app/Sources/Galley/`.
- **session-20260605-2000-main.md** — most recent session summary: confirms Phases 5 and 6 (reference system, chapter templates) remain PENDING and are out of scope for the Build Step 3 track. Build Step 3 adds an AppKit-free workspace store (`WorkspaceModel`/`WorkspaceDocument`) to `GalleyShell` additively, but must not touch `GalleyCore` or the editing/reveal surfaces established in Phases 1–4.

---

### Design Decisions (recorded here; ADRs to be written during implementation)

**Unsaved-New buffer policy (ADR-0015 candidate)**: A blank buffer created by Cmd-N has no `fileURL`. Switching away from it does NOT prompt and does NOT write a temp file. The buffer lives in memory only. If the buffer has content (at least one non-empty run) at close time, the user is asked to save or discard. A truly empty blank (zero characters in all runs) is discarded silently. Rationale: this matches every macOS text editor's behavior and avoids surprising temp-file pollution.

**Last-buffer-close behavior (ADR-0015 candidate)**: Closing the last open buffer replaces it with a fresh blank rather than quitting. Quitting (Cmd-Q) is a separate explicit action. Rationale: keeps the workspace alive and consistent with browser-tab conventions; avoids accidental quit from Cmd-W on the only document.

**DocumentModel split (fix (a))**: `DocumentModel` mixes two concerns: (i) AppKit panel presentation (`NSOpenPanel` in `open()`, `NSSavePanel` in `saveAs()`) and (ii) buffer state + bundle load/persist (`load(from:)`, `persist(to:)`, `document`, `fileURL`, `hasContent`). Under fix (a) these are separated: a new `WorkspaceDocument` type in `GalleyShell` owns concern (ii) — it takes a `URL?` and has no AppKit import. The AppKit-side `DocumentModel` in the `Galley` executable becomes a thin panel-runner that runs `NSOpenPanel`/`NSSavePanel` and hands resulting URLs into `WorkspaceDocument`/`WorkspaceModel`. `WorkspaceDocument` is the headlessly-testable unit; `DocumentModel` (panel layer) is not tested headlessly.

**Workspace container abstraction (ADR-0016 candidate)**: `WorkspaceModel` is an `@Observable` class in `GalleyShell` that owns `[WorkspaceDocument]` + `currentIndex: Int`. It is AppKit-free and headlessly testable. `Galley.swift` owns exactly one `WorkspaceModel`; `ContentView` receives it and derives `currentDocument`. The executable's `DocumentModel` (panel layer) wraps or bridges into `WorkspaceModel` for the panel-presentation path. This is a store — Boundary Statement required before editing; OWNER is the `GalleyShell` library (app-layer state), not the `Galley` executable.

**Auto-save on switch**: When `switchTo(index:)` is called, the workspace calls `currentDocument.persist(to: fileURL)` if and only if `currentDocument.fileURL != nil` (i.e., the buffer has been saved at least once). Unsaved buffers are left untouched in memory.

---

### Phase W1: WorkspaceModel — buffer container and Cmd-N / Cmd-O rewire
- **Tier**: Medium
- **Budget**: 250 tool calls
- **Domain focus**: Introduce the `WorkspaceModel` store; replace the single `@State var model` in `Galley.swift` with a workspace; rewire Cmd-N (new blank buffer) and Cmd-O (append-and-switch, not replace); wire auto-save-on-switch.
- **Entry state**: Phase 4 exit state committed. `Galley.swift` owns one `@State var model = DocumentModel()`. `DocumentModel.open()` replaces the single model in-place. `CommandGroup(replacing: .newItem)` has no New action (only Open).
- **Files touched**:
  - NEW `app/Sources/GalleyShell/WorkspaceDocument.swift` — headless buffer state + load/persist (no AppKit import); owns `document: Document`, `fileURL: URL?`, `hasContent: Bool`, `load(from:)`, `persist(to:)`
  - NEW `app/Sources/GalleyShell/WorkspaceModel.swift` — the AppKit-free store (`@Observable`, owns `[WorkspaceDocument]` + `currentIndex: Int`, auto-save-on-switch logic)
  - `app/Sources/Galley/DocumentModel.swift` — refactor to a thin panel-runner: keep `NSOpenPanel`/`NSSavePanel` calls here; delegate buffer state and I/O to `WorkspaceDocument`; remove logic that now lives in `WorkspaceDocument`
  - `app/Sources/Galley/Galley.swift` — replace `@State var model` with `@State var workspace: WorkspaceModel`; rewire Cmd-N/Cmd-O `.commands` to call `workspace.new()` / `workspace.open(url:)` (with panel run staying in the executable)
  - `app/Sources/Galley/ContentView.swift` — accept `WorkspaceModel`, derive `currentDocument: WorkspaceDocument`
  - `app/Tests/GalleyShellTests/WorkspaceModelTests.swift` — NEW (extends existing `GalleyShellTests` target; no new test target needed; `app/Package.swift` requires no new target declaration)
- **Behavior Statements to write** (rule 12, before tests; all behaviors named here are on the GalleyShell-side types and are headlessly testable — they do not import AppKit):
  - `WorkspaceModel.new()` — DOES: appends a blank `WorkspaceDocument` (no URL, empty `Document`) and sets `currentIndex` to its position. REJECTS WHEN: never rejects.
  - `WorkspaceModel.open(url:)` — DOES: creates a `WorkspaceDocument`, calls `load(from: url)` on it, appends it, and switches to it. REJECTS WHEN: `DocumentBundle.read` throws; in that case no buffer is appended and the workspace is unchanged.
  - `WorkspaceModel.switchTo(index:)` — DOES: auto-saves the current `WorkspaceDocument` (calls `persist(to: fileURL)`) if `currentDocument.fileURL != nil`, then sets `currentIndex`. REJECTS WHEN: index out of range (no-op, does not crash).
  - `WorkspaceDocument.hasContent` — DOES: returns `true` if any run in any block has non-empty text; returns `false` for a pristine blank document. (No AppKit; pure value predicate over the `Document`.)
- **ADR-worthy**: `WorkspaceModel` container abstraction including the `WorkspaceDocument` split (ADR-0016 — note that the container lives in `GalleyShell`, not the executable); unsaved-New buffer policy (ADR-0015).
- **Boundary Statement required**: Yes — `WorkspaceModel` and `WorkspaceDocument` live under the store/state pattern in `GalleyShell`. Produce the statement before editing. OWNER: `GalleyShell` library (app-layer state, not the `Galley` executable).
- **Exit state**: `swift build` clean. Cmd-N appends a blank buffer and switches to it. Cmd-O appends the chosen project without replacing existing buffers. Switching between buffers auto-saves the outgoing buffer (if it has a URL). `WorkspaceModelTests` GREEN. Committed.
- **Status**: COMPLETE — `WorkspaceDocument` + `WorkspaceModel` added to `GalleyShell` (AppKit-free, `@Observable @MainActor`); 13 headless behavioral tests in `GalleyShellTests` (suite now 20 GREEN, build clean 0 warnings). `DocumentModel` removed; replaced by `FilePanels` (the `@MainActor` NSOpenPanel/NSSavePanel runner) + a `WorkspaceModel` panel extension in the executable. Cmd-N/Cmd-O rewired in `Galley.swift`; auto-save-on-switch via `autosaveCurrentIfPersisted()` (fires only when `fileURL != nil`). **Deviation from the file estimate:** moving the per-buffer object into GalleyShell required rebinding every view that used `DocumentModel` (`ContentView`, `DocumentTextView`, `InputController`, `RevealPane`, `MetadataPanel`) to `WorkspaceDocument`, and adding the SwiftUI `metaBinding` bridge over the headless `setMetadata`. App launches and runs (smoke-checked). ADR-0015 (unsaved/last-buffer policy) and ADR-0016 (workspace store in GalleyShell) written. (session b8b0bd, 2026-06-05)

---

### Phase W2: Cmd-W close + Window menu + Cmd-1..9 slot switching
- **Tier**: Small
- **Budget**: 100 tool calls
- **Domain focus**: Buffer lifecycle (close), navigation (direct-slot shortcuts), and the dynamic Window menu listing open projects.
- **Entry state**: Phase W1 exit state — `WorkspaceModel` exists; Cmd-N and Cmd-O work; switching auto-saves.
- **Files touched**:
  - `app/Sources/GalleyShell/WorkspaceModel.swift` — add `close(index:)` with empty-blank-discard and last-buffer replacement logic
  - `app/Sources/Galley/Galley.swift` — add `CommandGroup` for Cmd-W close; add a dynamic `CommandMenu("Window")` listing buffers with checkmarks; add Cmd-1..9 key bindings via `forEach`
  - `app/Sources/Galley/ContentView.swift` — toolbar/status bar shows current slot number and title
  - `app/Tests/GalleyShellTests/WorkspaceModelTests.swift` — extend (same file as W1; no new target) with close/last-buffer tests
- **Behavior Statements to write**:
  - `WorkspaceModel.close(index:)` (GalleyShell-side, headlessly testable) — DOES: removes the `WorkspaceDocument` at `index`; if it was the last buffer, replaces with a fresh blank `WorkspaceDocument`; switches `currentIndex` to the nearest neighbor (prefer `index - 1`, else `index`, clamped). REJECTS WHEN: if the closing `WorkspaceDocument` has content (`hasContent == true`) and `fileURL == nil`, emits a `.unsavedContent(WorkspaceDocument)` result that the executable-side caller uses to present a Save/Discard sheet before proceeding. The Save/Discard sheet itself lives in the `Galley` executable (AppKit/SwiftUI); `WorkspaceModel.close` never presents UI.
- **ADR-worthy**: last-buffer-close policy recorded alongside ADR-0015.
- **Exit state**: Cmd-W closes correctly; last-buffer is replaced by a blank; unsaved-content buffers prompt before close. Window menu lists buffers with checkmarks; Cmd-1..9 switches directly. All new tests GREEN. Committed.
- **Status**: COMPLETE (live-verified) — `WorkspaceModel.close(index:)`/`discardAndClose(index:)`/`removeBuffer(at:)` + `CloseOutcome` + `pendingCloseIndex` added to GalleyShell; persist-on-close for file-backed buffers, silent discard of empty blanks, `.needsConfirmation` for unsaved-with-content, last-buffer→fresh-blank, neighbour-index math. 9 new headless tests (suite now 29 GREEN, build clean 0 warnings). Executable: `Galley.swift` adds **Cmd-W Close**, a **"Projects" `CommandMenu`** (checkmarked `Toggle` per buffer, click-to-switch) and **Cmd-1..9** slot shortcuts; `ContentView` adds the Save/Discard/Cancel `confirmationDialog` (driven by `pendingCloseIndex`) and a "Project N of M" slot indicator. **Naming note:** the buffer list is a custom menu titled **"Projects"**, not literally "Window", to avoid colliding with the macOS-managed Window menu. **Regression fixed during verification:** new/switched buffers were not typeable — the `.id(currentIndex)` rebuild tore down the `NSTextView` per switch and lost first-responder; replaced with one persistent text view whose bound buffer is swapped in `updateNSView` (preserving first-responder) plus an explicit `makeFirstResponder` on launch (`DocumentTextView.swift`). User-verified live: New/typing/slot-switch (Cmd-1..9), Projects-menu checkmarks, Cmd-W close incl. last-buffer-replacement (window stays alive), unsaved-close dialog, auto-save-on-switch. (session b8b0bd, 2026-06-05)
