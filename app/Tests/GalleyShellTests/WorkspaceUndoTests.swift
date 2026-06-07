//
//  WorkspaceUndoTests.swift
//  GalleyShellTests
//
//  Behavioral tests for `WorkspaceDocument` model-snapshot undo/redo (LT3), derived
//  from its Behavior Statement. Each asserts on the restored `document` state — not
//  on `canUndo` alone — covering the checkpoint-before-edit, the redo-after-undo,
//  the redo-cleared-by-new-edit fork, and the empty-stack no-ops. Tests run on the
//  main actor because `WorkspaceDocument` is `@MainActor`.
//

import Testing
import GalleyCore
@testable import GalleyShell

@MainActor
@Suite("WorkspaceDocument undo/redo")
struct WorkspaceUndoTests {

    /// A buffer seeded with one paragraph carrying `text`.
    private func buffer(text: String) -> WorkspaceDocument {
        WorkspaceDocument(document: Document(
            blocks: [Block(id: 0, content: .paragraph(runs: [Run(text: text)]))],
            nextBlockID: 1
        ))
    }

    @Test func undoRestoresThePreEditDocument() {
        let doc = buffer(text: "Hello")
        doc.apply(.insertText("!", blockID: 0, offset: 5))
        #expect(doc.document.blocks[0].content == .paragraph(runs: [Run(text: "Hello!")]))

        doc.undo()
        #expect(doc.document.blocks[0].content == .paragraph(runs: [Run(text: "Hello")]))
    }

    @Test func redoReappliesTheUndoneEdit() {
        let doc = buffer(text: "Hello")
        doc.apply(.insertText("!", blockID: 0, offset: 5))
        doc.undo()
        doc.redo()
        #expect(doc.document.blocks[0].content == .paragraph(runs: [Run(text: "Hello!")]))
    }

    @Test func aNewEditAfterUndoClearsTheRedoTimeline() {
        let doc = buffer(text: "Hi")
        doc.apply(.insertText("!", blockID: 0, offset: 2))   // "Hi!"
        doc.undo()                                           // back to "Hi"
        doc.apply(.insertText("?", blockID: 0, offset: 2))   // "Hi?" — forks
        #expect(!doc.canRedo)                                // the "!" future is gone
        doc.redo()                                           // no-op
        #expect(doc.document.blocks[0].content == .paragraph(runs: [Run(text: "Hi?")]))
    }

    @Test func undoSpansSeveralEditsOneStepAtATime() {
        let doc = buffer(text: "")
        doc.apply(.insertText("a", blockID: 0, offset: 0))
        doc.apply(.insertText("b", blockID: 0, offset: 1))
        doc.undo()
        #expect(doc.document.blocks[0].content == .paragraph(runs: [Run(text: "a")]))
        doc.undo()
        #expect(doc.document.blocks[0].content == .paragraph(runs: [Run(text: "")]))
    }

    @Test func undoRestoresACutTitleEdit() {
        let doc = buffer(text: "Body")
        doc.placeCut(atBlock: 0)
        doc.setCutTitle(atBlock: 0, to: "Chapter #a")
        #expect(doc.document.cuts.first?.title == "Chapter #a")

        doc.undo()                                           // undo the title set
        #expect(doc.document.cuts.first?.title == nil)
        doc.undo()                                           // undo the cut placement
        #expect(doc.document.cuts.isEmpty)
    }

    @Test func undoOnEmptyHistoryIsANoOp() {
        let doc = buffer(text: "Steady")
        #expect(!doc.canUndo)
        doc.undo()                                           // must not crash
        #expect(doc.document.blocks[0].content == .paragraph(runs: [Run(text: "Steady")]))
    }
}
