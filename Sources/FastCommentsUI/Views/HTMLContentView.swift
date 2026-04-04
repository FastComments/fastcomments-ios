import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Renders HTML content as styled text with support for inline images.
public struct HTMLContentView: View {
    let html: String
    var linkHandler: ((URL) -> Void)?

    @Environment(\.fastCommentsTheme) private var theme
    @State private var parsedContent: ParsedContent?

    public init(html: String, linkHandler: ((URL) -> Void)? = nil) {
        self.html = html
        self.linkHandler = linkHandler
    }

    public var body: some View {
        Group {
            if let content = parsedContent {
                renderContent(content)
            } else {
                // Fallback while loading — strip tags for plain text
                Text(html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
                    .font(.subheadline)
            }
        }
        .task(id: html) {
            parsedContent = await Self.parse(html: html, linkColor: theme.resolveLinkColor())
        }
    }

    // MARK: - Parsed Content Model

    private enum ContentPart {
        case text(AttributedString)
        case image(URL)
    }

    private struct ParsedContent {
        let parts: [ContentPart]
    }

    // MARK: - Rendering

    @ViewBuilder
    private func renderContent(_ content: ParsedContent) -> some View {
        if content.parts.count == 1, case .text(let attrStr) = content.parts.first {
            styledText(attrStr)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(content.parts.enumerated()), id: \.offset) { _, part in
                    switch part {
                    case .text(let attrStr):
                        styledText(attrStr)
                    case .image(let url):
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius.inner))
                            case .failure:
                                EmptyView()
                            case .empty:
                                ProgressView()
                                    .frame(height: 100)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                }
            }
        }
    }

    private func styledText(_ attributedString: AttributedString) -> some View {
        Text(attributedString)
            .environment(\.openURL, OpenURLAction { url in
                if let linkHandler = linkHandler {
                    linkHandler(url)
                    return .handled
                }
                return .systemAction
            })
    }

    // MARK: - Cache

    private static let parsedCache: NSCache<NSString, CachedParsedContent> = {
        let cache = NSCache<NSString, CachedParsedContent>()
        cache.countLimit = 500
        return cache
    }()

    private final class CachedParsedContent {
        let value: ParsedContent
        init(_ value: ParsedContent) { self.value = value }
    }

    /// Produce a deterministic cache key from a Color by resolving its RGBA components.
    /// Color.description is not stable across iOS versions or appearance changes.
    private static func stableCacheKey(for color: Color) -> String {
        #if canImport(UIKit)
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%.4f,%.4f,%.4f,%.4f", r, g, b, a)
        #elseif canImport(AppKit)
        let nsColor = NSColor(color)
        let converted = nsColor.usingColorSpace(.sRGB) ?? nsColor
        return String(format: "%.4f,%.4f,%.4f,%.4f",
                      converted.redComponent, converted.greenComponent,
                      converted.blueComponent, converted.alphaComponent)
        #endif
    }

    // MARK: - Async Parsing

    private static func parse(html: String, linkColor: Color) async -> ParsedContent {
        let cacheKey = "\(html)|\(Self.stableCacheKey(for: linkColor))" as NSString
        if let cached = parsedCache.object(forKey: cacheKey) {
            return cached.value
        }
        let imgParts = splitHTMLIntoParts(html)

        var parts: [ContentPart] = []
        for imgPart in imgParts {
            switch imgPart {
            case .rawText(let text):
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if let attrStr = parseHTMLToAttributedString(text, linkColor: linkColor) {
                        parts.append(.text(attrStr))
                    }
                }
            case .image(let url):
                parts.append(.image(url))
            }
        }

        if parts.isEmpty {
            // Fallback to plain text
            let plain = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            parts.append(.text(AttributedString(plain)))
        }

        let result = ParsedContent(parts: parts)
        parsedCache.setObject(CachedParsedContent(result), forKey: cacheKey)
        return result
    }

    // MARK: - HTML Splitting

    private enum HTMLPart {
        case rawText(String)
        case image(URL)
    }

    private static func splitHTMLIntoParts(_ html: String) -> [HTMLPart] {
        let imgPattern = #"<img\s+[^>]*src\s*=\s*"([^"]*)"[^>]*/?\s*>"#
        guard let regex = try? NSRegularExpression(pattern: imgPattern, options: .caseInsensitive) else {
            return [.rawText(html)]
        }

        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        guard !matches.isEmpty else {
            return [.rawText(html)]
        }

        var parts: [HTMLPart] = []
        var lastEnd = 0

        for match in matches {
            let matchRange = match.range
            if matchRange.location > lastEnd {
                let textRange = NSRange(location: lastEnd, length: matchRange.location - lastEnd)
                let text = nsHTML.substring(with: textRange)
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parts.append(.rawText(text))
                }
            }
            if match.numberOfRanges >= 2 {
                let srcRange = match.range(at: 1)
                let src = nsHTML.substring(with: srcRange)
                if let url = URL(string: src) {
                    parts.append(.image(url))
                }
            }
            lastEnd = matchRange.location + matchRange.length
        }

        if lastEnd < nsHTML.length {
            let text = nsHTML.substring(from: lastEnd)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append(.rawText(text))
            }
        }

        return parts
    }

    // MARK: - HTML → AttributedString

    // @MainActor required: NSAttributedString(data:options:.html) uses WebKit internally
    // and must run on the main thread. Removing this will crash.
    @MainActor
    private static func parseHTMLToAttributedString(_ html: String, linkColor: Color) -> AttributedString? {
        let fullHTML = """
        <html><head><style>
        body { font-family: -apple-system; font-size: 15px; }
        a { color: \(linkColor.description); }
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
