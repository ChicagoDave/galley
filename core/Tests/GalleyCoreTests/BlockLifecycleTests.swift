//
//  BlockLifecycleTests.swift
//  GalleyCoreTests
//
//  Purpose: Behavioral tests for the ADR-0010 block-lifecycle operations. Each
//  test asserts on actual Document state after the call — block content, block
//  membership, and cut anchors — never on return values or mocks. Derived line
//  by line from the Behavior Statements for split / merge / delete / adjust.
//  Owner context: GalleyCoreTests.
//

import Testing
@testable import GalleyCore

// MARK: - Helpers

/// Builds a document of single-run paragraphs, returning it with the minted ids.
private func makeDoc(_ texts: [String]) -> (Document, [BlockID]) {
    var doc = Document()
    var ids: [BlockID] = []
    for t in texts {
        let id = doc.mintBlockID()
        ids.append(id)
        doc.blocks.append(Block(id: id, content: .paragraph(runs: t.isEmpty ? [] : [Run(text: t)])))
    }
    return (doc, ids)
}

/// The joined paragraph text of a block (empty for non-paragraphs).
private func text(of block: Block) -> String {
    if case .paragraph(let runs) = block.content { return runs.map(\.text).joined() }
    return ""
}

// MARK: - splitBlock

@Test("splitBlock: original keeps the head, a new block holds the tail with a fresh id")
func splitProducesHeadAndTail() throws {
    var (doc, ids) = makeDoc(["Hello world"])
    let mintedNext = doc.nextBlockID
    try doc.splitBlock(id: ids[0], atOffset: 5)            // "Hello" | " world"

    #expect(doc.blocks.count == 2)
    #expect(doc.blocks[0].id == ids[0])
    #expect(text(of: doc.blocks[0]) == "Hello")
    #expect(text(of: doc.blocks[1]) == " world")
    #expect(doc.blocks[1].id == mintedNext)               // received the minted id
    #expect(doc.nextBlockID == mintedNext + 1)            // counter advanced
}

@Test("splitBlock: trailing-half cut re-anchors to the new block; others stay")
func splitRelocatesTrailingCut() throws {
    var (doc, ids) = makeDoc(["Hello world"])
    doc.cuts = [
        ChapterCut(blockID: ids[0], offsetInBlock: 8),    // in tail (>= 5)
        ChapterCut(blockID: ids[0], offsetInBlock: 2),    // in head (< 5)
        ChapterCut(blockID: ids[0], offsetInBlock: nil),  // boundary cut
    ]
    try doc.splitBlock(id: ids[0], atOffset: 5)
    let newID = doc.blocks[1].id

    #expect(doc.cuts[0].blockID == newID)
    #expect(doc.cuts[0].offsetInBlock == 3)               // 8 - 5
    #expect(doc.cuts[1].blockID == ids[0])
    #expect(doc.cuts[1].offsetInBlock == 2)
    #expect(doc.cuts[2].blockID == ids[0])
    #expect(doc.cuts[2].offsetInBlock == nil)
}

@Test("splitBlock rejects unknown id, non-paragraph, and out-of-range offset, leaving state unmutated")
func splitRejections() {
    var (doc, ids) = makeDoc(["abc"])
    let sbID = doc.mintBlockID()
    doc.blocks.append(Block(id: sbID, content: .sceneBreak))
    let before = doc

    #expect(throws: BlockOperationError.blockNotFound(999)) {
        try doc.splitBlock(id: 999, atOffset: 0)
    }
    #expect(throws: BlockOperationError.notAParagraph(sbID)) {
        try doc.splitBlock(id: sbID, atOffset: 0)
    }
    #expect(throws: BlockOperationError.offsetOutOfRange(ids[0], offset: 99, length: 3)) {
        try doc.splitBlock(id: ids[0], atOffset: 99)
    }
    #expect(doc == before)                                // every rejection threw before mutating
}

@Test("splitBlock: the new tail block inherits the original's presentation overrides")
func splitInheritsOverrides() throws {
    var doc = Document()
    let id = doc.mintBlockID()
    doc.blocks.append(Block(
        id: id,
        content: .paragraph(runs: [Run(text: "centered text")]),
        overrides: [.alignment(.center)]
    ))
    try doc.splitBlock(id: id, atOffset: 8)

    #expect(doc.blocks[0].overrides == [.alignment(.center)])
    #expect(doc.blocks[1].overrides == [.alignment(.center)])   // tail inherits
}

// MARK: - mergeBlocks

@Test("mergeBlocks: second's text appends to first and second is removed")
func mergeJoinsParagraphs() throws {
    var (doc, ids) = makeDoc(["Hello", " world"])
    try doc.mergeBlocks(first: ids[0], second: ids[1])

    #expect(doc.blocks.count == 1)
    #expect(doc.blocks[0].id == ids[0])
    #expect(text(of: doc.blocks[0]) == "Hello world")
    #expect(doc.blocks.contains { $0.id == ids[1] } == false)
}

@Test("mergeBlocks: cuts on second re-anchor into first, shifted by first's length")
func mergeRelocatesCuts() throws {
    var (doc, ids) = makeDoc(["Hello", " world"])         // first length 5
    doc.cuts = [
        ChapterCut(blockID: ids[1], offsetInBlock: 3),    // -> 5 + 3
        ChapterCut(blockID: ids[1], offsetInBlock: nil),  // boundary -> 5
        ChapterCut(blockID: ids[0], offsetInBlock: 2),    // on first -> unchanged
    ]
    try doc.mergeBlocks(first: ids[0], second: ids[1])

    #expect(doc.cuts[0].blockID == ids[0])
    #expect(doc.cuts[0].offsetInBlock == 8)
    #expect(doc.cuts[1].blockID == ids[0])
    #expect(doc.cuts[1].offsetInBlock == 5)
    #expect(doc.cuts[2].blockID == ids[0])
    #expect(doc.cuts[2].offsetInBlock == 2)
}

@Test("mergeBlocks inverts splitBlock at the text level and stays canonical")
func splitThenMergeRestoresText() throws {
    var (doc, ids) = makeDoc(["Half a league"])
    try doc.splitBlock(id: ids[0], atOffset: 4)           // "Half" | " a league"
    let newID = doc.blocks[1].id
    try doc.mergeBlocks(first: ids[0], second: newID)

    #expect(doc.blocks.count == 1)
    #expect(text(of: doc.blocks[0]) == "Half a league")
    if case .paragraph(let runs) = doc.blocks[0].content {
        #expect(runs.count == 1)                          // coalesced back to one run
    } else {
        Issue.record("expected a paragraph")
    }
}

@Test("mergeBlocks rejects unknown id, non-adjacent blocks, and non-paragraph, leaving state unmutated")
func mergeRejections() {
    var (doc, ids) = makeDoc(["a", "b", "c"])
    let before = doc
    #expect(throws: BlockOperationError.blockNotFound(999)) {
        try doc.mergeBlocks(first: 999, second: ids[0])
    }
    #expect(throws: BlockOperationError.blocksNotAdjacent(ids[0], ids[2])) {
        try doc.mergeBlocks(first: ids[0], second: ids[2])
    }
    #expect(doc == before)

    var (doc2, ids2) = makeDoc(["a"])
    let sb = doc2.mintBlockID()
    doc2.blocks.append(Block(id: sb, content: .sceneBreak))
    let before2 = doc2
    #expect(throws: BlockOperationError.notAParagraph(sb)) {
        try doc2.mergeBlocks(first: ids2[0], second: sb)
    }
    #expect(doc2 == before2)
}

// MARK: - deleteBlock

@Test("deleteBlock: removes a middle block and re-anchors its cut to the next block's start")
func deleteMiddleRelocatesToNext() throws {
    var (doc, ids) = makeDoc(["a", "b", "c"])
    doc.cuts = [ChapterCut(blockID: ids[1], offsetInBlock: 0, title: "X")]
    try doc.deleteBlock(id: ids[1])

    #expect(doc.blocks.count == 2)
    #expect(doc.blocks.contains { $0.id == ids[1] } == false)
    #expect(doc.cuts[0].blockID == ids[2])                // former next block
    #expect(doc.cuts[0].offsetInBlock == nil)             // start boundary
    #expect(doc.cuts[0].title == "X")                     // metadata preserved
}

@Test("deleteBlock: deleting the last block re-anchors its cut to the previous block's end")
func deleteLastRelocatesToPrevEnd() throws {
    var (doc, ids) = makeDoc(["abc", "de"])               // prev "abc" length 3
    doc.cuts = [ChapterCut(blockID: ids[1], offsetInBlock: 1)]
    try doc.deleteBlock(id: ids[1])

    #expect(doc.blocks.count == 1)
    #expect(doc.cuts[0].blockID == ids[0])
    #expect(doc.cuts[0].offsetInBlock == 3)               // end of "abc"
}

@Test("deleteBlock: deleting the only block empties the document and drops its cuts")
func deleteOnlyDropsCut() throws {
    var (doc, ids) = makeDoc(["solo"])
    doc.cuts = [ChapterCut(blockID: ids[0], offsetInBlock: nil)]
    try doc.deleteBlock(id: ids[0])

    #expect(doc.blocks.isEmpty)
    #expect(doc.cuts.isEmpty)
}

@Test("deleteBlock rejects unknown id, leaving state unmutated")
func deleteRejectsUnknown() {
    var (doc, _) = makeDoc(["a"])
    let before = doc
    #expect(throws: BlockOperationError.blockNotFound(42)) {
        try doc.deleteBlock(id: 42)
    }
    #expect(doc == before)
}

@Test("deleteBlock: last-block deletion anchors a cut to a scene-break end (length 0)")
func deleteLastAnchorsToSceneBreakEnd() throws {
    var doc = Document()
    let sb = doc.mintBlockID()
    doc.blocks.append(Block(id: sb, content: .sceneBreak))
    let p = doc.mintBlockID()
    doc.blocks.append(Block(id: p, content: .paragraph(runs: [Run(text: "tail")])))
    doc.cuts = [ChapterCut(blockID: p, offsetInBlock: 2)]

    try doc.deleteBlock(id: p)                            // delete last; survivor is a scene break

    #expect(doc.blocks.count == 1)
    #expect(doc.cuts[0].blockID == sb)
    #expect(doc.cuts[0].offsetInBlock == 0)               // contentTextLength(.sceneBreak) == 0
}

@Test("deleteBlock: last-block deletion anchors a cut to a set-piece end (summed line length)")
func deleteLastAnchorsToSetPieceEnd() throws {
    var doc = Document()
    let v = doc.mintBlockID()
    doc.blocks.append(Block(id: v, content: .setPiece(kind: .verse, lines: [[Run(text: "ab")], [Run(text: "cde")]]))) // 2 + 3
    let p = doc.mintBlockID()
    doc.blocks.append(Block(id: p, content: .paragraph(runs: [Run(text: "x")])))
    doc.cuts = [ChapterCut(blockID: p, offsetInBlock: 0)]

    try doc.deleteBlock(id: p)                            // delete last; survivor is a set-piece

    #expect(doc.cuts[0].blockID == v)
    #expect(doc.cuts[0].offsetInBlock == 5)               // summed line length
}

// MARK: - adjustCutOffset

@Test("adjustCutOffset: insertion shifts only cuts strictly after the pivot")
func adjustInsertion() {
    var (doc, ids) = makeDoc(["abcdef"])
    let other = doc.mintBlockID()
    doc.blocks.append(Block(id: other, content: .paragraph(runs: [Run(text: "zzz")])))
    doc.cuts = [
        ChapterCut(blockID: ids[0], offsetInBlock: 4),    // after pivot 2 -> +3
        ChapterCut(blockID: ids[0], offsetInBlock: 2),    // at pivot -> unchanged
        ChapterCut(blockID: ids[0], offsetInBlock: 1),    // before pivot -> unchanged
        ChapterCut(blockID: ids[0], offsetInBlock: nil),  // boundary -> unchanged
        ChapterCut(blockID: other,  offsetInBlock: 0),    // other block -> unchanged
    ]
    doc.adjustCutOffset(blockID: ids[0], at: 2, delta: 3)

    #expect(doc.cuts[0].offsetInBlock == 7)
    #expect(doc.cuts[1].offsetInBlock == 2)
    #expect(doc.cuts[2].offsetInBlock == 1)
    #expect(doc.cuts[3].offsetInBlock == nil)
    #expect(doc.cuts[4].offsetInBlock == 0)
}

@Test("adjustCutOffset: deletion shifts cuts after the range and clamps cuts inside it")
func adjustDeletion() {
    var (doc, ids) = makeDoc(["abcdefghij"])
    doc.cuts = [
        ChapterCut(blockID: ids[0], offsetInBlock: 7),    // >= end(5) -> 7 - 3
        ChapterCut(blockID: ids[0], offsetInBlock: 3),    // inside [2,5) -> clamp 2
        ChapterCut(blockID: ids[0], offsetInBlock: 5),    // == end -> 5 - 3
        ChapterCut(blockID: ids[0], offsetInBlock: 2),    // == pivot -> unchanged
        ChapterCut(blockID: ids[0], offsetInBlock: 1),    // before pivot -> unchanged
    ]
    doc.adjustCutOffset(blockID: ids[0], at: 2, delta: -3) // remove [2,5)

    #expect(doc.cuts[0].offsetInBlock == 4)
    #expect(doc.cuts[1].offsetInBlock == 2)
    #expect(doc.cuts[2].offsetInBlock == 2)
    #expect(doc.cuts[3].offsetInBlock == 2)
    #expect(doc.cuts[4].offsetInBlock == 1)
}

@Test("adjustCutOffset: delta 0 is a no-op")
func adjustZeroNoop() {
    var (doc, ids) = makeDoc(["abc"])
    doc.cuts = [ChapterCut(blockID: ids[0], offsetInBlock: 2)]
    doc.adjustCutOffset(blockID: ids[0], at: 0, delta: 0)
    #expect(doc.cuts[0].offsetInBlock == 2)
}
