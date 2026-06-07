//
//  RevealController.swift
//  Galley
//
//  Purpose: The Reveal Codes editing surface (LT5, ADR-0030/ADR-0032) — an
//  `NSTextView` subclass that renders the model-annotated reveal stream
//  (`RevealLayout`) with codes as atomic bracketed chips, and shares one caret with
//  the prose editor through `WorkspaceDocument.currentCaret` (ADR-0033). In phase
//  LT5-1 it is read-only *as to the document model*: it positions and shares the
//  caret, steps the caret over a code as one unit, and triggers shared undo/redo —
//  but dispatches no `InputEvent` (no model mutation). Bidirectional code editing is
//  LT5-2 (ADR-0034). The model is the single source of truth (ADR-0004); the text
//  storage is never edited directly.
//  Public interface: `RevealController` (its `buffer`, `render`, `syncIfNeeded`,
//  `reconcileSharedCaret`).
//  Owner context: Galley — the macOS shell's editing layer (ADR-0003).
//

import AppKit
import GalleyCore
import GalleyShell

/// A read-from-model reveal view that shares the one caret with the prose editor.
final class RevealController: NSTextView {

    /// The document buffer being revealed. Weak: the workspace store owns it.
    weak var buffer: WorkspaceDocument?

    /// The layout from the most recent render — the reveal caret ↔ model map.
    private var layout = RevealLayout(attributedString: NSAttributedString(), segments: [])

    /// The document state the current render reflects, so external changes re-render
    /// without re-rendering on our own (caret-only) activity.
    private var lastRenderedDocument: Document?

    /// Guards the selection observer against re-entry while we reconcile or re-render.
    private var isSyncing = false

    /// The caret location at the last settled selection, so the step-over knows which
    /// way the caret moved and snaps off a code chip accordingly.
    private var lastCaretLocation = 0

    // MARK: Rendering

    /// Rebuilds the reveal layout from the model and pushes it into the text storage,
    /// then reconciles the caret to the shared `currentCaret`. Does not mutate the model.
    func render() {
        guard let buffer else { return }
        layout = RevealLayout.build(from: buffer.document)
        lastRenderedDocument = buffer.document

        let string = layout.attributedString
        if let contentStorage = textContentStorage, let backing = contentStorage.textStorage {
            contentStorage.performEditingTransaction {
                backing.setAttributedString(string)
            }
        } else {
            textStorage?.setAttributedString(string)
        }
        // A wholesale content-storage swap does not always repaint the TextKit 2 view;
        // force the viewport to re-lay-out and redraw (same fix as the prose editor).
        textLayoutManager?.textViewportLayoutController.layoutViewport()
        needsLayout = true
        needsDisplay = true

        reconcileSharedCaret()
    }

    /// Re-renders only if the model changed outside our own activity (an edit in the
    /// prose pane, an undo, a file open). A pure caret move does not change the model,
    /// so it falls through to a caret-only reconcile by the host.
    func syncIfNeeded() {
        guard let buffer else { return }
        if lastRenderedDocument != buffer.document { render() }
    }

    /// Reconciles this view's selection to the shared `currentCaret` (ADR-0033) — used
    /// when the *other* surface moved the caret. A no-op when the selection already
    /// matches, so the surface that originated the change does not loop.
    func reconcileSharedCaret() {
        guard let caret = buffer?.currentCaret, let range = layout.characterRange(for: caret) else { return }
        guard range != selectedRange() else { return }
        isSyncing = true
        defer { isSyncing = false }
        setSelectedRange(range)
    }

    // MARK: Caret sharing + step-over

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        guard !isSyncing, !stillSelecting else { return }

        // The caret never rests inside a code chip — snap it off to the edge it was
        // moving toward, exactly as the prose editor glides past a heading (ADR-0030).
        let location = selectedRange().location
        if selectedRange().length == 0, let code = layout.codeSegment(forCharacterAt: location) {
            let forward = location >= lastCaretLocation
            let edge = forward ? code.utf16Range.location + code.utf16Range.length : code.utf16Range.location
            isSyncing = true
            setSelectedRange(NSRange(location: edge, length: 0))
            isSyncing = false
        }
        lastCaretLocation = selectedRange().location

        // Publish this surface's caret to the shared one so the prose pane reflects it.
        buffer?.currentCaret = layout.modelPosition(forCharacterAt: selectedRange().location).map {
            Caret(blockID: $0.blockID, offset: $0.offset)
        }
    }

    // MARK: Key handling

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "z":
                // Shared timeline: undo/redo work identically from either pane (ADR-0033).
                if event.modifierFlags.contains(.shift) { buffer?.performRedo() } else { buffer?.performUndo() }
                render()
                return
            case "y":
                buffer?.performRedo(); render(); return
            default: break
            }
        }
        // Arrow/navigation keys fall through; LT5-1 dispatches no editing events, so
        // typing and deletion are intercepted as no-ops below.
        super.keyDown(with: event)
    }

    // MARK: Read-only-as-to-model intercepts (LT5-1)

    // LT5-1 is read-only with respect to the document: the reveal surface positions and
    // shares the caret but never mutates the model. These primitive editing actions are
    // suppressed here; LT5-2 (ADR-0034) replaces them with code→event dispatch.
    override func insertText(_ string: Any, replacementRange: NSRange) { /* no-op until LT5-2 */ }
    override func insertNewline(_ sender: Any?) { /* no-op until LT5-2 */ }
    override func deleteBackward(_ sender: Any?) { /* no-op until LT5-2 */ }
    override func deleteForward(_ sender: Any?) { /* no-op until LT5-2 */ }
}
