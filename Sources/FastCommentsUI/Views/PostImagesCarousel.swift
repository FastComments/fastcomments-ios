import SwiftUI
import FastCommentsSwift

/// Paging carousel for multi-image feed posts. Uses TabView with page style.
public struct PostImagesCarousel: View {
    let mediaItems: [FeedPostMediaItem]
    var onImageTap: ((FeedPostMediaItem, Int) -> Void)?

    @State private var currentPage: Int = 0

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $currentPage) {
                ForEach(Array(mediaItems.enumerated()), id: \.offset) { index, item in
                    if let asset = item.sizes.first, let url = URL(string: asset.src) {
                        SmartImage(url: url, contentMode: .fill)
                            .clipped()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onImageTap?(item, index)
                            }
                            .tag(index)
                    }
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            #endif
            .frame(height: 300)

            // Image counter
            if mediaItems.count > 1 {
                Text("\(currentPage + 1)/\(mediaItems.count)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(8)
            }
        }
    }

    private var imagePlaceholder: some View {
        Rectangle()
            #if os(iOS)
            .fill(Color(uiColor: .systemGray5))
            #else
            .fill(Color(nsColor: .quaternaryLabelColor))
            #endif
            .overlay(
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            )
    }
}
