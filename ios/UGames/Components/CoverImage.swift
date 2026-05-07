import SwiftUI

struct CoverImage: View {
    let url: URL?
    var placeholder: Color = UGColor.Surface.raised
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
