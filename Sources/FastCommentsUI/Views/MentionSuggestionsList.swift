import SwiftUI
import FastCommentsSwift

/// Autocomplete dropdown for @mentions in comment input.
struct MentionSuggestionsList: View {
    let suggestions: [UserSearchResult]
    var onSelect: ((UserSearchResult) -> Void)?

    @Environment(\.fastCommentsTheme) private var theme

    var body: some View {
        if !suggestions.isEmpty {
            VStack(spacing: 0) {
                ForEach(suggestions) { user in
                    Button {
                        onSelect?(user)
                    } label: {
                        HStack(spacing: 10) {
                            AvatarImage(url: user.avatarSrc, size: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(user.displayName ?? user.name)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                if let displayName = user.displayName, displayName != user.name {
                                    Text(user.name)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)

                    if user.id != suggestions.last?.id {
                        Divider()
                            .padding(.leading, 52)
                    }
                }
            }
            #if os(iOS)
            .background(Color(uiColor: .systemBackground))
            #else
            .background(Color(nsColor: .windowBackgroundColor))
            #endif
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
            .padding(.horizontal, 12)
        }
    }
}
