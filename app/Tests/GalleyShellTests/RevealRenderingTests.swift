//
//  RevealRenderingTests.swift
//  GalleyShellTests
//
//  Behavioral tests for the pure reveal view-model layer: token → item mapping
//  and chapter-anchor listing. AppKit-free; assert on the produced values.
//

import Testing
import GalleyCore
@testable import GalleyShell

@Suite("reveal rendering")
struct RevealRenderingTests {

    @Test func mapsTextAndChipTokensWithStableIndices() {
        let tokens: [RevealToken] = [
            .text("She left "),
            .code(label: "i", id: .italicOpen(0, 0)),
            .text("now"),
            .code(label: "/i", id: .italicClose(0, 0)),
        ]
        let items = revealItems(from: tokens)
        #expect(items == [
            RevealItem(id: 0, kind: .text("She left ")),
            RevealItem(id: 1, kind: .chip(label: "i", code: .italicOpen(0, 0))),
            RevealItem(id: 2, kind: .text("now")),
            RevealItem(id: 3, kind: .chip(label: "/i", code: .italicClose(0, 0))),
        ])
    }

    @Test func chapterAnchorsOnePerBlockMarkingTheCut() {
        let doc = Document(blocks: [
            Block(id: 0, content: .paragraph(runs: [Run(text: "Opening line of the chapter.")])),
            Block(id: 1, content: .sceneBreak),
            Block(id: 2, content: .setPiece(kind: .verse, lines: [[Run(text: "verse")]])),
        ], cuts: [ChapterCut(blockID: 2, offsetInBlock: nil, title: "Two")], nextBlockID: 3)

        let anchors = chapterAnchors(of: doc)
        #expect(anchors == [
            ChapterAnchor(id: 0, label: "Opening line of the chapter.", hasCut: false, title: nil),
            ChapterAnchor(id: 1, label: "* * *", hasCut: false, title: nil),
            ChapterAnchor(id: 2, label: "[Verse]", hasCut: true, title: "Two"),
        ])
    }

    @Test func longParagraphPreviewIsTruncated() {
        let long = String(repeating: "x", count: 60)
        let doc = Document(blocks: [Block(id: 0, content: .paragraph(runs: [Run(text: long)]))], nextBlockID: 1)
        let anchor = chapterAnchors(of: doc)[0]
        #expect(anchor.label == String(repeating: "x", count: 40) + "…")
    }
}
