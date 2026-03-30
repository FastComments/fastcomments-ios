#if canImport(UIKit)
import Foundation
import UIKit

/// Converts NSAttributedString to HTML, supporting bold, italic, code, and links.
/// Uses a stack-based approach to correctly nest and close tags.
enum AttributedStringHTMLConverter {

    /// Convert an attributed string to an HTML string.
    static func convert(_ attributedString: NSAttributedString) -> String {
        guard attributedString.length > 0 else { return "" }

        var html = ""
        var activeTags: [Tag] = []
        let fullRange = NSRange(location: 0, length: attributedString.length)

        attributedString.enumerateAttributes(in: fullRange, options: []) { attrs, range, _ in
            // Handle image attachments
            if let imageUrl = attrs[.imageURL] as? String {
                // Close any active tags first
                while let last = activeTags.popLast() {
                    html += last.closeTag
                }
                html += "<img src=\"\(escapeHTML(imageUrl))\" />"
                return
            }

            // Skip attachment characters (object replacement char) without imageURL
            let text = (attributedString.string as NSString).substring(with: range)
            if text == "\u{FFFC}" { return }

            let desiredTags = tagsForAttributes(attrs)

            // Find longest matching prefix between active and desired tags
            let commonPrefix = zip(activeTags, desiredTags).prefix(while: { $0 == $1 }).count

            // Close everything after the common prefix (reverse order)
            while activeTags.count > commonPrefix {
                html += activeTags.removeLast().closeTag
            }

            // Open new tags after the common prefix
            for tag in desiredTags[commonPrefix...] {
                html += tag.openTag
                activeTags.append(tag)
            }

            // Append HTML-escaped text
            html += escapeHTML(text)
        }

        // Close remaining open tags
        while let last = activeTags.popLast() {
            html += last.closeTag
        }

        return html
    }

    // MARK: - Tag Model

    private enum Tag: Equatable {
        case bold
        case italic
        case strikethrough
        case code
        case link(URL)

        var openTag: String {
            switch self {
            case .bold: return "<b>"
            case .italic: return "<i>"
            case .strikethrough: return "<strike>"
            case .code: return "<code>"
            case .link(let url): return "<a href=\"\(escapeHTML(url.absoluteString))\">"
            }
        }

        var closeTag: String {
            switch self {
            case .bold: return "</b>"
            case .italic: return "</i>"
            case .strikethrough: return "</strike>"
            case .code: return "</code>"
            case .link: return "</a>"
            }
        }

        static func == (lhs: Tag, rhs: Tag) -> Bool {
            switch (lhs, rhs) {
            case (.bold, .bold), (.italic, .italic), (.strikethrough, .strikethrough), (.code, .code): return true
            case (.link(let a), .link(let b)): return a == b
            default: return false
            }
        }
    }

    // MARK: - Helpers

    private static func tagsForAttributes(_ attrs: [NSAttributedString.Key: Any]) -> [Tag] {
        var tags: [Tag] = []

        if let font = attrs[.font] as? UIFont {
            let traits = font.fontDescriptor.symbolicTraits
            if traits.contains(.traitMonoSpace) {
                tags.append(.code)
            } else {
                if traits.contains(.traitBold) { tags.append(.bold) }
                if traits.contains(.traitItalic) { tags.append(.italic) }
            }
        }

        if let strikeStyle = attrs[.strikethroughStyle] as? Int, strikeStyle == NSUnderlineStyle.single.rawValue {
            tags.append(.strikethrough)
        }

        if let url = attrs[.link] as? URL {
            tags.append(.link(url))
        } else if let urlString = attrs[.link] as? String, let url = URL(string: urlString) {
            tags.append(.link(url))
        }

        return tags
    }

    private static func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
#endif
