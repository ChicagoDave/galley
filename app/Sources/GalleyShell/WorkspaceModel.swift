//
//  WorkspaceModel.swift
//  GalleyShell
//
//  Purpose: The single-window workspace store — an ordered set of open document
//  buffers (`WorkspaceDocument`) plus the index of the current one. It is the
//  source of truth for which buffers are open and which is showing, and it owns the
//  New / Open / switch operations. AppKit file panels and SwiftUI menus live in the
//  `Galley` executable and call in with already-chosen URLs and indices, so the
//  store stays AppKit-free and headlessly testable (ADR-0011, fix (a)).
//  Public interface: `WorkspaceModel`, its observable `documents` / `currentIndex`
//  state, `current`, `new()`, `open(url:)`, `switchTo(index:)`, `close(index:)`,
//  `discardAndClose(index:)`, `pendingCloseIndex`, and `CloseOutcome`.
//  Owner context: GalleyShell — app-layer window/navigation state. Foundation +
//  GalleyCore (transitively, via `WorkspaceDocument`) + Observation only; no
//  AppKit/SwiftUI.
//

import Foundation
import Observation

/// The result of attempting to close a buffer.
public enum CloseOutcome: Equatable {

    /// The buffer was closed (after being persisted first, if it was file-backed).
    case closed

    /// The buffer has unsaved content and was left open: the caller must resolve it
    /// (save or discard) before it can be closed. Carries the buffer's index so the
    /// executable can prompt and then call back.
    case needsConfirmation(index: Int)
}

/// Observable state for one window's set of open document buffers.
///
/// Holds an ordered `[WorkspaceDocument]` and the `currentIndex` of the buffer on
/// screen. Switching away from a buffer auto-saves it when it has already been
/// saved once (`fileURL != nil`), so navigation is never destructive; an unsaved
/// blank buffer is left in memory untouched (ADR-0015).
///
/// Invariant: `documents` is never empty and `currentIndex` is always a valid index
/// into it, so `current` is always safe to read.
@MainActor
@Observable
public final class WorkspaceModel {

    /// The open buffers, in slot order (slot 1 is `documents[0]`).
    public private(set) var documents: [WorkspaceDocument]

    /// The index of the buffer currently shown in the window. Always in range.
    public private(set) var currentIndex: Int

    /// View-coordination state: the index of a buffer whose close is awaiting a
    /// save/discard decision, or `nil`. Set by the executable when `close` returns
    /// `.needsConfirmation`; the executable presents the sheet and then calls
    /// `close`/`discardAndClose` and clears this. Plain `Int?` state — it carries no
    /// AppKit and does not affect headless testability.
    public var pendingCloseIndex: Int?

    /// Creates a workspace with a single blank buffer — the launch state.
    public init() {
        self.documents = [WorkspaceDocument()]
        self.currentIndex = 0
    }

    /// The buffer currently shown in the window.
    ///
    /// Always valid by the type's invariant (at least one buffer; `currentIndex` in
    /// range).
    public var current: WorkspaceDocument { documents[currentIndex] }

    /// Appends a fresh blank buffer and switches to it.
    ///
    /// Auto-saves the outgoing buffer first if it has been saved before, so creating
    /// a new project never drops unsaved-to-disk work on a tracked file. Other
    /// buffers are untouched. Never rejects.
    public func new() {
        autosaveCurrentIfPersisted()
        documents.append(WorkspaceDocument())
        currentIndex = documents.count - 1
    }

    /// Loads the bundle at `url` into a new buffer and switches to it, leaving the
    /// existing buffers in place.
    ///
    /// Auto-saves the outgoing buffer (if persisted) only once the load has
    /// succeeded, so a failed open leaves the workspace entirely unchanged.
    ///
    /// - Parameter url: the bundle directory to open.
    /// - Returns: `true` if the bundle loaded and a buffer was appended; `false` if
    ///   the read failed — in which case the workspace is unchanged.
    @discardableResult
    public func open(url: URL) -> Bool {
        let buffer = WorkspaceDocument()
        do {
            try buffer.load(from: url)
        } catch {
            return false
        }
        autosaveCurrentIfPersisted()
        documents.append(buffer)
        currentIndex = documents.count - 1
        return true
    }

    /// Switches the window to the buffer at `index`, auto-saving the outgoing buffer
    /// first if it has ever been saved (ADR-0015).
    ///
    /// - Parameter index: the slot to show.
    /// - Note: an out-of-range `index` is a no-op — the workspace is unchanged.
    public func switchTo(index: Int) {
        guard documents.indices.contains(index) else { return }
        autosaveCurrentIfPersisted()
        currentIndex = index
    }

    /// Closes the buffer at `index`.
    ///
    /// A file-backed buffer is persisted, then removed. An unsaved but empty blank is
    /// removed silently. An unsaved buffer that has content is left untouched and the
    /// caller is asked to confirm (ADR-0015). Removing the last buffer leaves a fresh
    /// blank so the window always has a current buffer.
    ///
    /// - Parameter index: the slot to close.
    /// - Returns: `.closed` if the buffer was removed; `.needsConfirmation(index:)`
    ///   if it has unsaved content (the workspace is left unchanged); `.closed` for an
    ///   out-of-range index (a no-op).
    @discardableResult
    public func close(index: Int) -> CloseOutcome {
        guard documents.indices.contains(index) else { return .closed }
        let target = documents[index]

        if let url = target.fileURL {
            target.persist(to: url)
            removeBuffer(at: index)
            return .closed
        }
        if target.hasContent {
            return .needsConfirmation(index: index)
        }
        removeBuffer(at: index)
        return .closed
    }

    /// Closes the buffer at `index` unconditionally, discarding any unsaved content.
    ///
    /// The explicit override behind the close prompt's "Discard" action. Same
    /// last-buffer/neighbor handling as `close`.
    ///
    /// - Parameter index: the slot to close. Out-of-range is a no-op.
    public func discardAndClose(index: Int) {
        guard documents.indices.contains(index) else { return }
        removeBuffer(at: index)
    }

    /// Removes the buffer at `index` and keeps `current` valid.
    ///
    /// Replaces the set with a fresh blank when the last buffer is removed, otherwise
    /// adjusts `currentIndex`: it shifts left when an earlier buffer is removed, and
    /// lands on the previous neighbour (preferring `index - 1`) when the current
    /// buffer itself is removed.
    private func removeBuffer(at index: Int) {
        documents.remove(at: index)

        if documents.isEmpty {
            documents.append(WorkspaceDocument())
            currentIndex = 0
            return
        }
        if index < currentIndex {
            currentIndex -= 1
        } else if index == currentIndex {
            currentIndex = min(max(index - 1, 0), documents.count - 1)
        }
        // index > currentIndex: the current buffer is unaffected and still in range.
    }

    /// Persists the current buffer if it is backed by a file, so switching away from
    /// it never loses on-disk-tracked edits. A never-saved buffer is left in memory.
    private func autosaveCurrentIfPersisted() {
        if let url = current.fileURL {
            current.persist(to: url)
        }
    }
}
