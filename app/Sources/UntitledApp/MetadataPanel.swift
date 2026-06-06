//
//  MetadataPanel.swift
//  UntitledApp
//
//  Purpose: The submission-fields side panel — a form over the project's fixed
//  metadata (title-page and cover-letter data every submission needs). Edits bind
//  straight into `Document.meta` through `DocumentModel` and persist on save.
//  Public interface: `MetadataPanel`.
//  Owner context: UntitledApp — the macOS shell's SwiftUI view layer.
//

import SwiftUI
import UntitledCore

/// The submission-fields editor: a grouped form bound to the document metadata.
struct MetadataPanel: View {

    @Bindable var model: DocumentModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Submission Fields")
                .font(.headline)
                .padding(12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    group("Title Page") {
                        field("Title", \.title)
                        field("Byline (pen name)", \.author)
                        field("Legal name", \.legalName)
                        field("Word count", \.wordCount)
                    }
                    group("Submission") {
                        field("Genre / category", \.genre)
                        field("Logline", \.logline)
                        field("Bio", \.bio, multiline: true)
                        field("Agent", \.agent)
                    }
                    group("Contact") {
                        field("Email", \.email)
                        field("Phone", \.phone)
                        field("Address", \.address, multiline: true)
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 280)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// A titled group of fields.
    @ViewBuilder
    private func group(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.bold())
            content()
        }
    }

    /// A labeled text field bound to a metadata key path; `multiline` grows to a
    /// few lines for bios and addresses.
    @ViewBuilder
    private func field(_ label: String, _ keyPath: WritableKeyPath<Metadata, String>, multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            if multiline {
                TextField(label, text: model.metaBinding(keyPath), axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
            } else {
                TextField(label, text: model.metaBinding(keyPath))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
            }
        }
    }
}
