//
//  SnippetCompletion.swift
//  Galley
//
//  Purpose: The AppKit surface for `@`-snippet completion (§9) — a non-focus
//  stealing `NSPopover` listing the matching snippet names at the caret. All
//  matching and insertion logic lives in the headless `SnippetIndex` (GalleyShell)
//  and the `InputController`; this controller only presents and positions, so the
//  editor keeps receiving keystrokes while the list is visible.
//  Public interface: `SnippetCompletionPopover`.
//  Owner context: Galley — the macOS shell's reference UI.
//

import AppKit
import SwiftUI

/// A non-focus-stealing popover listing the current `@`-snippet matches.
///
/// The owning `InputController` owns the selection index and all key handling; this
/// controller just renders the list and keeps itself anchored to the caret. Its
/// behaviour is `.applicationDefined` so it never auto-dismisses on the typing that
/// drives it — the controller hides it explicitly.
@MainActor
final class SnippetCompletionPopover {

    private let popover = NSPopover()
    private let host = NSHostingController(rootView: CompletionList(names: [], selected: 0))

    init() {
        popover.behavior = .applicationDefined
        popover.animates = false
        host.sizingOptions = .preferredContentSize   // popover sizes to the SwiftUI content
        popover.contentViewController = host
    }

    /// Whether the list is currently on screen.
    var isShown: Bool { popover.isShown }

    /// Shows or re-anchors the list at the caret with the given names/selection.
    func show(names: [String], selected: Int, caretRect: NSRect, in view: NSView) {
        host.rootView = CompletionList(names: names, selected: selected)
        if !popover.isShown {
            popover.show(relativeTo: caretRect, of: view, preferredEdge: .maxY)
        }
    }

    /// Updates the names/selection of an already-visible list.
    func update(names: [String], selected: Int) {
        host.rootView = CompletionList(names: names, selected: selected)
    }

    /// Hides the list if shown.
    func hide() {
        if popover.isShown { popover.performClose(nil) }
    }
}

/// The `@`-completion match list. Highlights the selected row; non-interactive so
/// it never steals focus from the editor.
private struct CompletionList: View {
    let names: [String]
    let selected: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                Text(name)
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
