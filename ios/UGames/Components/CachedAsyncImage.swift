import SwiftUI
import UIKit

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

        if let cached = ImageMemoryCache.shared.image(for: url) {
            phase = .success(Image(uiImage: cached))
            return
        }

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

final class ImageMemoryCache: @unchecked Sendable {
    static let shared = ImageMemoryCache()

    private let cache: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.totalCostLimit = 60 * 1024 * 1024
        return c
    }()

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func set(_ img: UIImage, for url: URL) {
        let cost = Int(img.size.width * img.size.height * img.scale * img.scale * 4)
        cache.setObject(img, forKey: url as NSURL, cost: cost)
    }
}
