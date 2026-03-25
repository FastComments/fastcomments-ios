import XCTest
import SwiftUI
@testable import FastCommentsUI

final class ThemeTests: XCTestCase {

    func testDefaultResolve() {
        let theme = FastCommentsTheme()
        // With no colors set, resolve should return a default (accentColor or blue)
        let color = theme.resolveActionButtonColor()
        XCTAssertNotNil(color)
    }

    func testPrimaryColorFallback() {
        var theme = FastCommentsTheme()
        theme.primaryColor = .red

        // Action button should fall back to primary when not explicitly set
        let color = theme.resolveActionButtonColor()
        XCTAssertEqual(color, .red)
    }

    func testSpecificColorOverride() {
        var theme = FastCommentsTheme()
        theme.primaryColor = .red
        theme.actionButtonColor = .green

        // Specific color should take precedence over primary
        let color = theme.resolveActionButtonColor()
        XCTAssertEqual(color, .green)
    }

    func testAllPrimary() {
        let theme = FastCommentsTheme.allPrimary(.purple)

        XCTAssertEqual(theme.resolvePrimaryColor(), .purple)
        XCTAssertEqual(theme.resolveActionButtonColor(), .purple)
        XCTAssertEqual(theme.resolveReplyButtonColor(), .purple)
        XCTAssertEqual(theme.resolveToggleRepliesButtonColor(), .purple)
        XCTAssertEqual(theme.resolveLinkColor(), .purple)
    }

    func testResolveWithNoColorReturnsNonNil() {
        let theme = FastCommentsTheme()

        // All resolve methods should return a valid color even with no configuration
        XCTAssertNotNil(theme.resolveReplyButtonColor())
        XCTAssertNotNil(theme.resolveToggleRepliesButtonColor())
        XCTAssertNotNil(theme.resolveLoadMoreButtonTextColor())
        XCTAssertNotNil(theme.resolveLinkColor())
        XCTAssertNotNil(theme.resolveVoteCountColor())
        XCTAssertNotNil(theme.resolveVoteCountZeroColor())
        XCTAssertNotNil(theme.resolveOnlineIndicatorColor())
    }
}
