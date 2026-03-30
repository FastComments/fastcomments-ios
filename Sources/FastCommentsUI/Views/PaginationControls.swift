import SwiftUI

/// Next / Load All pagination buttons at the bottom of the comments list.
public struct PaginationControls: View {
    @ObservedObject var sdk: FastCommentsSDK
    var onLoadMore: (() async -> Void)?
    var onLoadAll: (() async -> Void)?

    @Environment(\.fastCommentsTheme) private var theme
    @State private var isLoadingMore = false

    private var nextCount: Int {
        min(sdk.getCountRemainingToShow(), sdk.pageSize)
    }

    public var body: some View {
        if sdk.hasMore {
            HStack(spacing: 12) {
                Button {
                    Task {
                        isLoadingMore = true
                        await onLoadMore?()
                        isLoadingMore = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isLoadingMore {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                        Text(String(
                            format: NSLocalizedString("next_%lld", bundle: .module, comment: ""),
                            nextCount
                        ))
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.resolveActionButtonColor())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(theme.resolveActionButtonColor().opacity(0.08))
                    .clipShape(Capsule())
                }
                .disabled(isLoadingMore)

                if sdk.shouldShowLoadAll() && sdk.commentCountOnServer < 2000 {
                    Button {
                        Task {
                            isLoadingMore = true
                            await onLoadAll?()
                            isLoadingMore = false
                        }
                    } label: {
                        Text(String(
                            format: NSLocalizedString("load_all_%lld", bundle: .module, comment: ""),
                            sdk.commentCountOnServer
                        ))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(theme.resolveActionButtonColor())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(theme.resolveActionButtonColor().opacity(0.08))
                        .clipShape(Capsule())
                    }
                    .disabled(isLoadingMore)
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 12)
        }
    }
}
