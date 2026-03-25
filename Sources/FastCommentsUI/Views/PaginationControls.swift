import SwiftUI

/// Next / Load All pagination buttons at the bottom of the comments list.
public struct PaginationControls: View {
    @ObservedObject var sdk: FastCommentsSDK
    var onLoadMore: (() async -> Void)?
    var onLoadAll: (() async -> Void)?

    @Environment(\.fastCommentsTheme) private var theme
    @State private var isLoadingMore = false

    public var body: some View {
        if sdk.hasMore {
            HStack(spacing: 16) {
                Button {
                    Task {
                        isLoadingMore = true
                        await onLoadMore?()
                        isLoadingMore = false
                    }
                } label: {
                    if isLoadingMore {
                        ProgressView()
                    } else {
                        Text(String(
                            format: NSLocalizedString("next_%lld", bundle: .module, comment: ""),
                            sdk.pageSize
                        ))
                    }
                }
                .disabled(isLoadingMore)

                if sdk.shouldShowLoadAll() {
                    Button {
                        Task {
                            isLoadingMore = true
                            await onLoadAll?()
                            isLoadingMore = false
                        }
                    } label: {
                        Text(String(
                            format: NSLocalizedString("load_all_%lld", bundle: .module, comment: ""),
                            sdk.getCountRemainingToShow()
                        ))
                    }
                    .disabled(isLoadingMore)
                }
            }
            .font(.subheadline)
            .foregroundStyle(theme.resolveActionButtonColor())
            .padding()
        }
    }
}
