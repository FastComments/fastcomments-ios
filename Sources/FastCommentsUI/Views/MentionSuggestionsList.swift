import SwiftUI
import FastCommentsSwift

/// Autocomplete dropdown for @mentions in comment input.
struct MentionSuggestionsList: View {
    let suggestions: [UserSearchResult]
    var onSelect: ((UserSearchResult) -> Void)?

    var body: some View {
        if !suggestions.isEmpty {
            VStack(spacing: 0) {
                ForEach(suggestions) { user in
                    Button {
                        onSelect?(user)
                    } label: {
                        HStack(spacing: 8) {
                            AvatarImage(url: user.avatarSrc, size: 24)
                            Text(user.displayName ?? user.name)
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)

                    if user.id != suggestions.last?.id {
                        Divider()
                    }
                }
            }
            #if os(iOS)
            .background(Color(uiColor: .systemBackground))
            #else
            .background(Color(nsColor: .windowBackgroundColor))
            #endif
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
    }
}
