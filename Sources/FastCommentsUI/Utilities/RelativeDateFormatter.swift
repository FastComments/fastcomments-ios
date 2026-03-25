import Foundation

/// Formats dates as relative strings ("2m ago", "3h ago", "Yesterday", etc.)
public enum RelativeDateFormatter {
    private static let formatter: Foundation.RelativeDateTimeFormatter = {
        let f = Foundation.RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    public static func format(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)

        if interval < 60 {
            return NSLocalizedString("just_now", bundle: .module, comment: "Just now")
        }

        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
