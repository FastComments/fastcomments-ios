import SwiftUI

/// Circular avatar image with optional online indicator.
/// Uses AsyncImage for zero-dependency image loading.
public struct AvatarImage: View {
    let url: String?
    var size: CGFloat = 36
    var showOnlineIndicator: Bool = false
    var isOnline: Bool = false

    @Environment(\.fastCommentsTheme) private var theme

    public init(url: String?, size: CGFloat = 36, showOnlineIndicator: Bool = false, isOnline: Bool = false) {
        self.url = url
        self.size = size
        self.showOnlineIndicator = showOnlineIndicator
        self.isOnline = isOnline
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let url = url, let imageURL = URL(string: url) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholderView
                    case .empty:
                        placeholderView
                    @unknown default:
                        placeholderView
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                placeholderView
            }

            if showOnlineIndicator && isOnline {
                Circle()
                    .fill(theme.resolveOnlineIndicatorColor())
                    .frame(width: size * 0.3, height: size * 0.3)
                    .overlay {
                        #if os(iOS)
                        Circle()
                            .stroke(Color(uiColor: .systemBackground), lineWidth: 1.5)
                        #else
                        Circle()
                            .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5)
                        #endif
                    }
            }
        }
    }

    private var placeholderView: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(.secondary)
    }
}
