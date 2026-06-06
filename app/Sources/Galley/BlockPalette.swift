//
//  BlockPalette.swift
//  Galley
//
//  Purpose: The Block Palette (BP2) — the keyboard-first surface (Cmd-;) that
//  inserts structure without leaving the keyboard (memory: keyboard-first-writing-ux).
//  It lists the one complete built-in block (Scene Break) and the writer's own
//  block templates from the buffer's headless `TemplateIndex`, and turns the chosen
//  row into an `InputEvent.insertBlock` against the pure reducer (model-as-truth,
//  ADR-0004). Sibling to `SnippetCompletionPopover`: a non-focus-stealing list
//  popover the `InputController` drives by keyboard. Matching/templates are headless
//  (GalleyShell); this is the AppKit presentation + the item vocabulary.
//  Public interface: `BlockPaletteItem`, `BlockPalette.items(templates:)`,
//  `BlockPalettePopover`.
//  Owner context: Galley — the macOS shell's editing UI.
//
//  Scope (v1): the palette inserts editable blocks only. Set-piece kinds
//  (verse/epigraph/letter) are deferred from the palette because set-pieces are not
//  yet inline-editable (EditorLayout marks them non-editable, a Phase-3 limit) —
//  inserting one the caret cannot enter would break the "real, editable block"
//  promise. An `align:center` + `smallCaps` template serves the epigraph need today.
//

import AppKit
import SwiftUI
import GalleyCore
import GalleyShell

/// What inserting a palette row does, in model terms.
enum BlockPaletteAction: Equatable {

    /// Insert a scene-break ornament (the one complete built-in block).
    case sceneBreak

    /// Insert an editable paragraph seeded from a user template's body + overrides.
    case template(BlockTemplate)
}

/// One row of the Block Palette: its display label and the insertion it performs.
struct BlockPaletteItem: Equatable {
    let label: String
    let action: BlockPaletteAction
}

enum BlockPalette {

    /// The palette rows for a buffer: the Scene Break built-in first, then the
    /// writer's templates alphabetically. A buffer with no templates still offers
    /// Scene Break, so the palette is never empty.
    ///
    /// - Parameter templates: the buffer's loaded template index (may be empty).
    /// - Returns: the ordered palette rows.
    static func items(templates: TemplateIndex) -> [BlockPaletteItem] {
        let builtins = [BlockPaletteItem(label: "Scene Break", action: .sceneBreak)]
        let templateItems = templates.matches(for: "", limit: .max).map {
            BlockPaletteItem(label: $0.name, action: .template($0))
        }
        return builtins + templateItems
    }
}

/// A non-focus-stealing popover listing the Block Palette rows at the caret.
///
/// The owning `InputController` owns the selection index and all key handling; this
/// controller just renders the list and keeps itself anchored to the caret. Mirrors
/// `SnippetCompletionPopover`: `.applicationDefined` so it never auto-dismisses on
/// the keystrokes that drive it.
@MainActor
final class BlockPalettePopover {

    private let popover = NSPopover()
    private let host = NSHostingController(rootView: PaletteList(labels: [], selected: 0))

    init() {
        popover.behavior = .applicationDefined
        popover.animates = false
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
    }

    /// Whether the palette is currently on screen.
    var isShown: Bool { popover.isShown }

    /// Shows or re-anchors the palette at the caret with the given labels/selection.
    func show(labels: [String], selected: Int, caretRect: NSRect, in view: NSView) {
        host.rootView = PaletteList(labels: labels, selected: selected)
        if !popover.isShown {
            popover.show(relativeTo: caretRect, of: view, preferredEdge: .maxY)
        }
    }

    /// Updates the selection of an already-visible palette.
    func update(labels: [String], selected: Int) {
        host.rootView = PaletteList(labels: labels, selected: selected)
    }

    /// Hides the palette if shown.
    func hide() {
        if popover.isShown { popover.performClose(nil) }
    }
}

/// The Block Palette list. Highlights the selected row; non-interactive so it never
/// steals focus from the editor.
private struct PaletteList: View {
    let labels: [String]
    let selected: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                Text(label)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(index == selected ? Color.accentColor.opacity(0.22) : Color.clear)
            }
        }
        .padding(.vertical, 4)
        .frame(width: 240, alignment: .leading)
    }
}
