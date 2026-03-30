import SwiftUI

/// Date separator row for live chat mode.
public struct DateSeparatorRow: View {
    let separator: DateSeparator

    @Environment(\.fastCommentsTheme) private var theme

    public var body: some View {
        HStack(spacing: 12) {
            line
            Text(separator.formattedDate)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
            line
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
    }

    private var line: some View {
        Rectangle()
            .fill(theme.resolveSeparatorColor().opacity(0.5))
            .frame(height: 0.5)
    }
}
