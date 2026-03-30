import SwiftUI

/// ViewModifier that shows a non-blocking warning banner (e.g. "Demo Mode") at the top of the view.
/// Parses HTML from the API warning to extract plain text and an optional link/button.
struct DemoBannerModifier: ViewModifier {
    let isDemo: Bool
    let warningMessage: String?

    func body(content: Content) -> some View {
        if isDemo || warningMessage != nil {
            VStack(spacing: 0) {
                warningBanner
                content
            }
        } else {
            content
        }
    }

    @ViewBuilder
    private var warningBanner: some View {
        if let warningMessage = warningMessage {
            let parsed = Self.parseWarningHTML(warningMessage)
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption2)
                    Text(parsed.text)
                        .font(.caption2)
                        .fontWeight(.semibold)
                }

                if let linkText = parsed.linkText, let url = parsed.linkURL {
                    Link(destination: url) {
                        Text(linkText)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(Color.orange.opacity(0.08))
            .foregroundStyle(.orange)
        } else {
            // isDemo but no warning message — just show simple banner
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.caption2)
                Text("Demo Mode")
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(Color.orange.opacity(0.08))
            .foregroundStyle(.orange)
        }
    }

    // MARK: - HTML Parsing

    /// Extracts plain text and an optional link from simple HTML like:
    /// `THIS IS A DEMO <a href="https://...">Create an Account</a>`
    struct ParsedWarning {
        let text: String
        let linkText: String?
        let linkURL: URL?
    }

    static func parseWarningHTML(_ html: String) -> ParsedWarning {
        // Extract <a href="...">text</a>
        let anchorPattern = #"<a\s+[^>]*href\s*=\s*"([^"]*)"[^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: anchorPattern, options: .caseInsensitive) else {
            return ParsedWarning(text: stripHTML(html), linkText: nil, linkURL: nil)
        }

        let nsHTML = html as NSString
        let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: nsHTML.length))

        if let match = match,
           match.numberOfRanges >= 3 {
            let href = nsHTML.substring(with: match.range(at: 1))
            let linkText = nsHTML.substring(with: match.range(at: 2))
            let url = URL(string: href)

            // Remove the anchor tag to get the plain text part
            let plainPart = regex.stringByReplacingMatches(
                in: html, range: NSRange(location: 0, length: nsHTML.length),
                withTemplate: ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            return ParsedWarning(
                text: stripHTML(plainPart),
                linkText: stripHTML(linkText),
                linkURL: url
            )
        }

        return ParsedWarning(text: stripHTML(html), linkText: nil, linkURL: nil)
    }

    static func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension View {
    func demoBanner(isDemo: Bool, warningMessage: String? = nil) -> some View {
        modifier(DemoBannerModifier(isDemo: isDemo, warningMessage: warningMessage))
    }
}
