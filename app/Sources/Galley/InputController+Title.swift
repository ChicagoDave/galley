//
//  InputController+Title.swift
//  Galley
//
//  Purpose: Inline chapter-title editing in the main editor (LT3) and the
//  model-snapshot undo/redo hooks (Cmd-Z / Cmd-Shift-Z). Every heading is a
//  navigable, editable segment; edit-mode follows the caret (the selection
//  observer): whichever heading the caret enters — by click or arrow key — renders
//  the raw title (the macro visible) and routes keystrokes to the cut's title via
//  `WorkspaceDocument.setCutTitle`; every other heading shows the resolved title
//  (numbering rendered) — the spreadsheet rule (ADR-0026). Leaving a heading
//  restores its resolved form. Backspace never silently merges across a break: at a
//  chapter's prose start it moves up into the title, and removing the break is a
//  deliberate backspace at the title's start.
//  Public interface: the `InputController` key/mouse/selection hooks call into these.
//  Owner context: Galley — the macOS shell's editing layer.
//

import AppKit
import GalleyCore

extension InputController {

    // MARK: Title-position lookup

    /// The `(cutBlockID, offset)` of the caret when it sits in a heading, else `nil`.
    func caretTitlePosition() -> (cutBlockID: BlockID, offset: Int)? {
        currentLayout.titlePosition(forCharacterAt: selectedRange().location)
    }

    /// The raw (macro-bearing) title stored on the boundary cut at `blockID`.
    private func rawTitle(of blockID: BlockID) -> String {
        buffer?.document.cuts.first { $0.blockID == blockID && $0.offsetInBlock == nil }?.title ?? ""
    }

    /// Runs `body` with the selection observer suppressed, restoring the prior state
    /// so nested calls compose correctly.
    private func withoutSelectionSync(_ body: () -> Void) {
        let wasSyncing = isSyncingSelection
        isSyncingSelection = true
        defer { isSyncingSelection = wasSyncing }
        body()
    }

    // MARK: Selection-driven exit + arrow-glide past breaks

    /// After a settled selection change: leave the heading being edited if the caret
    /// has exited it, then skip the caret past any (non-edited) break it landed on so
    /// arrows glide over breaks (LT3). Editing a break is only ever entered by click.
    func syncTitleEditingToCaret() {
        // 1. Exit the edited heading once the caret moves out of it (e.g. arrow down
        //    into the prose, or up into the previous block).
        if let editing = editingTitleCut,
           currentLayout.headingCut(forCharacterAt: selectedRange().location) != editing {
            let landing = caretModelPosition()
            ensureNonEmptyTitle(editing)
            editingTitleCut = nil
            withoutSelectionSync {
                applyRender()
                if let landing, let position = currentLayout.characterPosition(forBlock: landing.blockID, offset: landing.offset) {
                    setSelectedRange(NSRange(location: position, length: 0))
                }
            }
        }

        // 2. If the caret landed inside a (non-edited) heading, glide it past — to the
        //    chapter's prose when moving down, to the previous section's end when up.
        let location = selectedRange().location
        if editingTitleCut == nil, let heading = currentLayout.headingCut(forCharacterAt: location) {
            skipPastHeading(cut: heading, forward: location >= lastCaretLocation)
        }
        lastCaretLocation = selectedRange().location
    }

    /// Moves the caret off a break heading: to the start of the chapter's prose when
    /// gliding forward/down, or to the end of the previous section when backward/up.
    private func skipPastHeading(cut: BlockID, forward: Bool) {
        guard let buffer else { return }
        let doc = buffer.document
        var target: (blockID: BlockID, offset: Int) = (cut, 0)
        if !forward, let index = doc.blocks.firstIndex(where: { $0.id == cut }), index > 0 {
            let previous = doc.blocks[index - 1]
            if case .paragraph(let runs) = previous.content {
                target = (previous.id, runs.reduce(0) { $0 + $1.text.count })
            } else {
                target = (previous.id, 0)
            }
        }
        if let position = currentLayout.characterPosition(forBlock: target.blockID, offset: target.offset) {
            withoutSelectionSync { setSelectedRange(NSRange(location: position, length: 0)) }
        }
    }

    // MARK: Click hit-testing

    /// The cut whose heading covers `point` (view coordinates), for click-to-edit.
    func headingCut(atPoint point: NSPoint) -> BlockID? {
        for segment in currentLayout.segments where segment.titleCutBlockID != nil {
            if let box = rect(forUTF16Range: segment.utf16Range), box.contains(point) {
                return segment.titleCutBlockID
            }
        }
        return nil
    }

    /// The bounding rectangle of a UTF-16 range in this view's coordinates, via the
    /// TextKit 2 layout (the same segment geometry the caret anchor uses).
    private func rect(forUTF16Range range: NSRange) -> NSRect? {
        guard let layoutManager = textLayoutManager,
              let contentStorage = textContentStorage,
              let start = contentStorage.location(contentStorage.documentRange.location, offsetBy: range.location),
              let end = contentStorage.location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end) else { return nil }

        var union: NSRect?
        layoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
            union = union.map { $0.union(frame) } ?? frame
            return true
        }
        guard let box = union else { return nil }
        let origin = textContainerOrigin
        return box.offsetBy(dx: origin.x, dy: origin.y)
    }

    // MARK: Editing a title

    /// Inserts text into the heading's raw title at the caret, re-renders raw, and
    /// restores the caret after the inserted text.
    func insertIntoTitle(_ text: String, at position: (cutBlockID: BlockID, offset: Int)) {
        guard let buffer else { return }
        editingTitleCut = position.cutBlockID
        withoutSelectionSync {
            var characters = Array(rawTitle(of: position.cutBlockID))
            let offset = min(max(position.offset, 0), characters.count)
            characters.insert(contentsOf: Array(text), at: offset)
            buffer.setCutTitle(atBlock: position.cutBlockID, to: String(characters))
            applyRender()
            if let caret = currentLayout.characterPosition(forTitleCut: position.cutBlockID, offset: offset + text.count) {
                setSelectedRange(NSRange(location: caret, length: 0))
            }
        }
    }

    /// Backspace in a heading: deletes the character before the caret. At the title's
    /// start it is a no-op — removing a break is done from the prose side via the Y/N
    /// confirm prompt (LT3), so a title backspace never destroys structure.
    func deleteBackwardInTitle(at position: (cutBlockID: BlockID, offset: Int)) {
        guard let buffer, position.offset > 0 else { return }
        editingTitleCut = position.cutBlockID

        withoutSelectionSync {
            var characters = Array(rawTitle(of: position.cutBlockID))
            let offset = min(position.offset, characters.count)
            guard offset > 0 else { return }
            characters.remove(at: offset - 1)
            buffer.setCutTitle(atBlock: position.cutBlockID, to: String(characters))
            applyRender()
            if let caret = currentLayout.characterPosition(forTitleCut: position.cutBlockID, offset: offset - 1) {
                setSelectedRange(NSRange(location: caret, length: 0))
            }
        }
    }

    // MARK: Entering / leaving / removing

    /// Enters inline editing for the heading of the cut at `cut`: renders it raw,
    /// caret at the end of the title, takes focus.
    func beginTitleEditing(cut: BlockID) {
        if let current = editingTitleCut, current != cut { ensureNonEmptyTitle(current) }
        endCompletion()
        endPalette()
        editingTitleCut = cut
        withoutSelectionSync {
            applyRender()
            if let caret = currentLayout.endOfTitle(cutBlockID: cut) {
                setSelectedRange(NSRange(location: caret, length: 0))
            }
            window?.makeFirstResponder(self)
        }
    }

    /// Leaves title editing: an emptied title reverts to its role default (never
    /// blank), the heading re-renders resolved, and — when `moveToBody` — the caret
    /// drops into the chapter's first prose block.
    func exitTitleEditing(moveToBody: Bool) {
        guard let cut = editingTitleCut else { return }
        ensureNonEmptyTitle(cut)
        editingTitleCut = nil
        withoutSelectionSync {
            if moveToBody {
                renderFromModel(caret: (cut, 0))   // the cut anchors the chapter's prose block
            } else {
                applyRender()
                let length = (string as NSString).length
                setSelectedRange(NSRange(location: min(selectedRange().location, length), length: 0))
            }
        }
    }

    // MARK: Break-deletion confirmation (Y/N)

    /// Resolves a pending break deletion from its confirming key: `y` removes the
    /// break, anything else (including `n` and Esc) cancels (LT3).
    func handleBreakDeletionKey(_ event: NSEvent) {
        guard let pending = pendingBreakDeletion else { return }
        if event.charactersIgnoringModifiers?.lowercased() == "y" {
            confirmBreakDeletion(pending)
        } else {
            cancelBreakDeletion(pending)
        }
    }

    /// Removes the break (its boundary cut), leaving the prose block, and lands the
    /// caret at the end of the previous section.
    func confirmBreakDeletion(_ cut: BlockID) {
        guard let buffer else { return }
        pendingBreakDeletion = nil
        let doc = buffer.document
        var caret: (BlockID, Int) = (cut, 0)
        if let index = doc.blocks.firstIndex(where: { $0.id == cut }), index > 0 {
            let previous = doc.blocks[index - 1]
            if case .paragraph(let runs) = previous.content {
                caret = (previous.id, runs.reduce(0) { $0 + $1.text.count })   // end of previous section
            } else {
                caret = (previous.id, 0)
            }
        }
        withoutSelectionSync {
            buffer.removeCut(atBlock: cut)
            renderFromModel(caret: caret)
        }
    }

    /// Dismisses the prompt without deleting; the caret returns in front of the break
    /// (the chapter's prose start).
    func cancelBreakDeletion(_ cut: BlockID) {
        pendingBreakDeletion = nil
        withoutSelectionSync {
            renderFromModel(caret: (cut, 0))
        }
    }

    /// Restores the role's default title if the cut's title was cleared to empty.
    private func ensureNonEmptyTitle(_ cut: BlockID) {
        guard let buffer, rawTitle(of: cut).isEmpty else { return }
        let role = buffer.document.cuts.first { $0.blockID == cut && $0.offsetInBlock == nil }?.role ?? .chapter
        buffer.setCutTitle(atBlock: cut, to: role.defaultTitle)
    }

    // MARK: Undo / redo (Cmd-Z, Cmd-Shift-Z)

    /// Restores the previous document state and lands the caret *at the change site*
    /// — the first block (and character) that differs — so undo focuses where it acted.
    func performUndo() {
        guard let buffer else { return }
        let before = buffer.document
        editingTitleCut = nil
        pendingBreakDeletion = nil
        buffer.undo()
        restoreCaret(at: changeSite(from: before, to: buffer.document, atEnd: false))
    }

    /// Re-applies the most recently undone state, landing the caret *after* the
    /// re-applied change (the end of the changed region), as redo conventionally does.
    func performRedo() {
        guard let buffer else { return }
        let before = buffer.document
        editingTitleCut = nil
        pendingBreakDeletion = nil
        buffer.redo()
        restoreCaret(at: changeSite(from: before, to: buffer.document, atEnd: true))
    }

    /// Re-renders after an undo/redo and places the caret at `site` (clamped),
    /// falling back to the first editable position so the caret never lands in the void.
    private func restoreCaret(at site: (blockID: BlockID, offset: Int)?) {
        withoutSelectionSync {
            applyRender()
            if let site, let position = currentLayout.characterPosition(forBlock: site.blockID, offset: site.offset) {
                setSelectedRange(NSRange(location: position, length: 0))
            } else if let first = currentLayout.firstEditablePosition(),
                      let position = currentLayout.characterPosition(forBlock: first.blockID, offset: first.offset) {
                setSelectedRange(NSRange(location: position, length: 0))
            } else {
                let length = (string as NSString).length
                setSelectedRange(NSRange(location: min(selectedRange().location, length), length: 0))
            }
        }
    }

    /// The location an undo/redo acted on, in the new document. `atEnd` chooses where
    /// in a changed block the caret lands: the start of the change (undo) or just past
    /// it (redo). Falls back to an added/removed block, then the first changed cut.
    private func changeSite(from old: Document, to new: Document, atEnd: Bool) -> (blockID: BlockID, offset: Int)? {
        let shared = min(old.blocks.count, new.blocks.count)
        for i in 0..<shared where old.blocks[i] != new.blocks[i] {
            return (new.blocks[i].id, changeOffset(old.blocks[i], new.blocks[i], atEnd: atEnd))
        }
        if new.blocks.count != old.blocks.count {
            if new.blocks.indices.contains(shared) { return (new.blocks[shared].id, 0) }
            if let last = new.blocks.last { return (last.id, 0) }
            return nil
        }
        if old.cuts != new.cuts {
            if let cut = new.cuts.first(where: { !old.cuts.contains($0) }) ?? old.cuts.first(where: { !new.cuts.contains($0) }),
               new.blocks.contains(where: { $0.id == cut.blockID }) {
                return (cut.blockID, 0)
            }
        }
        return nil
    }

    /// Where two paragraph blocks' text differs, in the *new* block's coordinates: the
    /// first differing index (`atEnd == false`, for undo) or the end of the changed
    /// region — new length minus the shared suffix (`atEnd == true`, for redo, so the
    /// caret sits after the re-added text). 0 for non-paragraph content.
    private func changeOffset(_ old: Block, _ new: Block, atEnd: Bool) -> Int {
        guard case .paragraph(let oldRuns) = old.content,
              case .paragraph(let newRuns) = new.content else { return 0 }
        let oldText = Array(oldRuns.map(\.text).joined())
        let newText = Array(newRuns.map(\.text).joined())
        if atEnd {
            var suffix = 0
            while suffix < min(oldText.count, newText.count)
                && oldText[oldText.count - 1 - suffix] == newText[newText.count - 1 - suffix] { suffix += 1 }
            return newText.count - suffix
        }
        let shared = min(oldText.count, newText.count)
        var prefix = 0
        while prefix < shared && oldText[prefix] == newText[prefix] { prefix += 1 }
        return prefix
    }
}
