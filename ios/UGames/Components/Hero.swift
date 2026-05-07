import SwiftUI

/// Editorial Hero card for Home. Phase 1 STUB: image background + gradient.
/// Phase 2 will autoplay videoUrl through AVPlayerLayer when present.
struct HeroSection: View {
    let game: Game
    let onPlay: () -> Void
    let onFavorite: () -> Void
    let onShare: () -> Void

    private var halo: Color { Color(hex: game.mainColor) ?? UGColor.accent }
    private var placeholder: Color { Color(hex: game.mainColor) ?? UGColor.elevated }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            placeholder
            AsyncImage(url: URL(string: game.coverUrl)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    Color.clear
                }
            }
            // Bound the image to the hero's frame and clip — without this,
            // `.scaledToFill()` keeps the source image's intrinsic size and
            // the AsyncImage view overflows its parent (it would bleed past
            // the rounded corner and even past the card width on portrait
            // covers).
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            LinearGradient(
                stops: [.init(color: .clear, location: 0.35), .init(color: .black.opacity(0.85), location: 1.0)],
                startPoint: .top, endPoint: .bottom
            )
            VStack { topRow; Spacer() }
            bottomBlock
        }
        .frame(height: 300)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(halo.opacity(UGColor.haloBorderAlpha)))
        .shadow(color: halo.opacity(UGColor.haloAlpha), radius: 20, x: 0, y: 14)
    }

    private var topRow: some View {
        HStack {
            Text("✦ FEATURED TODAY")
                .font(UGFont.caption)
                .foregroundColor(UGColor.accent)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(UGColor.accent.opacity(0.18))
                .clipShape(Capsule())
            Spacer()
            heroIcon("heart", action: onFavorite)
            heroIcon("square.and.arrow.up", action: onShare)
        }
        .padding(14)
    }

    @ViewBuilder
    private func heroIcon(_ system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(UGColor.textPrimary)
                .frame(width: 32, height: 32)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
        .buttonStyle(.borderless)
    }

    private var bottomBlock: some View {
        let chips = [
            game.rating > 0 ? String(format: "★ %.1f", game.rating) : nil,
            game.ratingCount > 0 ? "\(game.ratingCount) ratings" : nil,
            game.categories.first,
        ].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 8) {
            if !chips.isEmpty {
                HStack(spacing: 6) {
                    ForEach(chips, id: \.self) { c in
                        Text(c)
                            .font(UGFont.caption)
                            .foregroundColor(UGColor.textSecondary)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
            }
            Text(game.title)
                .font(UGFont.display)
                .foregroundColor(UGColor.textPrimary)
                .lineLimit(2)
            Button(action: onPlay) {
                Text("▶ Play now")
                    .font(UGFont.bodyS.weight(.heavy))
                    .foregroundColor(.black)
                    .padding(.horizontal, 22).padding(.vertical, 11)
                    .background(LinearGradient.ugAccent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.borderless)
        }
        .padding(18)
    }
}

@available(iOS 17.0, *)
#Preview(traits: .fixedLayout(width: 360, height: 320)) {
    ZStack {
        Color.black.ignoresSafeArea()
        HeroSection(
            game: Game(
                appId: 1, title: "Block Puzzle: Falling Shapes",
                rating: 4.9, ratingCount: 39,
                coverUrl: "", iconUrl: "",
                categories: ["Puzzle"], developer: "studio",
                mainColor: "#41B4F6"
            ),
            onPlay: {}, onFavorite: {}, onShare: {}
        )
        .padding(14)
    }
}
