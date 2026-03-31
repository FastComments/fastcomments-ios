import SwiftUI

/// Circular avatar image with optional online indicator and smooth loading.
public struct AvatarImage: View {
    let url: String?
    var size: CGFloat = 36
    var showOnlineIndicator: Bool = false
    var isOnline: Bool = false
    var onlineIdentifier: String?

    @Environment(\.fastCommentsTheme) private var theme

    public init(url: String?, size: CGFloat = 36, showOnlineIndicator: Bool = false, isOnline: Bool = false, onlineIdentifier: String? = nil) {
        self.url = url
        self.size = size
        self.showOnlineIndicator = showOnlineIndicator
        self.isOnline = isOnline
        self.onlineIdentifier = onlineIdentifier
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
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    case .failure:
                        placeholderView
                    case .empty:
                        placeholderView
                            .overlay {
                                ProgressView()
                                    .scaleEffect(0.5)
                            }
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
                    .frame(width: onlineIndicatorSize, height: onlineIndicatorSize)
                    .overlay {
                        Circle()
                            .stroke(onlineIndicatorBorderColor, lineWidth: 2)
                    }
                    .offset(x: 1, y: 1)
                    .accessibilityIdentifier(onlineIdentifier ?? "online-indicator")
            }
        }
    }

    private var onlineIndicatorSize: CGFloat {
        max(size * 0.28, 8)
    }

    private var onlineIndicatorBorderColor: Color {
        #if os(iOS)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    private var placeholderView: some View {
        Circle()
            .fill(placeholderBackground)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "person.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.45, height: size * 0.45)
                    .foregroundStyle(.white.opacity(0.8))
            }
    }

    private var placeholderBackground: some ShapeStyle {
        #if os(iOS)
        Color(uiColor: .systemGray4)
        #else
        Color(nsColor: .systemGray)
        #endif
    }
}
