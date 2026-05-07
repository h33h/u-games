import SwiftUI
import UIKit

/// Drop-in replacement for SwiftUI's stock `AsyncImage(url:content:)`
/// that caches decoded images in memory (NSCache) and raw response
/// bytes on disk (URLCache.shared). Stock AsyncImage doesn't cache, so
/// flipping between Home → Detail → Home re-fetched every cover from
/// the network — visibly slow on flaky connections and wasteful on
/// data.
///
/// API matches AsyncImage so callsites can swap one-for-one, including
/// the trailing `content` closure that receives an `AsyncImagePhase`.
struct CachedAsyncImage<Content: View>: View {
    let url: URL?
    let scale: CGFloat
    let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty

    init(
        url: URL?,
        scale: CGFloat = 1.0,
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.url = url
        self.scale = scale
        self.content = content
    }

    var body: some View {
        content(phase)
            .task(id: url) { await load() }
    }

    private func load() async {
        guard let url = url else {
            phase = .empty
            return
        }

        // 1. Memory cache hit — skip everything else.
        if let cached = ImageMemoryCache.shared.image(for: url) {
            phase = .success(Image(uiImage: cached))
            return
        }

        // 2. Hit URLCache.shared first via a `.returnCacheDataElseLoad`
        //    request, falling back to the network on miss. Yandex's
        //    avatars URLs are content-hashed (the asset id is in the
        //    path), so cached responses never go stale — using a
        //    cache-first policy is safe and dramatically reduces
        //    re-fetch traffic.
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let img = UIImage(data: data, scale: scale) else {
                phase = .failure(URLError(.cannotDecodeContentData))
                return
            }
            ImageMemoryCache.shared.set(img, for: url)
            phase = .success(Image(uiImage: img))
        } catch {
            phase = .failure(error)
        }
    }
}

/// Process-lifetime memory cache for decoded UIImages. Distinct from
/// URLCache (which stores raw response bytes) because re-decoding a
/// JPEG is the actual cost on scroll — we want already-decoded bitmaps
/// ready to draw.
final class ImageMemoryCache: @unchecked Sendable {
    static let shared = ImageMemoryCache()

    private let cache: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.totalCostLimit = 60 * 1024 * 1024  // 60 MB of decoded pixels
        return c
    }()

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func set(_ img: UIImage, for url: URL) {
        // Cost ≈ uncompressed RGBA size. Helps NSCache evict the
        // largest images first when totalCostLimit is breached.
        let cost = Int(img.size.width * img.size.height * img.scale * img.scale * 4)
        cache.setObject(img, forKey: url as NSURL, cost: cost)
    }
}
