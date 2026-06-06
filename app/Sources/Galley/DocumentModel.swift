//
//  DocumentModel.swift
//  Galley
//
//  Purpose: The window's observable document state — holds the in-memory
//  `Document` (the model-as-truth, ADR-0004) and the bundle URL it loaded from,
//  and drives open/save through `NSOpenPanel`/`NSSavePanel` and `DocumentBundle`.
//  Phase 1 is a scaffold: it round-trips the file pair and reports status; there
//  is no editing surface or projection yet.
//  Public interface: `DocumentModel`, its observable `document`/`fileURL`/`status`
//  state, and `open()` / `save()` / `saveAs()`.
//  Owner context: Galley — the macOS shell's view-state. AppKit/SwiftUI live
//  here; never in GalleyCore.
//

import AppKit
import Observation
import SwiftUI
import GalleyCore
import GalleyShell

/// Observable view-state for a single document window.
///
/// Owns the live `Document` and the bundle URL it is associated with. The open
/// and save commands delegate the format to `DocumentBundle`; this type only
/// mediates the file panels and surfaces a human-readable `status`.
@MainActor
@Observable
public final class DocumentModel {

    /// The live document (the model-as-truth). Mutated only through load/save here
    /// in Phase 1; editing arrives in Phase 3.
    public private(set) var document: Document

    /// The bundle directory this document was last opened from or saved to, if any.
    public private(set) var fileURL: URL?

    /// A short human-readable description of the last open/save outcome.
    public private(set) var status: String

    /// Creates a model holding a fresh document seeded with one empty paragraph,
    /// so the editor always has a block to place the caret in.
    public init() {
        self.document = DocumentModel.blank
        self.fileURL = nil
        self.status = "New document."
    }

    /// A document with a single empty paragraph — the editable starting point.
    private static var blank: Document {
        Document(blocks: [Block(id: 0, content: .paragraph(runs: []))], nextBlockID: 1)
    }

    /// Prompts for an `.galley` bundle directory and loads it into `document`.
    ///
    /// On success, replaces `document` and sets `fileURL`. On failure, leaves both
    /// unchanged and records the reason in `status`. A cancelled panel is a no-op.
    public func open() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose an .galley document folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(from: url)
    }

    /// Loads a bundle from a known URL without prompting (used by `open()` and the
    /// `UNTITLED_OPEN` launch hook).
    ///
    /// On success replaces `document` and sets `fileURL`; on failure leaves both
    /// unchanged and records the reason in `status`.
    func load(from url: URL) {
        do {
            document = try DocumentBundle.read(from: url)
            fileURL = url
            status = "Opened \(url.lastPathComponent) — \(document.blocks.count) block(s)."
        } catch {
            status = "Open failed: \(error)"
        }
    }

    /// Applies one editing intent to the document via the pure core reducer (§8),
    /// keeping the model the single source of truth (ADR-0004).
    ///
    /// - Parameter event: the model-coordinate editing intent from the input layer.
    func apply(_ event: InputEvent) {
        document = applyInput(event, to: document)
    }

    // MARK: Submission metadata

    /// A two-way binding to a string metadata field, for the submission-fields
    /// panel. Edits flow straight into the document (and persist on save).
    func metaBinding(_ keyPath: WritableKeyPath<Metadata, String>) -> Binding<String> {
        Binding(
            get: { self.document.meta[keyPath: keyPath] },
            set: { self.document.meta[keyPath: keyPath] = $0 }
        )
    }

    // MARK: Chapter overlay (reveal pane chapter-slicing, §6)

    /// Places a boundary chapter cut at a block.
    func placeCut(atBlock blockID: BlockID) { document.placeChapterCut(atBlock: blockID) }

    /// Removes the boundary chapter cut at a block.
    func removeCut(atBlock blockID: BlockID) { document.removeChapterCut(atBlock: blockID) }

    /// Moves a boundary chapter cut from one block to another.
    func moveCut(fromBlock source: BlockID, toBlock target: BlockID) {
        document.moveChapterCut(fromBlock: source, toBlock: target)
    }

    /// Sets (or clears) the title of the boundary chapter cut at a block.
    func setCutTitle(atBlock blockID: BlockID, to title: String?) {
        document.setChapterCutTitle(atBlock: blockID, to: title)
    }

    /// Saves to the current `fileURL`, or prompts for a location if there is none.
    public func save() {
        if let url = fileURL {
            persist(to: url)
        } else {
            saveAs()
        }
    }

    /// Prompts for a destination `.galley` bundle and saves the document there.
    ///
    /// On success, records the new `fileURL`. A cancelled panel is a no-op.
    public func saveAs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Untitled.galley"
        panel.message = "Save as an .galley document folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        if persist(to: url) {
            fileURL = url
        }
    }

    /// Writes `document` to `url` via `DocumentBundle`, updating `status`.
    ///
    /// - Returns: `true` on success, `false` if the write threw.
    @discardableResult
    private func persist(to url: URL) -> Bool {
        do {
            try DocumentBundle.write(document, to: url)
            status = "Saved \(url.lastPathComponent)."
            return true
        } catch {
            status = "Save failed: \(error)"
            return false
        }
    }
}
