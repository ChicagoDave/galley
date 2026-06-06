//
//  InputTests.swift
//  UntitledCoreTests
//
//  Behavioral tests for `applyInput` (§8), derived from its Behavior Statement.
//  Each asserts on the resulting Document state — block content, structure, cut
//  anchors — never on a return flag. Every DOES line and the unknown-block
//  REJECTS line is covered.
//

import Testing
@testable import UntitledCore

@Suite("applyInput")
struct InputTests {

    private func paragraphDoc(_ text: String, italic: Bool = false, id: BlockID = 0) -> Document {
        Document(blocks: [Block(id: id, content: .paragraph(runs: [Run(text: text, italic: italic)]))], nextBlockID: id + 1)
    }

    private func runs(_ doc: Document, _ id: BlockID) -> [Run]? {
        guard case .paragraph(let r)? = doc.blocks.first(where: { $0.id == id })?.content else { return nil }
        return r
    }

    // MARK: insertText

    @Test func insertTextInsertsAtOffset() {
        let doc = applyInput(.insertText("X", blockID: 0, offset: 3), to: paragraphDoc("abcdef"))
        #expect(runs(doc, 0) == [Run(text: "abcXdef")])
    }

    @Test func insertTextInheritsItalicOfPrecedingRun() {
        // "plain " + "italic" ; insert at offset 12 (end of italic run) inherits italic.
        let doc = Document(blocks: [Block(id: 0, content: .paragraph(runs: [
            Run(text: "plain "), Run(text: "italic", italic: true),
        ]))], nextBlockID: 1)
        let out = applyInput(.insertText("!", blockID: 0, offset: 12), to: doc)
        #expect(runs(out, 0) == [Run(text: "plain "), Run(text: "italic!", italic: true)])
    }

    @Test func insertTextCurlsAClosingQuote() {
        let doc = applyInput(.insertText("\"", blockID: 0, offset: 2), to: paragraphDoc("hi"))
        #expect(runs(doc, 0) == [Run(text: "hi\u{201D}")])
    }

    @Test func insertHyphenAfterHyphenBecomesEmDash() {
        let doc = applyInput(.insertText("-", blockID: 0, offset: 3), to: paragraphDoc("no-"))
        #expect(runs(doc, 0) == [Run(text: "no\u{2014}")])
    }

    @Test func insertThirdDotBecomesEllipsisCharacter() {
        let doc = applyInput(.insertText(".", blockID: 0, offset: 2), to: paragraphDoc(".."))
        #expect(runs(doc, 0) == [Run(text: "\u{2026}")])   // one … glyph, not three periods
        #expect(runs(doc, 0)?.first?.text.count == 1)
    }

    @Test func insertTextShiftsACutAfterTheCaret() {
        var doc = paragraphDoc("abcdef")
        doc.cuts = [ChapterCut(blockID: 0, offsetInBlock: 4, title: "C")]
        let out = applyInput(.insertText("XY", blockID: 0, offset: 1), to: doc)
        #expect(out.cuts == [ChapterCut(blockID: 0, offsetInBlock: 6, title: "C")])
    }

    // MARK: splitParagraph

    @Test func splitParagraphProducesTwoBlocks() {
        let out = applyInput(.splitParagraph(blockID: 0, offset: 3), to: paragraphDoc("abcdef"))
        #expect(out.blocks.count == 2)
        #expect(runs(out, 0) == [Run(text: "abc")])
        #expect(out.blocks[1].content == .paragraph(runs: [Run(text: "def")]))
    }

    // MARK: deleteBackward

    @Test func deleteBackwardRemovesPrecedingCharacter() {
        let out = applyInput(.deleteBackward(blockID: 0, offset: 3), to: paragraphDoc("abcdef"))
        #expect(runs(out, 0) == [Run(text: "abdef")])
    }

    @Test func deleteBackwardAtOffsetZeroMergesWithPreviousParagraph() {
        let doc = Document(blocks: [
            Block(id: 0, content: .paragraph(runs: [Run(text: "Hello")])),
            Block(id: 1, content: .paragraph(runs: [Run(text: "world")])),
        ], nextBlockID: 2)
        let out = applyInput(.deleteBackward(blockID: 1, offset: 0), to: doc)
        #expect(out.blocks.count == 1)
        #expect(runs(out, 0) == [Run(text: "Helloworld")])
    }

    @Test func deleteBackwardAtOffsetZeroRemovesPrecedingSceneBreak() {
        let doc = Document(blocks: [
            Block(id: 0, content: .sceneBreak),
            Block(id: 1, content: .paragraph(runs: [Run(text: "after")])),
        ], nextBlockID: 2)
        let out = applyInput(.deleteBackward(blockID: 1, offset: 0), to: doc)
        #expect(out.blocks.map(\.id) == [1])
        #expect(runs(out, 1) == [Run(text: "after")])
    }

    @Test func deleteBackwardAtStartOfFirstBlockIsNoOp() {
        let doc = paragraphDoc("abc")
        #expect(applyInput(.deleteBackward(blockID: 0, offset: 0), to: doc) == doc)
    }

    // MARK: toggleItalic

    @Test func toggleItalicItalicisesAPlainRange() {
        let out = applyInput(.toggleItalic(blockID: 0, start: 2, end: 5), to: paragraphDoc("abcdef"))
        #expect(runs(out, 0) == [Run(text: "ab"), Run(text: "cde", italic: true), Run(text: "f")])
    }

    @Test func toggleItalicClearsAWhollyItalicRange() {
        let doc = paragraphDoc("abcdef", italic: true)
        let out = applyInput(.toggleItalic(blockID: 0, start: 0, end: 6), to: doc)
        #expect(runs(out, 0) == [Run(text: "abcdef")])
    }

    // MARK: makeSceneBreak

    @Test func makeSceneBreakReplacesBlockContent() {
        let out = applyInput(.makeSceneBreak(blockID: 0), to: paragraphDoc(""))
        #expect(out.blocks[0].content == .sceneBreak)
    }

    // MARK: toggleSetPiece

    @Test func toggleSetPieceWrapsParagraphAsVerseLine() {
        let out = applyInput(.toggleSetPiece(blockID: 0, kind: .verse), to: paragraphDoc("a line"))
        #expect(out.blocks[0].content == .setPiece(kind: .verse, lines: [[Run(text: "a line")]]))
    }

    @Test func toggleSetPieceFlattensVerseBackToParagraph() {
        let doc = Document(blocks: [Block(id: 0, content: .setPiece(kind: .verse, lines: [
            [Run(text: "one")], [Run(text: "two")],
        ]))], nextBlockID: 1)
        let out = applyInput(.toggleSetPiece(blockID: 0, kind: .verse), to: doc)
        #expect(out.blocks[0].content == .paragraph(runs: [Run(text: "onetwo")]))
    }

    // MARK: breakSetPieceLine

    @Test func breakSetPieceLineSplitsOneLineIntoTwo() {
        let doc = Document(blocks: [Block(id: 0, content: .setPiece(kind: .verse, lines: [
            [Run(text: "halfhalf")],
        ]))], nextBlockID: 1)
        let out = applyInput(.breakSetPieceLine(blockID: 0, lineIndex: 0, offset: 4), to: doc)
        #expect(out.blocks[0].content == .setPiece(kind: .verse, lines: [
            [Run(text: "half")], [Run(text: "half")],
        ]))
    }

    // MARK: REJECTS

    @Test func unknownBlockLeavesDocumentUnchanged() {
        let doc = paragraphDoc("abc")
        #expect(applyInput(.insertText("X", blockID: 99, offset: 0), to: doc) == doc)
        #expect(applyInput(.toggleItalic(blockID: 99, start: 0, end: 1), to: doc) == doc)
    }
}
