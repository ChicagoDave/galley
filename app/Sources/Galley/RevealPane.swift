//
//  RevealPane.swift
//  Galley
//
//  Purpose: The reveal pane (§5, ADR-0006) — the truth view that renders the
//  `revealProjection` token stream as prose segments and addressable code chips,
//  and doubles as the chapter-slicing surface (ADR-0005). In chapter-edit mode it
//  exposes the chapter anchors so the writer can place, retitle, and remove
//  boundary cuts; the edits flow through `WorkspaceDocument` into the buffer.
//  Public interface: `RevealPane`.
//  Owner context: Galley — the macOS shell's SwiftUI view layer.
//

import SwiftUI
import GalleyCore
import GalleyShell

/// The reveal pane: a token-stream truth view plus a chapter-slicing editor.
struct RevealPane: View {

    @Bindable var buffer: WorkspaceDocument
    @State private var chapterEditMode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Reveal").font(.headline)
                Spacer()
                Button(chapterEditMode ? "Done" : "Edit Chapters") { chapterEditMode.toggle() }
                    .controlSize(.small)
            }

            Divider()

            ScrollView {
                FlowLayout {
                    ForEach(revealItems(from: buffer.document.revealProjection())) { item in
                        RevealItemView(buffer: buffer, item: item)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if chapterEditMode {
                Divider()
                ChapterEditor(buffer: buffer)
            }
        }
        .padding(12)
        .frame(minWidth: 300)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// One reveal item: prose text, or a colored code chip. A boundary section cut
/// renders as a role chip plus its tap-to-edit title (LT2); all other chips are
/// plain colored capsules.
private struct RevealItemView: View {

    @Bindable var buffer: WorkspaceDocument
    let item: RevealItem

    var body: some View {
        switch item.kind {
        case .text(let string):
            Text(string).font(.system(.body, design: .serif))
        case .chip(let label, let code):
            if case .chapter(let blockID, nil) = code {
                SectionChip(buffer: buffer, role: label, blockID: blockID)
            } else {
                chip(label: label, color: color(for: code))
            }
        }
    }

    /// A plain colored capsule chip.
    private func chip(label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2.monospaced())
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(color))
            .foregroundStyle(.white)
    }

    /// Chapter chips read as the structural surface; other codes are muted.
    private func color(for code: CodeID) -> Color {
        switch code {
        case .chapter: return .accentColor
        case .sceneBreak: return .orange
        case .setPieceOpen, .setPieceClose: return .purple
        case .line: return .gray
        case .italicOpen, .italicClose: return .secondary
        case .override: return .teal
        }
    }
}

/// A boundary section cut in the reveal stream: the role capsule (Chapter /
/// Prologue / …) plus its resolved title (numbering macros rendered to their
/// chapter number, ADR-0026). Read-only here — titles are edited inline in the main
/// editor by clicking the heading (LT3); the reveal is the truth view, not a second
/// editing surface.
private struct SectionChip: View {

    @Bindable var buffer: WorkspaceDocument
    let role: String
    let blockID: BlockID

    /// The display title — macros resolved to the chapter number (ADR-0026).
    private var resolvedTitle: String {
        buffer.document.resolvedTitle(forCutAt: blockID)
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(role)
                .font(.caption2.monospaced())
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.accentColor))
                .foregroundStyle(.white)

            if !resolvedTitle.isEmpty {
                Text(resolvedTitle)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
        }
    }
}

/// The chapter-slicing editor: one row per block, with a toggle to place/remove a
/// boundary cut (§6). Titling lives in the reveal stream itself (tap a section
/// chip's title, LT2), not here — structure is named in the truth view, not a panel.
private struct ChapterEditor: View {

    @Bindable var buffer: WorkspaceDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Chapters").font(.subheadline.bold())
            Text("Toggle a block to begin a chapter there. Name it by tapping its chip above.")
                .font(.caption).foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(chapterAnchors(of: buffer.document)) { anchor in
                        ChapterAnchorRow(buffer: buffer, anchor: anchor)
                    }
                }
            }
            .frame(maxHeight: 180)
        }
    }
}

/// A single chapter-anchor row: a cut toggle (place/remove a boundary cut) and the
/// block preview. Titling is done in the reveal stream (tap the section chip), not
/// here, so this row stays a pure placement control.
private struct ChapterAnchorRow: View {

    @Bindable var buffer: WorkspaceDocument
    let anchor: ChapterAnchor

    var body: some View {
        HStack(spacing: 6) {
            Toggle("", isOn: Binding(
                get: { anchor.hasCut },
                set: { isOn in
                    if isOn { buffer.placeCut(atBlock: anchor.id) }
                    else { buffer.removeCut(atBlock: anchor.id) }
                }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)

            Text(anchor.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
    }
}
