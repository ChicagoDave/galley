//
//  Galley.swift
//  Galley
//
//  Purpose: The macOS app entry point (ADR-0001 native, ADR-0003 AppKit-hosted)
//  — a single-window SwiftUI shell over GalleyCore. Phase 1 is a scaffold: it
//  opens and saves the `.galley` bundle pair and reports status; the editing
//  surface arrives in later phases.
//  Public interface: `Galley` (`@main`).
//  Owner context: Galley — the macOS shell. AppKit/SwiftUI live here only.
//

import AppKit
import SwiftUI
import GalleyShell

/// The application entry point: one window group over a single `WorkspaceModel`
/// (an ordered set of open document buffers), with New/Open/Save wired into the
/// standard menu commands.
@main
struct Galley: App {

    /// Forces foreground-app behaviour and routes Launch Services open-document
    /// events into the workspace (see `AppDelegate`).
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// The window's workspace — the open buffers and the current one. Shared with
    /// the delegate so a Finder double-click and the scene act on one store
    /// (`AppWorkspace`, ADR-0018).
    @State private var workspace = AppWorkspace.shared

    var body: some Scene {
        WindowGroup("Galley") {
            ContentView(workspace: workspace)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New") { workspace.new() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Open…") { workspace.openWithPanel() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save…") { workspace.saveCurrentWithPanel() }
                    .keyboardShortcut("s", modifiers: .command)
            }
            CommandGroup(after: .saveItem) {
                Button("Close") {
                    if case .needsConfirmation(let index) = workspace.close(index: workspace.currentIndex) {
                        workspace.pendingCloseIndex = index
                    }
                }
                .keyboardShortcut("w", modifiers: .command)
            }
            CommandMenu("Projects") {
                ForEach(Array(workspace.documents.enumerated()), id: \.offset) { pair in
                    projectMenuItem(index: pair.offset, buffer: pair.element)
                }
            }
        }
    }

    /// One row in the Projects menu: a checkmarked toggle that switches to the buffer
    /// at `index`, with a Cmd-1…Cmd-9 shortcut for the first nine slots.
    @ViewBuilder
    private func projectMenuItem(index: Int, buffer: WorkspaceDocument) -> some View {
        let toggle = Toggle(
            Galley.projectTitle(for: buffer, index: index),
            isOn: Binding(
                get: { workspace.currentIndex == index },
                set: { _ in workspace.switchTo(index: index) }
            )
        )
        if index < 9 {
            toggle.keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
        } else {
            toggle
        }
    }

    /// A display title for a buffer: the document title, else its file name, else a
    /// numbered placeholder for an unsaved blank.
    static func projectTitle(for buffer: WorkspaceDocument, index: Int) -> String {
        let title = buffer.document.meta.title
        if !title.isEmpty { return title }
        if let name = buffer.fileURL?.deletingPathExtension().lastPathComponent { return name }
        return "Untitled \(index + 1)"
    }
}
