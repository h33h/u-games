import SwiftUI

/// Network-loaded cover image with a solid `mainColor` fallback, sized
/// to fill its frame and clipped at its bounds. Centralises the
/// `placeholder + GeometryReader { CachedAsyncImage { ... .frame .clipped } }`
/// recipe that every card surface (Hero, Tile, Wide, Square, StoryCard,
/// detail screenshots, profile avatar) was duplicating.
///
/// Usage:
/// ```
/// CoverImage(url: URL(string: game.coverUrl), placeholder: halo)
///     .frame(width: 130, height: 130)
///     .haloChrome(halo, size: .lg)
/// ```
struct CoverImage: View {
    let url: URL?
    var placeholder: Color = UGColor.elevated
    var contentMode: ContentMode = .fill

    var body: some View {
        ZStack {
            placeholder
            GeometryReader { geo in
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    default:
                        Color.clear
                    }
                }
            }
        }
    }
}
