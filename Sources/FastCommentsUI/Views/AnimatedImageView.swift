#if canImport(UIKit)
import SwiftUI
import UIKit

/// Shared image cache for all feed images (GIF and static).
/// Uses cost-based eviction so large decoded GIFs don't crowd out static images.
final class FeedImageCache {
    static let shared: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200
        cache.totalCostLimit = 50 * 1024 * 1024 // ~50 MB
        return cache
    }()

    /// Approximate byte cost of a UIImage for cache accounting.
    static func cost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else {
            // Animated images: estimate from frame count
            if let images = image.images {
                return images.reduce(0) { $0 + (cost(of: $1)) }
            }
            return 0
        }
        return cgImage.bytesPerRow * cgImage.height
    }
}

/// Displays an image from a URL, with animated GIF support.
/// Uses UIImageView for GIFs (which natively animates all frames)
/// and CachedStaticImageView for static images (backed by FeedImageCache).
struct SmartImage: View {
    let url: URL
    var contentMode: ContentMode = .fill

    var body: some View {
        if url.pathExtension.lowercased() == "gif" {
            AnimatedImageView(url: url, contentMode: contentMode)
        } else {
            CachedStaticImageView(url: url, contentMode: contentMode)
        }
    }
}

/// UIViewRepresentable wrapper around UIImageView for animated GIF display.
private struct AnimatedImageView: UIViewRepresentable {
    let url: URL
    var contentMode: ContentMode = .fill

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = contentMode == .fill ? .scaleAspectFill : .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return imageView
    }

    func updateUIView(_ imageView: UIImageView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url

        let key = url.absoluteString as NSString

        if let cached = FeedImageCache.shared.object(forKey: key) {
            imageView.image = cached
            return
        }

        imageView.image = nil

        URLSession.shared.dataTask(with: url) { [weak imageView] data, _, _ in
            guard let data else { return }
            guard let image = UIImage.animatedImage(with: data) else { return }
            FeedImageCache.shared.setObject(image, forKey: key as NSString, cost: FeedImageCache.cost(of: image))
            DispatchQueue.main.async { [weak imageView] in
                imageView?.image = image
            }
        }.resume()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var loadedURL: URL?
    }
}

/// UIViewRepresentable wrapper for cached static image display.
/// Shares FeedImageCache with AnimatedImageView so images survive view re-renders.
private struct CachedStaticImageView: UIViewRepresentable {
    let url: URL
    var contentMode: ContentMode = .fill

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = contentMode == .fill ? .scaleAspectFill : .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return imageView
    }

    func updateUIView(_ imageView: UIImageView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url

        let key = url.absoluteString as NSString

        if let cached = FeedImageCache.shared.object(forKey: key) {
            imageView.image = cached
            return
        }

        imageView.image = nil

        URLSession.shared.dataTask(with: url) { [weak imageView] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            FeedImageCache.shared.setObject(image, forKey: key as NSString, cost: FeedImageCache.cost(of: image))
            DispatchQueue.main.async { [weak imageView] in
                imageView?.image = image
            }
        }.resume()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var loadedURL: URL?
    }
}

// MARK: - UIImage GIF helper

private extension UIImage {
    /// Create an animated UIImage from GIF data. Falls back to static image.
    static func animatedImage(with data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }

        let count = CGImageSourceGetCount(source)
        guard count > 1 else {
            return UIImage(data: data)
        }

        var images: [UIImage] = []
        var totalDuration: TimeInterval = 0

        for i in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            images.append(UIImage(cgImage: cgImage))

            // Get frame duration
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any],
               let gifDict = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any] {
                let delay = (gifDict[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double)
                    ?? (gifDict[kCGImagePropertyGIFDelayTime as String] as? Double)
                    ?? 0.1
                totalDuration += max(delay, 0.02)
            } else {
                totalDuration += 0.1
            }
        }

        return UIImage.animatedImage(with: images, duration: totalDuration)
    }
}
#endif
