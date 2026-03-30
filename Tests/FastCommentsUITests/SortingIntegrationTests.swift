import XCTest
@testable import FastCommentsUI
import FastCommentsSwift

@MainActor
final class SortingIntegrationTests: IntegrationTestBase {

    func testNewestFirst() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        let a = try await sdk.postComment(text: "Comment A")
        try await Task.sleep(nanoseconds: 100_000_000) // small gap for distinct timestamps
        _ = try await sdk.postComment(text: "Comment B")
        try await Task.sleep(nanoseconds: 100_000_000)
        let c = try await sdk.postComment(text: "Comment C")

        // Reload with newest first
        let sdk2 = FastCommentsSDK(config: sdk.config)
        sdk2.defaultSortDirection = .nf
        try await sdk2.load()

        let visibleComments = sdk2.commentsTree.visibleNodes.compactMap { $0 as? RenderableComment }
        XCTAssertGreaterThanOrEqual(visibleComments.count, 3)

        // C should appear before A (newest first)
        let indexC = visibleComments.firstIndex { $0.id == c.id }
        let indexA = visibleComments.firstIndex { $0.id == a.id }
        XCTAssertNotNil(indexC)
        XCTAssertNotNil(indexA)
        if let ic = indexC, let ia = indexA {
            XCTAssertLessThan(ic, ia, "Newest comment (C) should appear before oldest (A)")
        }
    }

    func testOldestFirst() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        let a = try await sdk.postComment(text: "Comment A")
        try await Task.sleep(nanoseconds: 100_000_000)
        _ = try await sdk.postComment(text: "Comment B")
        try await Task.sleep(nanoseconds: 100_000_000)
        let c = try await sdk.postComment(text: "Comment C")

        // Reload with oldest first
        let sdk2 = FastCommentsSDK(config: sdk.config)
        sdk2.defaultSortDirection = .of
        try await sdk2.load()

        let visibleComments = sdk2.commentsTree.visibleNodes.compactMap { $0 as? RenderableComment }
        XCTAssertGreaterThanOrEqual(visibleComments.count, 3)

        let indexA = visibleComments.firstIndex { $0.id == a.id }
        let indexC = visibleComments.firstIndex { $0.id == c.id }
        XCTAssertNotNil(indexA)
        XCTAssertNotNil(indexC)
        if let ia = indexA, let ic = indexC {
            XCTAssertLessThan(ia, ic, "Oldest comment (A) should appear before newest (C)")
        }
    }

    func testMostRelevant() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        let a = try await sdk.postComment(text: "Comment A - popular")
        let b = try await sdk.postComment(text: "Comment B - unpopular")

        // Upvote A
        _ = try await sdk.voteComment(commentId: a.id, isUpvote: true)

        // Reload with most relevant sort
        let sdk2 = FastCommentsSDK(config: sdk.config)
        sdk2.defaultSortDirection = .mr
        try await sdk2.load()

        let visibleComments = sdk2.commentsTree.visibleNodes.compactMap { $0 as? RenderableComment }
        XCTAssertGreaterThanOrEqual(visibleComments.count, 2)

        let indexA = visibleComments.firstIndex { $0.id == a.id }
        let indexB = visibleComments.firstIndex { $0.id == b.id }
        XCTAssertNotNil(indexA)
        XCTAssertNotNil(indexB)
        if let ia = indexA, let ib = indexB {
            XCTAssertLessThan(ia, ib, "Higher-voted comment (A) should appear first")
        }
    }

    func testSortDirectionApplied() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        _ = try await sdk.postComment(text: "Early")
        try await Task.sleep(nanoseconds: 100_000_000)
        _ = try await sdk.postComment(text: "Late")

        // Load newest first
        let sdkNF = FastCommentsSDK(config: sdk.config)
        sdkNF.defaultSortDirection = .nf
        try await sdkNF.load()
        let nfComments = sdkNF.commentsTree.visibleNodes.compactMap { $0 as? RenderableComment }

        // Load oldest first
        let sdkOF = FastCommentsSDK(config: sdk.config)
        sdkOF.defaultSortDirection = .of
        try await sdkOF.load()
        let ofComments = sdkOF.commentsTree.visibleNodes.compactMap { $0 as? RenderableComment }

        XCTAssertGreaterThanOrEqual(nfComments.count, 2)
        XCTAssertGreaterThanOrEqual(ofComments.count, 2)

        // First comment should be different between the two sorts
        if nfComments.count >= 2 && ofComments.count >= 2 {
            XCTAssertNotEqual(nfComments.first?.id, ofComments.first?.id,
                              "Different sort directions should produce different orderings")
        }
    }

    func testPinnedCommentStaysFirst() async throws {
        let sdk = makeSDK()
        try await sdk.load()

        let a = try await sdk.postComment(text: "Will be pinned")
        try await Task.sleep(nanoseconds: 100_000_000)
        _ = try await sdk.postComment(text: "Not pinned")

        // Pin via admin API
        _ = try await DefaultAPI.updateComment(
            tenantId: tenantId,
            id: a.id,
            updatableCommentParams: UpdatableCommentParams(isPinned: true),
            apiConfiguration: adminApiConfig
        )

        // Reload and verify pinned comment is first
        let sdk2 = FastCommentsSDK(config: sdk.config)
        sdk2.defaultSortDirection = .nf
        try await sdk2.load()

        let visibleComments = sdk2.commentsTree.visibleNodes.compactMap { $0 as? RenderableComment }
        XCTAssertGreaterThanOrEqual(visibleComments.count, 2)
        XCTAssertEqual(visibleComments.first?.id, a.id, "Pinned comment should appear first")
    }
}
