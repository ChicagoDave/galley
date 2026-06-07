//
//  WorkspaceDocument.swift
//  GalleyShell
//
//  Purpose: One open document buffer's headless state — the live `Document`
//  (model-as-truth, ADR-0004), the `.galley` bundle URL it loads from / saves to,
//  a human-readable status line, and the load / persist / edit operations over it.
//  This is the per-buffer unit the workspace (`WorkspaceModel`) holds. It carries
//  no AppKit or SwiftUI, so it is unit-testable headlessly (ADR-0011); the file
//  panels that choose URLs live in the `Galley` executable, never here.
//  Public interface: `WorkspaceDocument`, its observable `document` / `fileURL` /
//  `status` state, `hasContent`, `load(from:)`, `persist(to:)`, `apply(_:)`,
//  `setMetadata(_:to:)`, and the chapter-overlay editing methods.
//  Owner context: GalleyShell — app-layer document state. Depends on GalleyCore
//  (the model-as-truth) plus Foundation and Observation only; no AppKit/SwiftUI.
//

import Foundation
import Observation
import GalleyCore

/// Observable state for a single open document buffer.
///
/// Owns the live `Document` and the bundle URL it is associated with. Load and
/// save delegate the on-disk format to `DocumentBundle`; this type mediates the
/// buffer's state and surfaces a human-readable `status`. A reference type so the
/// owning `WorkspaceModel` and the SwiftUI view tree observe and mutate one shared
/// instance per buffer.
@MainActor
@Observable
public final class WorkspaceDocument {

    /// The live document (the model-as-truth). Mutated only through `load`,
    /// `apply`, `setMetadata`, and the chapter-overlay methods below.
    public private(set) var document: Document

    /// Pre-edit document snapshots for undo, oldest first. Each editing mutator
    /// pushes the prior document here before changing it; `undo()` pops the top.
    private var undoStack: [Document] = []

    /// Document snapshots redo can restore, newest-undone last. Cleared by any new
    /// edit, so the timeline never forks (standard undo semantics).
    private var redoStack: [Document] = []

    /// The deepest the undo history grows before the oldest snapshot is dropped.
    private static let undoLimit = 500

    /// The bundle directory this buffer was last opened from or saved to, if any.
    /// `nil` for a brand-new buffer that has never been saved.
    public private(set) var fileURL: URL?

    /// A short human-readable description of the last open/save outcome.
    public private(set) var status: String

    /// The reference bible for this buffer (§9), fuzzy-indexed from the package's
    /// `bible/` directory — read in the bible side panel. Empty for a never-saved
    /// buffer (no package on disk yet).
    public private(set) var bibleIndex = BibleIndex()

    /// The reusable text snippets for this buffer (§9), indexed from the package's
    /// `snippets/` directory — the source for `@`-completion. Empty until saved.
    public private(set) var snippetIndex = SnippetIndex()

    /// The reusable block templates for this buffer (BP1), indexed from the
    /// package's `templates/` directory — the source for the Block Palette (BP2).
    /// Empty for a never-saved buffer (no package on disk yet).
    public private(set) var templateIndex = TemplateIndex()

    /// Figure image references (LT4-2) that name a file missing from the package's
    /// `images/` directory — surfaced as a non-blocking warning, never a load
    /// failure (a figure records intent; the typesetter resolves the file, ADR-0024).
    /// Recomputed on load and save; empty for a never-saved buffer or when every
    /// non-empty ref resolves.
    public private(set) var missingImageRefs: [String] = []

    /// Creates a buffer. Defaults to a fresh blank document with no associated file.
    ///
    /// - Parameters:
    ///   - document: the initial document; defaults to a single empty paragraph.
    ///   - fileURL: the associated bundle URL; defaults to none (unsaved buffer).
    ///   - status: the initial status line.
    public init(
        document: Document = WorkspaceDocument.blankDocument,
        fileURL: URL? = nil,
        status: String = "New document."
    ) {
        self.document = document
        self.fileURL = fileURL
        self.status = status
        // A fresh buffer still gets the built-in (and user-level) template toolkit,
        // so the Block Palette is never empty in a new project (LT1, ADR-0025).
        reloadIndexes()
    }

    /// A document with a single empty paragraph — the editable starting point, so
    /// the editor always has a block to place the caret in.
    public static var blankDocument: Document {
        Document(blocks: [Block(id: 0, content: .paragraph(runs: []))], nextBlockID: 1)
    }

    /// Whether any run in any block carries non-empty text.
    ///
    /// The signal that a blank buffer has actually been written into — it drives the
    /// save-or-discard prompt on close (ADR-0015). A lone scene break (no text of
    /// its own) does not count as content.
    public var hasContent: Bool {
        document.blocks.contains { block in
            switch block.content {
            case .paragraph(let runs):
                return runs.contains { !$0.text.isEmpty }
            case .setPiece(_, let lines):
                return lines.contains { line in line.contains { !$0.text.isEmpty } }
            case .sceneBreak:
                return false
            case .figure(let imageRef, let caption):
                return !imageRef.isEmpty || !caption.isEmpty   // a placed figure is real content
            }
        }
    }

    /// Loads a `.galley` bundle from disk into this buffer.
    ///
    /// On success replaces `document`, sets `fileURL`, and records a status. On
    /// failure throws and leaves `document`, `fileURL`, and `status` unchanged, so a
    /// failed open never corrupts the buffer the caller is about to discard.
    ///
    /// - Parameter url: the bundle directory URL.
    /// - Throws: `DocumentBundle.BundleError`, a `GalleyCore.ParseError`, or a
    ///   Foundation I/O error if the bundle cannot be read.
    public func load(from url: URL) throws {
        let loaded = try DocumentBundle.read(from: url)
        document = loaded
        fileURL = url
        reloadIndexes()
        revalidateImageRefs()
        status = "Opened \(url.lastPathComponent) — \(loaded.blocks.count) block(s)."
    }

    /// Rebuilds the reference indexes (§9, BP1, LT1).
    ///
    /// The **template index is layered** (ADR-0025): built-in templates + the
    /// user-level global directory are always merged in, plus the per-project
    /// `templates/` directory when this buffer is saved — so even a brand-new unsaved
    /// buffer offers the built-in (and user) toolkit. **Bible and snippets stay
    /// project-scoped** (this novel's data, ADR-0020): they load only from the
    /// package and are empty for a never-saved buffer.
    ///
    /// Called on init, load, and after save; safe to call any time the writer may
    /// have added or edited reference files.
    public func reloadIndexes() {
        templateIndex = TemplateIndex.merged(
            builtIns: BuiltInTemplates.all,
            userDirectory: TemplateIndex.userTemplateDirectory,
            storyDirectory: fileURL?.appendingPathComponent("templates", isDirectory: true)
        )

        guard let url = fileURL else {
            bibleIndex = BibleIndex()
            snippetIndex = SnippetIndex()
            return
        }
        bibleIndex = BibleIndex.load(directory: url.appendingPathComponent("bible", isDirectory: true))
        snippetIndex = SnippetIndex.load(directory: url.appendingPathComponent("snippets", isDirectory: true))
    }

    /// Writes this buffer to `url` via `DocumentBundle`, recording `fileURL` and
    /// status on success.
    ///
    /// - Parameter url: the destination bundle directory.
    /// - Returns: `true` on success, `false` if the write threw (status records why).
    @discardableResult
    public func persist(to url: URL) -> Bool {
        do {
            try DocumentBundle.write(document, to: url)
            fileURL = url
            ensureImagesDirectory(in: url)
            reloadIndexes()
            revalidateImageRefs()
            status = "Saved \(url.lastPathComponent)."
            return true
        } catch {
            status = "Save failed: \(error)"
            return false
        }
    }

    // MARK: Figure images (LT4-2)

    /// The non-empty image references of every figure block, in document order.
    private var figureImageRefs: [String] {
        document.blocks.compactMap { block in
            guard case .figure(let imageRef, _) = block.content, !imageRef.isEmpty else { return nil }
            return imageRef
        }
    }

    /// Creates the package's `images/` directory if the document references any
    /// image and the directory does not exist yet. The directory holds writer-placed
    /// assets (ADR-0020 pattern); we never copy or fetch image content (ADR-0024).
    private func ensureImagesDirectory(in url: URL) {
        guard !figureImageRefs.isEmpty else { return }
        let images = url.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
    }

    /// Recomputes `missingImageRefs`: every non-empty figure ref whose file is absent
    /// from the package's `images/` directory. Empty when there is no package yet
    /// (a never-saved buffer cannot have missing files — there is nowhere to look).
    private func revalidateImageRefs() {
        guard let url = fileURL else { missingImageRefs = []; return }
        let images = url.appendingPathComponent("images", isDirectory: true)
        missingImageRefs = figureImageRefs.filter { ref in
            !FileManager.default.fileExists(atPath: images.appendingPathComponent(ref).path)
        }
    }

    // MARK: Undo / redo (model snapshots)

    /// Whether there is a prior document state to restore.
    public var canUndo: Bool { !undoStack.isEmpty }

    /// Whether an undone state can be re-applied.
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Records the current document as an undo checkpoint before an edit, and clears
    /// the redo timeline (a new edit forks off any undone future). Every editing
    /// mutator calls this first; load/persist do not (opening a file is not an edit).
    private func checkpoint() {
        undoStack.append(document)
        if undoStack.count > WorkspaceDocument.undoLimit {
            undoStack.removeFirst(undoStack.count - WorkspaceDocument.undoLimit)
        }
        redoStack.removeAll(keepingCapacity: true)
    }

    /// Restores the most recent pre-edit document (Cmd-Z). The current document is
    /// pushed onto the redo stack so it can be re-applied. No-op when nothing to undo.
    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document)
        document = previous
    }

    /// Re-applies the most recently undone document (Cmd-Shift-Z). No-op when there
    /// is nothing to redo.
    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        document = next
    }

    /// Applies one editing intent to the document via the pure core reducer (§8),
    /// keeping the model the single source of truth (ADR-0004). Checkpoints the prior
    /// state for undo.
    ///
    /// - Parameter event: the model-coordinate editing intent from the input layer.
    public func apply(_ event: InputEvent) {
        checkpoint()
        document = applyInput(event, to: document)
    }

    /// Sets a single string metadata field on the document (submission fields).
    ///
    /// The controlled mutator behind the SwiftUI metadata bindings — the view layer
    /// cannot write `document` directly, so it routes field edits through here.
    ///
    /// - Parameters:
    ///   - keyPath: the metadata field to write.
    ///   - value: the new value.
    public func setMetadata(_ keyPath: WritableKeyPath<Metadata, String>, to value: String) {
        checkpoint()
        document.meta[keyPath: keyPath] = value
    }

    // MARK: Chapter overlay (reveal-pane chapter-slicing, §6)

    /// Places a boundary chapter cut at a block.
    public func placeCut(atBlock blockID: BlockID) { checkpoint(); document.placeChapterCut(atBlock: blockID) }

    /// Removes the boundary chapter cut at a block.
    public func removeCut(atBlock blockID: BlockID) { checkpoint(); document.removeChapterCut(atBlock: blockID) }

    /// Moves a boundary chapter cut from one block to another.
    public func moveCut(fromBlock source: BlockID, toBlock target: BlockID) {
        checkpoint()
        document.moveChapterCut(fromBlock: source, toBlock: target)
    }

    /// Sets (or clears) the title of the boundary chapter cut at a block.
    public func setCutTitle(atBlock blockID: BlockID, to title: String?) {
        checkpoint()
        document.setChapterCutTitle(atBlock: blockID, to: title)
    }

    /// Sets the caption of the figure block at `blockID` (LT4-2, ADR-0028 Option A).
    /// Routes through the pure reducer so figure-block invariants stay in the core; a
    /// no-op on an unknown or non-figure block (the reducer's total contract).
    public func setFigureCaption(atBlock blockID: BlockID, to caption: String) {
        apply(.setFigureCaption(blockID: blockID, caption: caption))
    }
}
