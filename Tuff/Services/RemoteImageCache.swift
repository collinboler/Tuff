import UIKit
import SwiftUI

// Shared, memory-pressure-aware image cache.
// NSCache auto-evicts entries when the system is under memory pressure,
// which prevents the OOM kills that UIImage-per-AsyncImage caused.
final class RemoteImageCache {
    static let shared = RemoteImageCache()

    private let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 30 * 1024 * 1024 // 30 MB ceiling
        c.countLimit     = 80
        return c
    }()

    private init() {}

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }

    func store(_ image: UIImage, for url: URL) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: url.absoluteString as NSString, cost: cost)
    }
}

// Per-URL loader. Reuse across all views that show the same URL so only one
// network request is ever in-flight for a given image.
@MainActor
final class RemoteImageLoader: ObservableObject {
    @Published var image: UIImage?

    private var task: URLSessionDataTask?

    func load(from urlString: String?) {
        guard let urlString, let url = URL(string: urlString) else { return }

        // Serve from cache immediately — no flicker on scroll
        if let cached = RemoteImageCache.shared.image(for: url) {
            image = cached
            return
        }

        task?.cancel()
        task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data,
                  let img = UIImage(data: data) else { return }
            // Downsample to max 200 px before caching to keep memory lean
            let small = img.downsample(to: CGSize(width: 200, height: 200))
            RemoteImageCache.shared.store(small, for: url)
            Task { @MainActor [weak self] in
                self?.image = small
            }
        }
        task?.resume()
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

private extension UIImage {
    /// Downsample to fit within `maxSize` while preserving aspect ratio.
    func downsample(to maxSize: CGSize) -> UIImage {
        let scale = min(maxSize.width / size.width, maxSize.height / size.height, 1)
        if scale >= 1 { return self }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in self.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
