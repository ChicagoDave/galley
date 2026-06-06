//
//  ChapterEditingTests.swift
//  GalleyCoreTests
//
//  Behavioral tests for the chapter-overlay edits (§6, ADR-0005), derived from
//  the Behavior Statement: each asserts on the resulting `cuts` overlay.
//

import Testing
@testable import GalleyCore

@Suite("chapter-overlay edits")
struct ChapterEditingTests {

    private func threeBlockDoc() -> Document {
        Document(blocks: [
            Block(id: 0, content: .paragraph(runs: [Run(text: "one")])),
            Block(id: 1, content: .paragraph(runs: [Run(text: "two")])),
            Block(id: 2, content: .paragraph(runs: [Run(text: "three")])),
        ], nextBlockID: 3)
    }

    @Test func placeAddsABoundaryCut() {
        var doc = threeBlockDoc()
        doc.placeChapterCut(atBlock: 1)
        #expect(doc.cuts == [ChapterCut(blockID: 1, offsetInBlock: nil)])
    }

    @Test func placeIsIdempotentAtTheSameBlock() {
        var doc = threeBlockDoc()
        doc.placeChapterCut(atBlock: 1)
        doc.placeChapterCut(atBlock: 1)
        #expect(doc.cuts == [ChapterCut(blockID: 1, offsetInBlock: nil)])
    }

    @Test func placeOnAnUnknownBlockIsANoOp() {
        var doc = threeBlockDoc()
        doc.placeChapterCut(atBlock: 99)
        #expect(doc.cuts.isEmpty)
    }

    @Test func removeDropsTheBoundaryCut() {
        var doc = threeBlockDoc()
        doc.placeChapterCut(atBlock: 1)
        doc.removeChapterCut(atBlock: 1)
        #expect(doc.cuts.isEmpty)
    }

    @Test func removeLeavesAMidBlockCutOnTheSameBlock() {
        var doc = threeBlockDoc()
        doc.cuts = [ChapterCut(blockID: 1, offsetInBlock: 2, title: "Mid")]
        doc.removeChapterCut(atBlock: 1)
        #expect(doc.cuts == [ChapterCut(blockID: 1, offsetInBlock: 2, title: "Mid")])
    }

    @Test func setTitleUpdatesTheCut() {
        var doc = threeBlockDoc()
        doc.placeChapterCut(atBlock: 1)
        doc.setChapterCutTitle(atBlock: 1, to: "Chapter Two")
        #expect(doc.cuts == [ChapterCut(blockID: 1, offsetInBlock: nil, title: "Chapter Two")])
    }

    @Test func setEmptyTitleClearsIt() {
        var doc = threeBlockDoc()
        doc.cuts = [ChapterCut(blockID: 1, offsetInBlock: nil, title: "old")]
        doc.setChapterCutTitle(atBlock: 1, to: "")
        #expect(doc.cuts == [ChapterCut(blockID: 1, offsetInBlock: nil, title: nil)])
    }

    @Test func moveReanchorsPreservingTitle() {
        var doc = threeBlockDoc()
        doc.cuts = [ChapterCut(blockID: 1, offsetInBlock: nil, title: "Two")]
        doc.moveChapterCut(fromBlock: 1, toBlock: 2)
        #expect(doc.cuts == [ChapterCut(blockID: 2, offsetInBlock: nil, title: "Two")])
    }

    @Test func moveToABlockThatAlreadyHasACutIsANoOp() {
        var doc = threeBlockDoc()
        doc.placeChapterCut(atBlock: 1)
        doc.placeChapterCut(atBlock: 2)
        doc.moveChapterCut(fromBlock: 1, toBlock: 2)
        // The source cut stays put; the target cut is untouched (no duplicate, no move).
        #expect(doc.cuts == [
            ChapterCut(blockID: 1, offsetInBlock: nil),
            ChapterCut(blockID: 2, offsetInBlock: nil),
        ])
    }

    @Test func moveToUnknownBlockIsANoOp() {
        var doc = threeBlockDoc()
        doc.placeChapterCut(atBlock: 1)
        doc.moveChapterCut(fromBlock: 1, toBlock: 99)
        #expect(doc.cuts == [ChapterCut(blockID: 1, offsetInBlock: nil)])
    }
}
