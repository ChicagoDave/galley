//
//  BiblePane.swift
//  Galley
//
//  Purpose: The bible slide-out panel (§9) — a read-only reference browser beside
//  the editor (toggled like the reveal and fields panels). Lists the buffer's bible
//  entries, filters them as the writer types in a search box, and shows the selected
//  entry's full note. All lookup runs through the headless `BibleIndex`
//  (GalleyShell); this view only presents (ADR-0011, ADR-0020).
//  Public interface: `BiblePane`.
//  Owner context: Galley — the macOS shell's SwiftUI view layer.
//

import SwiftUI
import GalleyShell
import GalleyCore

/// A read-only side panel that browses the current buffer's bible entries.
struct BiblePane: View {

    /// The document buffer whose bible is shown.
    var buffer: WorkspaceDocument

    /// The current search text; filters the entry list as the writer types.
    @State private var query = ""

    /// The name of the selected entry, or `nil` to default to the first result.
    @State private var selectedName: String?

    /// The entries matching the current search, best-first.
    private var results: [BibleEntry] { buffer.bibleIndex.matches(for: query, limit: 100) }

    /// The entry to display: the selected one if still in results, else the first.
    private var selected: BibleEntry? {
        if let selectedName, let entry = buffer.bibleIndex.entry(named: selectedName),
           results.contains(where: { $0.name == selectedName }) {
            return entry
        }
        return results.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("BIBLE")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            TextField("Search", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            if buffer.bibleIndex.entries.isEmpty {
                emptyState
            } else {
                List(results, id: \.name, selection: $selectedName) { entry in
                    Text(entry.name).tag(entry.name)
                }
                .frame(maxHeight: 220)

                Divider()

                ScrollView {
                    if let selected {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(selected.name).font(.headline)
                            Text(selected.notes)
                                .font(.body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(12)
                    } else {
                        Text("No match.")
                            .foregroundStyle(.secondary)
                            .padding(12)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(width: 300)
    }

    /// Shown when the package has no `bible/` entries yet.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No bible entries.").font(.callout)
            Text("Add one Markdown file per entity to the package's bible/ folder (e.g. aldous-finch.md).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }
}
