#if canImport(UIKit)
import SwiftUI
import UIKit

/// Displays an image from a URL, with animated GIF support.
/// Uses UIImageView for GIFs (which natively animates all frames)
/// and AsyncImage for static images.
struct SmartImage: View {
    let url: URL
    var contentMode: ContentMode = .fill

    var body: some View {
        if url.pathExtension.lowercased() == "gif" {
            AnimatedImageView(url: url, contentMode: contentMode)
        } else {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                case .failure:
                    imagePlaceholder
                case .empty:
                    imagePlaceholder
                        .overlay { ProgressView() }
                @unknown default:
                    imagePlaceholder
                }
            }
        }
    }

    private var imagePlaceholder: some View {
        Rectangle()
            .fill(Color(uiColor: .systemGray6))
            .overlay {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(.quaternary)
            }
    }
}

/// UIViewRepresentable wrapper around UIImageView for animated GIF display.
private struct AnimatedImageView: UIViewRepresentable {
    let url: URL
    var contentMode: ContentMode = .fill

    private static let imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 50
        return cache
    }()

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

        // Check cache first
        if let cached = Self.imageCache.object(forKey: key) {
            imageView.image = cached
            return
        }

        imageView.image = nil

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data else { return }
            guard let image = UIImage.animatedImage(with: data) else { return }
            Self.imageCache.setObject(image, forKey: key)
            DispatchQueue.main.async {
                imageView.image = image
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
