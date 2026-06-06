//
//  InputController+Palette.swift
//  Galley
//
//  Purpose: The Cmd-; Block Palette behaviour for the editor (BP2). Summons the
//  palette at the caret, drives its list from the buffer's headless `TemplateIndex`
//  (plus the Scene Break built-in), and on selection inserts the chosen block
//  through the pure reducer's `insertBlock` op (model-as-truth, ADR-0004), moving
//  the caret into the new editable block. Structure is created entirely from the
//  keyboard — the writer never leaves it (memory: keyboard-first-writing-ux). The
//  palette vocabulary and matching live in `BlockPalette`/GalleyShell; this is the
//  AppKit driver.
//  Public interface: the `keyDown` hook in `InputController` calls into these.
//  Owner context: Galley — the macOS shell's editing layer.
//

import AppKit
import GalleyCore
import GalleyShell

extension InputController {

    // MARK: Palette lifecycle

    /// Opens the Block Palette at the caret, anchored to insert after the caret's
    /// block. A no-op when the caret is not in editable text (nowhere to anchor).
    func showBlockPalette() {
        guard let buffer, let caret = caretModelPosition() else { return }
        endCompletion()                       // never overlap with @-completion

        paletteAnchor = caret.blockID
        paletteItems = BlockPalette.items(templates: buffer.templateIndex)
        paletteSelection = 0
        // `items` always includes Scene Break, so the list is never empty.
        palettePopover.show(labels: paletteItems.map(\.label), selected: 0, caretRect: caretBoundingRect(), in: self)
    }

    /// Closes the palette session and clears its state.
    func endPalette() {
        guard paletteAnchor != nil || palettePopover.isShown else { return }
        paletteAnchor = nil
        paletteItems = []
        paletteSelection = 0
        palettePopover.hide()
    }

    /// Handles a key while the palette is visible. Returns `true` if the key was
    /// consumed (the caller then stops processing it).
    func handlePaletteKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 126:   // up arrow
            paletteSelection = max(paletteSelection - 1, 0)
            palettePopover.update(labels: paletteItems.map(\.label), selected: paletteSelection)
            return true
        case 125:   // down arrow
            paletteSelection = min(paletteSelection + 1, paletteItems.count - 1)
            palettePopover.update(labels: paletteItems.map(\.label), selected: paletteSelection)
            return true
        case 36, 76, 48:   // return / keypad enter / tab — accept
            acceptPaletteSelection()
            return true
        case 53:   // esc — dismiss without inserting
            endPalette()
            return true
        default:
            return false
        }
    }

    /// Inserts the highlighted palette item as a new block after the anchor, through
    /// the `insertBlock` reducer op, then moves the caret into the new editable
    /// block. A non-editable insert (Scene Break) leaves the caret where it was.
    func acceptPaletteSelection() {
        guard let buffer,
              paletteItems.indices.contains(paletteSelection),
              let anchor = paletteAnchor else {
            endPalette()
            return
        }

        let (content, overrides) = blockContent(for: paletteItems[paletteSelection].action)
        buffer.apply(.insertBlock(content: content, overrides: overrides, afterBlockID: anchor))
        endPalette()

        // The new block is the one now sitting immediately after the anchor. Place
        // the caret at its start; for a non-editable Scene Break this maps to nil
        // and the selection is simply left untouched.
        let doc = buffer.document
        if let i = doc.blocks.firstIndex(where: { $0.id == anchor }), i + 1 < doc.blocks.count {
            renderFromModel(caret: (doc.blocks[i + 1].id, 0))
        } else {
            renderFromModel(caret: nil)
        }
    }

    /// The model content + overrides a palette action inserts.
    ///
    /// A template becomes a single editable paragraph seeded with its body; any stray
    /// newline is flattened to a space so the block stays one logical paragraph
    /// (multi-paragraph templates are a deferred v1 limit). Scene Break inserts the
    /// ornament with no overrides.
    private func blockContent(for action: BlockPaletteAction) -> (BlockContent, [PresentationOverride]) {
        switch action {
        case .sceneBreak:
            return (.sceneBreak, [])
        case .template(let template):
            let body = template.body.replacingOccurrences(of: "\n", with: " ")
            return (.paragraph(runs: [Run(text: body)]), template.overrides)
        }
    }
}
