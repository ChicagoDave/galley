//
//  ContentView.swift
//  Galley
//
//  Purpose: The window contents — the editable text surface (§8) beside an
//  optional reveal pane (§5, ADR-0006), with Open/Save controls and a status
//  line. The reveal pane toggles with Cmd-/ and carries the chapter-slicing mode.
//  Public interface: `ContentView`.
//  Owner context: Galley — the macOS shell's SwiftUI view layer.
//

import SwiftUI
import GalleyShell

/// The single-window editing surface, optionally split with the reveal pane.
///
/// Binds to a `WorkspaceModel` and renders its current buffer: the editable
/// `DocumentTextView` writes through that buffer, and the `RevealPane` reads its
/// projection and edits its chapter overlay. New/Open/Save act on the workspace.
struct ContentView: View {

    /// The workspace driving this window — the open buffers and the current one.
    @Bindable var workspace: WorkspaceModel

    /// Whether the reveal pane is shown (toggled with Cmd-/).
    @State private var showReveal = false

    /// Whether the submission-fields panel is shown (toggled with Cmd-Shift-I).
    @State private var showFields = false

    /// The buffer currently shown in the window.
    private var current: WorkspaceDocument { workspace.current }

    /// The app + project name for the window title bar: "Galley — <title>" when
    /// the document is titled, otherwise just "Galley".
    private var projectTitle: String {
        let title = current.document.meta.title
        return title.isEmpty ? "Galley" : "Galley — \(title)"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if showFields {
                    MetadataPanel(buffer: current)
                    Divider()
                }

                DocumentTextView(buffer: current)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showReveal {
                    Divider()
                    RevealPane(buffer: current)
                        .frame(width: 340)
                }
            }

            Divider()

            HStack(spacing: 12) {
                Button("Open…") { workspace.openWithPanel() }
                Button("Save…") { workspace.saveCurrentWithPanel() }
                Button(showFields ? "Hide Fields" : "Fields") { showFields.toggle() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Button(showReveal ? "Hide Reveal" : "Reveal") { showReveal.toggle() }
                    .keyboardShortcut("/", modifiers: .command)
                Spacer()
                Text("Project \(workspace.currentIndex + 1) of \(workspace.documents.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Text(current.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 700, minHeight: 480)
        .navigationTitle(projectTitle)   // drives the window's title bar
        .confirmationDialog(
            "Save changes before closing this project?",
            isPresented: Binding(
                get: { workspace.pendingCloseIndex != nil },
                set: { presented in if !presented { workspace.pendingCloseIndex = nil } }
            ),
            presenting: workspace.pendingCloseIndex
        ) { index in
            Button("Save…") {
                workspace.saveCurrentWithPanel()
                // Only close if the save actually landed a file (panel not cancelled).
                if workspace.documents.indices.contains(index),
                   workspace.documents[index].fileURL != nil {
                    workspace.close(index: index)
                }
                workspace.pendingCloseIndex = nil
            }
            Button("Discard", role: .destructive) {
                workspace.discardAndClose(index: index)
                workspace.pendingCloseIndex = nil
            }
            Button("Cancel", role: .cancel) {
                workspace.pendingCloseIndex = nil
            }
        }
    }
}
