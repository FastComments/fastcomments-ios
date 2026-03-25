import SwiftUI

/// Date separator row for live chat mode.
public struct DateSeparatorRow: View {
    let separator: DateSeparator

    public var body: some View {
        HStack {
            line
            Text(separator.formattedDate)
                .font(.caption)
                .foregroundStyle(.secondary)
            line
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
    }

    private var line: some View {
        Rectangle()
            #if os(iOS)
            .fill(Color(uiColor: .separator))
            #else
            .fill(Color(nsColor: .separatorColor))
            #endif
            .frame(height: 0.5)
    }
}
