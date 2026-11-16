import XCTest
import UIKit
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

    // MARK: - Polls

    private func isDark(_ color: Color) -> Bool {
        var white: CGFloat = 0
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).getWhite(&white, alpha: nil)
        return white < 0.5
    }

    func testPollAccentTextStaysReadableOnACustomAccent() {
        var theme = FastCommentsTheme()
        theme.pollAccentColor = .yellow
        XCTAssertTrue(isDark(theme.resolvePollAccentTextColor()), "Dark text on a light accent")

        theme.pollAccentColor = Color(red: 0.1, green: 0.1, blue: 0.5)
        XCTAssertFalse(isDark(theme.resolvePollAccentTextColor()), "Light text on a dark accent")

        theme.primaryColor = .yellow
        theme.pollAccentColor = nil
        XCTAssertTrue(isDark(theme.resolvePollAccentTextColor()), "The accent falls back to the primary color")

        theme.pollAccentTextColor = .white
        XCTAssertFalse(isDark(theme.resolvePollAccentTextColor()), "An explicit color wins")
    }
}
