//
//  UntitledCoreTests.swift
//  UntitledCoreTests
//
//  Purpose: Phase-1 skeleton test — confirms the package builds and the test
//  target can import UntitledCore. Real behavioral suites (block-lifecycle,
//  round-trip, revealProjection) arrive in Phases 3-4.
//  Owner context: UntitledCoreTests.
//

import Testing
@testable import UntitledCore

@Test("module skeleton is wired and importable")
func moduleSkeletonIsWired() {
    #expect(UntitledCore.phase == "headless-core")
}
