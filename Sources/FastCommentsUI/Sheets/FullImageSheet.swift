import SwiftUI
import FastCommentsSwift

/// Full-screen, swipeable image viewer with per-page pinch-to-zoom and double-tap zoom.
/// Mirrors FullImageDialog.java from Android: a single source of truth for both single
/// and multi-image presentation — the single case is just a one-item gallery.
public struct FullImageSheet: View {
    /// Identifiable wrapper so callers can drive presentation with `.fullScreenCover(item:)`.
    /// Identity is derived from the inputs so reconstructing an equivalent value during
    /// a re-render does not tear down and re-present the sheet.
    public struct Presentation: Identifiable {
        public let items: [FeedPostMediaItem]
        public let startIndex: Int

        public init(items: [FeedPostMediaItem], startIndex: Int = 0) {
            self.items = items
            self.startIndex = max(0, min(startIndex, max(0, items.count - 1)))
        }

        /// Convenience for single-image presentation.
        public init(item: FeedPostMediaItem) {
            self.init(items: [item], startIndex: 0)
        }

        public var id: String {
            // Includes every item's lead asset so two distinct galleries
            // that happen to share the same first image (count + start index
            // matching too) don't collide and confuse `.fullScreenCover(item:)`.
            let joined = items.map { $0.sizes.first?.src ?? "" }.joined(separator: "|")
            return "\(items.count)-\(startIndex)-\(joined)"
        }
    }

    let presentation: Presentation

    @Environment(\.dismiss) private var dismiss
    @State private var currentPage: Int

    public init(presentation: Presentation) {
        self.presentation = presentation
        _currentPage = State(initialValue: presentation.startIndex)
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentPage) {
                ForEach(Array(presentation.items.enumerated()), id: \.offset) { index, item in
                    ZoomableImagePage(item: item)
                        .tag(index)
                }
            }
            #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .padding(.trailing, 16)
                }
                Spacer()

                if presentation.items.count > 1 {
                    Text("\(currentPage + 1) / \(presentation.items.count)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 24)
                }
            }
        }
        #if os(iOS)
            .statusBarHidden(true)
        #endif
    }
}

/// One page of the full-screen viewer — owns its own zoom/pan state, so each
/// page in the gallery preserves its own transform as the user pages through.
private struct ZoomableImagePage: View {
    let item: FeedPostMediaItem

    @Environment(\.displayScale) private var displayScale
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    /// Cumulative drag translation observed in the current pan gesture.
    /// Used to convert `DragGesture.translation` (cumulative from gesture
    /// start) into a per-frame delta, so a concurrent magnify that mutates
    /// `offset` isn't overwritten by a stale-baseline pan calculation.
    @State private var dragLastTranslation: CGSize = .zero

    private static let minScale: CGFloat = 1.0
    private static let maxScale: CGFloat = 5.0
    private static let zoomedThreshold: CGFloat = 1.01

    var body: some View {
        GeometryReader { geo in
            content(in: geo.size)
        }
    }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        if let url = bestQualityURL(for: size) {
            // Pan is gated via GestureMask rather than a conditional branch so
            // the view tree's identity stays stable — branching here would
            // tear SmartImage down whenever scale crosses the threshold.
            SmartImage(url: url, contentMode: .fit)
                .frame(width: size.width, height: size.height)
                .scaleEffect(scale)
                .offset(offset)
                .simultaneousGesture(
                    panGesture(in: size),
                    including: scale > Self.zoomedThreshold ? .all : .subviews
                )
                .simultaneousGesture(magnifyGesture(in: size))
                .gesture(doubleTapGesture(in: size))
        } else {
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: size.width, height: size.height)
        }
    }

    // MARK: - Asset selection

    /// Pick the smallest asset that can render the screen at full quality
    /// (≥ target pixel width). Falls back to the largest under the cap, then
    /// to the largest available. Mirrors Android's selectBestImageSize so a
    /// 10-image gallery doesn't resident-load 10 oversize originals.
    private func bestQualityURL(for size: CGSize) -> URL? {
        let sizes = item.sizes
        guard !sizes.isEmpty else { return nil }

        let target = targetPixelWidth(viewportPoints: size.width)
        let maxAcceptable = target * 1.5
        let sorted = sizes.sorted { $0.w < $1.w }

        let chosen: FeedPostMediaItemAsset = {
            if let fit = sorted.first(where: { CGFloat($0.w) >= target && CGFloat($0.w) <= maxAcceptable }) {
                return fit
            }
            if let largestUnderCap = sorted.last(where: { CGFloat($0.w) <= maxAcceptable }) {
                return largestUnderCap
            }
            return sorted.last ?? sizes[0]
        }()

        return URL(string: chosen.src)
    }

    /// Target asset pixel width for the current viewport. `viewportPoints` is
    /// the GeometryReader-reported size; multiplying by `displayScale` from
    /// the environment gives us the screen's pixel density without touching
    /// the deprecated `UIScreen.main`.
    private func targetPixelWidth(viewportPoints: CGFloat) -> CGFloat {
        let widthPoints = max(viewportPoints, 1)
        return widthPoints * max(displayScale, 1)
    }

    // MARK: - Gestures

    private func magnifyGesture(in size: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(lastScale * value, Self.minScale * 0.8), Self.maxScale * 1.1)
                offset = clamped(offset, scale: scale, in: size)
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    scale = min(max(scale, Self.minScale), Self.maxScale)
                    lastScale = scale
                    if scale <= Self.zoomedThreshold {
                        offset = .zero
                    } else {
                        offset = clamped(offset, scale: scale, in: size)
                    }
                }
            }
    }

    private func panGesture(in size: CGSize) -> some Gesture {
        // Apply translation deltas to the live `offset` rather than to a
        // baseline captured at gesture start — that way a concurrent magnify
        // can mutate `offset` between frames without us clobbering it.
        DragGesture()
            .onChanged { value in
                let delta = CGSize(
                    width: value.translation.width - dragLastTranslation.width,
                    height: value.translation.height - dragLastTranslation.height
                )
                dragLastTranslation = value.translation
                let raw = CGSize(
                    width: offset.width + delta.width,
                    height: offset.height + delta.height
                )
                offset = clamped(raw, scale: scale, in: size)
            }
            .onEnded { _ in
                dragLastTranslation = .zero
            }
    }

    /// Double-tap zoom that centers on the tap point — `SpatialTapGesture` is
    /// available on iOS 16+, so no availability gate needed.
    private func doubleTapGesture(in size: CGSize) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { event in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    if scale > Self.zoomedThreshold {
                        scale = 1
                        lastScale = 1
                        offset = .zero
                    } else {
                        let target: CGFloat = 2.5
                        scale = target
                        lastScale = target
                        // Translate so the tap point stays under the user's finger
                        // after scaling around the view center.
                        let dx = -(event.location.x - size.width / 2) * (target - 1)
                        let dy = -(event.location.y - size.height / 2) * (target - 1)
                        offset = clamped(CGSize(width: dx, height: dy), scale: target, in: size)
                    }
                }
            }
    }

    /// Clamp the pan offset so the scaled image never leaves the viewport.
    /// Approximates the image's rendered size as the viewport size at scale 1
    /// (true for `.fit` content with a matching aspect ratio; otherwise this
    /// over-permits panning into the letterbox, which is harmless).
    private func clamped(_ offset: CGSize, scale: CGFloat, in size: CGSize) -> CGSize {
        let extraW = max(0, size.width * (scale - 1) / 2)
        let extraH = max(0, size.height * (scale - 1) / 2)
        return CGSize(
            width: min(max(offset.width, -extraW), extraW),
            height: min(max(offset.height, -extraH), extraH)
        )
    }
}
