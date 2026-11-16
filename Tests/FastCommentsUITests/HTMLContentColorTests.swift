import XCTest
import SwiftUI
@testable import FastCommentsUI

/// Comment text has to follow the appearance, or it is black on black in dark mode.
@MainActor
final class HTMLContentColorTests: XCTestCase {

    private func parse(_ html: String) throws -> NSAttributedString {
        let parsed = try XCTUnwrap(HTMLContentView.parseHTMLToAttributedString(html, linkColor: .blue))
        return try NSAttributedString(parsed, including: \.uiKit)
    }

    private func textColor(of text: String, in attributed: NSAttributedString) -> Any? {
        let range = (attributed.string as NSString).range(of: text)
        return attributed.attribute(.foregroundColor, at: range.location, effectiveRange: nil)
    }

    func testPlainTextHasNoFixedColor() throws {
        let attributed = try parse("<p>Lunch vote <b>today</b></p>")
        XCTAssertNil(textColor(of: "Lunch vote", in: attributed))
        XCTAssertNil(textColor(of: "today", in: attributed))
    }

    func testCodeKeepsItsDarkTextOnItsLightBackground() throws {
        let attributed = try parse("<p>Run <code>make</code></p>")
        XCTAssertNil(textColor(of: "Run", in: attributed))
        XCTAssertNotNil(textColor(of: "make", in: attributed))
    }

    func testExplicitColorsAreKept() throws {
        let attributed = try parse(#"<p><span style="color: red">Warning</span></p>"#)
        XCTAssertNotNil(textColor(of: "Warning", in: attributed))
    }
}
