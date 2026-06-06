//
//  ChapterEditing.swift
//  GalleyCore
//
//  Purpose: Placing, removing, and moving chapter cuts on the movable overlay
//  (ADR-0005) — the model operations behind the reveal pane's chapter-slicing
//  mode (§6, ADR-0006). These edit the `cuts` overlay directly; they are not
//  block-lifecycle operations (ADR-0010) and never touch the block stream.
//  Phase 4 places cuts at block boundaries (`offsetInBlock == nil`); mid-block
//  cut placement is a later refinement.
//  Public interface: `Document.placeChapterCut(atBlock:)`,
//  `removeChapterCut(atBlock:)`, `moveChapterCut(fromBlock:toBlock:)`.
//  Owner context: GalleyCore — UI-free Swift, the model-as-truth (ADR-0004).
//

extension Document {

    /// Places a boundary chapter cut at the start of a block (§6).
    ///
    /// - Parameter blockID: the block the chapter begins at.
    /// - Note: no-op if the block does not exist or already carries a boundary cut,
    ///   so the overlay never gains a duplicate or a dangling anchor.
    public mutating func placeChapterCut(atBlock blockID: BlockID) {
        guard blocks.contains(where: { $0.id == blockID }) else { return }
        guard !cuts.contains(where: { $0.blockID == blockID && $0.offsetInBlock == nil }) else { return }
        cuts.append(ChapterCut(blockID: blockID, offsetInBlock: nil))
    }

    /// Removes the boundary chapter cut anchored at a block, if any (§6).
    ///
    /// - Parameter blockID: the anchor block whose boundary cut is removed. Mid-block
    ///   cuts on the same block are left untouched.
    public mutating func removeChapterCut(atBlock blockID: BlockID) {
        cuts.removeAll { $0.blockID == blockID && $0.offsetInBlock == nil }
    }

    /// Sets (or clears) the title of the boundary chapter cut at a block (§6).
    ///
    /// - Parameters:
    ///   - blockID: the anchor block whose boundary cut is retitled.
    ///   - title: the new title; an empty or `nil` title clears it.
    /// - Note: no-op if no boundary cut is anchored at `blockID`.
    public mutating func setChapterCutTitle(atBlock blockID: BlockID, to title: String?) {
        guard let index = cuts.firstIndex(where: { $0.blockID == blockID && $0.offsetInBlock == nil }) else { return }
        cuts[index].title = (title?.isEmpty ?? true) ? nil : title
    }

    /// Moves a boundary chapter cut from one block to another, preserving its
    /// title and opener (§6).
    ///
    /// - Parameters:
    ///   - source: the block the cut currently anchors to.
    ///   - target: the block to re-anchor it to.
    /// - Note: no-op if `source` has no boundary cut, `target` does not exist, or
    ///   `target` already carries a boundary cut.
    public mutating func moveChapterCut(fromBlock source: BlockID, toBlock target: BlockID) {
        guard let index = cuts.firstIndex(where: { $0.blockID == source && $0.offsetInBlock == nil }) else { return }
        guard blocks.contains(where: { $0.id == target }) else { return }
        guard !cuts.contains(where: { $0.blockID == target && $0.offsetInBlock == nil }) else { return }
        cuts[index].blockID = target
    }
}
