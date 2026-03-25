import SwiftUI
import FastCommentsSwift

/// Full-screen image viewer with pinch-to-zoom. Supports single image and gallery mode.
/// Mirrors FullImageDialog.java from Android.
public struct FullImageSheet: View {
    enum Mode: Identifiable {
        case single(url: String)
        case gallery(items: [FeedPostMediaItem], startIndex: Int)

        var id: String {
            switch self {
            case .single(let url): return "single-\(url)"
            case .gallery(let items, let idx): return "gallery-\(items.count)-\(idx)"
            }
        }
    }

    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage: Int = 0
    @State private var scale: CGFloat = 1.0

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            switch mode {
            case .single(let url):
                zoomableImage(url: url)

            case .gallery(let items, let startIndex):
                TabView(selection: $currentPage) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        if let asset = item.sizes.max(by: { $0.w < $1.w }) {
                            zoomableImage(url: asset.src)
                                .tag(index)
                        }
                    }
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                #endif
                .onAppear { currentPage = startIndex }

                // Counter
                if items.count > 1 {
                    VStack {
                        Spacer()
                        Text("\(currentPage + 1) / \(items.count)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .padding(.bottom, 40)
                    }
                }
            }

            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .padding()
            }
        }
    }

    @ViewBuilder
    private func zoomableImage(url: String) -> some View {
        if let imageURL = URL(string: url) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = value
                                }
                                .onEnded { value in
                                    withAnimation(.spring()) {
                                        scale = max(1.0, min(value, 5.0))
                                    }
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring()) {
                                scale = scale > 1.0 ? 1.0 : 2.5
                            }
                        }
                case .failure:
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.5))
                case .empty:
                    ProgressView()
                        .tint(.white)
                @unknown default:
                    EmptyView()
                }
            }
        }
    }
}
