import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Renders HTML content as an AttributedString.
/// Falls back to plain text if HTML parsing fails.
public struct HTMLContentView: View {
    let html: String
    var linkHandler: ((URL) -> Void)?

    @Environment(\.fastCommentsTheme) private var theme

    public init(html: String, linkHandler: ((URL) -> Void)? = nil) {
        self.html = html
        self.linkHandler = linkHandler
    }

    public var body: some View {
        if let attributedString = parseHTML(html) {
            Text(attributedString)
                .environment(\.openURL, OpenURLAction { url in
                    if let linkHandler = linkHandler {
                        linkHandler(url)
                        return .handled
                    }
                    return .systemAction
                })
        } else {
            // Fallback: strip HTML tags
            Text(html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
        }
    }

    private func parseHTML(_ html: String) -> AttributedString? {
        // Wrap in basic HTML structure for proper parsing
        let fullHTML = """
        <html><head><style>
        body { font-family: -apple-system; font-size: 15px; }
        a { color: \(theme.resolveLinkColor().description); }
        code { font-family: monospace; background-color: #f0f0f0; padding: 2px 4px; border-radius: 3px; }
        pre { font-family: monospace; background-color: #f0f0f0; padding: 8px; border-radius: 6px; }
        </style></head><body>\(html)</body></html>
        """

        guard let data = fullHTML.data(using: .utf8) else { return nil }

        do {
            let nsAttrString = try NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
            )
            #if os(iOS)
            return try AttributedString(nsAttrString, including: \.uiKit)
            #else
            return try AttributedString(nsAttrString, including: \.appKit)
            #endif
        } catch {
            return nil
        }
    }
}
