//
//  DocumentEditing.swift
//  UntitledCore
//
//  Purpose: The block-lifecycle operations (ADR-0010) — split, merge, delete,
//  and same-block-edit cut adjustment — that mutate the block stream while
//  keeping every ChapterCut anchored correctly. These are the highest-risk
//  operations in the core; their whole job is that a cut never dangles and
//  never drifts off the text it marks.
//  Public interface: `Document.splitBlock/mergeBlocks/deleteBlock/adjustCutOffset`,
//  and `BlockOperationError`.
//  Owner context: UntitledCore — UI-free Swift, the model-as-truth (ADR-0004).
//

/// Why a block-lifecycle operation refused.
public enum BlockOperationError: Error, Equatable {

    /// No block in the stream has the given id.
    case blockNotFound(BlockID)

    /// The offset is outside `0...length` for the named block.
    case offsetOutOfRange(BlockID, offset: Int, length: Int)

    /// The operation requires a paragraph but the block is a scene break or set-piece.
    case notAParagraph(BlockID)

    /// `mergeBlocks` requires `second` to immediately follow `first`; it did not.
    case blocksNotAdjacent(BlockID, BlockID)
}

extension Document {

    /// Splits a paragraph block at a character offset (ADR-0010 "split").
    ///
    /// The original block keeps its id and the head text; a new block with a
    /// freshly minted id receives the tail and is inserted immediately after.
    /// Cuts on the block at or beyond `offset` re-anchor to the new block,
    /// rebased to the tail's coordinates.
    ///
    /// - Parameters:
    ///   - id: the block to split.
    ///   - offset: character offset within the block, in `0...length`.
    /// - Throws: `BlockOperationError.blockNotFound`, `.notAParagraph`, or
    ///   `.offsetOutOfRange`.
    public mutating func splitBlock(id: BlockID, atOffset offset: Int) throws {
        guard let i = blocks.firstIndex(where: { $0.id == id }) else {
            throw BlockOperationError.blockNotFound(id)
        }
        guard case .paragraph(let runs) = blocks[i].content else {
            throw BlockOperationError.notAParagraph(id)
        }
        let length = runsTextLength(runs)
        guard offset >= 0, offset <= length else {
            throw BlockOperationError.offsetOutOfRange(id, offset: offset, length: length)
        }

        let (head, tail) = splitRuns(runs, at: offset)
        blocks[i].content = .paragraph(runs: head)

        let newID = mintBlockID()
        // The trailing half is the same kind of paragraph, so it inherits any
        // per-block presentation overrides.
        let newBlock = Block(id: newID, content: .paragraph(runs: tail), overrides: blocks[i].overrides)
        blocks.insert(newBlock, at: i + 1)

        for k in cuts.indices {
            guard cuts[k].blockID == id, let co = cuts[k].offsetInBlock, co >= offset else { continue }
            cuts[k].blockID = newID
            cuts[k].offsetInBlock = co - offset
        }
    }

    /// Merges the paragraph `second` onto the end of the adjacent paragraph
    /// `first` (ADR-0010 "merge"). `first` survives; `second` is retired.
    ///
    /// Cuts on `second` re-anchor to `first`, shifted by `first`'s prior length
    /// so they keep their position in the joined text; a boundary cut on `second`
    /// becomes a mid-block cut at that length.
    ///
    /// - Parameters:
    ///   - first: the surviving block; must directly precede `second`.
    ///   - second: the block whose content is appended and whose id is retired.
    /// - Throws: `BlockOperationError.blockNotFound`, `.blocksNotAdjacent`, or
    ///   `.notAParagraph`.
    public mutating func mergeBlocks(first: BlockID, second: BlockID) throws {
        guard let i = blocks.firstIndex(where: { $0.id == first }) else {
            throw BlockOperationError.blockNotFound(first)
        }
        guard let j = blocks.firstIndex(where: { $0.id == second }) else {
            throw BlockOperationError.blockNotFound(second)
        }
        guard j == i + 1 else {
            throw BlockOperationError.blocksNotAdjacent(first, second)
        }
        guard case .paragraph(let firstRuns) = blocks[i].content else {
            throw BlockOperationError.notAParagraph(first)
        }
        guard case .paragraph(let secondRuns) = blocks[j].content else {
            throw BlockOperationError.notAParagraph(second)
        }

        let mergeOffset = runsTextLength(firstRuns)
        blocks[i].content = .paragraph(runs: coalesceRuns(firstRuns + secondRuns))
        blocks.remove(at: j)

        for k in cuts.indices where cuts[k].blockID == second {
            cuts[k].blockID = first
            cuts[k].offsetInBlock = mergeOffset + (cuts[k].offsetInBlock ?? 0)
        }
    }

    /// Deletes a block entirely (ADR-0010 "delete"), relocating any cut anchored
    /// to it to the nearest surviving boundary.
    ///
    /// Relocation target: the start (`offsetInBlock == nil`) of the block that
    /// now occupies the deleted slot; or, if the deleted block was last, the end
    /// of the new last block; or the cut is dropped if the document is now empty.
    ///
    /// - Parameter id: the block to remove.
    /// - Throws: `BlockOperationError.blockNotFound`.
    public mutating func deleteBlock(id: BlockID) throws {
        guard let i = blocks.firstIndex(where: { $0.id == id }) else {
            throw BlockOperationError.blockNotFound(id)
        }
        blocks.remove(at: i)

        if blocks.isEmpty {
            cuts.removeAll { $0.blockID == id }
            return
        }

        let targetID: BlockID
        let targetOffset: Int?
        if i < blocks.count {
            targetID = blocks[i].id          // former next block — anchor to its start
            targetOffset = nil
        } else {
            let last = blocks[blocks.count - 1]
            targetID = last.id               // deleted the last block — anchor to previous end
            targetOffset = contentTextLength(last.content)
        }

        for k in cuts.indices where cuts[k].blockID == id {
            cuts[k].blockID = targetID
            cuts[k].offsetInBlock = targetOffset
        }
    }

    /// Adjusts cut offsets for a same-block text edit (ADR-0010 "same-block edit").
    ///
    /// Models inserting (`delta > 0`) or deleting (`delta < 0`) `|delta|`
    /// characters at `pivot` within one block. Cuts strictly after `pivot` shift
    /// by `delta`; a cut whose anchored text fell inside a deletion clamps to
    /// `pivot`. Cuts at or before `pivot`, boundary cuts, and cuts on other
    /// blocks are untouched. A no-op when `delta == 0`.
    ///
    /// - Parameters:
    ///   - blockID: the edited block.
    ///   - pivot: character position where text was inserted or deletion began.
    ///   - delta: signed character count; positive inserts, negative deletes.
    public mutating func adjustCutOffset(blockID: BlockID, at pivot: Int, delta: Int) {
        guard delta != 0 else { return }

        for k in cuts.indices {
            guard cuts[k].blockID == blockID, let co = cuts[k].offsetInBlock else { continue }

            if delta > 0 {
                if co > pivot { cuts[k].offsetInBlock = co + delta }
            } else {
                let removed = -delta
                let end = pivot + removed
                if co >= end {
                    cuts[k].offsetInBlock = co - removed
                } else if co > pivot {
                    cuts[k].offsetInBlock = pivot   // anchored text was deleted
                }
            }
        }
    }
}
