import SwiftUI

struct HeroSection: View {
    let game: Game
    let onPlay: () -> Void
    let onFavorite: () -> Void
    let onShare: () -> Void

    private var halo: Color { Color(hex: game.mainColor) ?? UGColor.accent }
    private var placeholder: Color { Color(hex: game.mainColor) ?? UGColor.elevated }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CoverImage(
                url: URL(string: game.coverUrl(size: "pjpg1280x720")),
                placeholder: placeholder
            )
            LinearGradient(
                stops: [.init(color: .clear, location: 0.35), .init(color: .black.opacity(0.85), location: 1.0)],
                startPoint: .top, endPoint: .bottom
            )
            VStack { topRow; Spacer() }
            bottomBlock
        }
        .frame(height: UGSize.heroH)
        .frame(maxWidth: .infinity)
        .haloChrome(halo, size: .xl)

        .contentShape(RoundedRectangle(cornerRadius: UGRadius.xl))
        .onTapGesture { onPlay() }
    }

    private var topRow: some View {
        HStack {
            UGChip(text: "✦ FEATURED TODAY", style: .accentSoft)
            Spacer()
            UGCircleIconButton(systemName: "heart", diameter: UGSize.buttonM, iconSize: 14, background: Color.black.opacity(0.5), action: onFavorite)
            UGCircleIconButton(systemName: "square.and.arrow.up", diameter: UGSize.buttonM, iconSize: 14, background: Color.black.opacity(0.5), action: onShare)
        }
        .padding(UGSpace.l)
    }

    private var bottomBlock: some View {
        let chips = [
            game.rating > 0 ? String(format: "★ %.1f", game.rating) : nil,
            game.ratingCount > 0 ? "\(game.ratingCount) ratings" : nil,
            game.categories.first,
        ].compactMap { $0 }
        return VStack(alignment: .leading, spacing: UGSpace.s) {
            if !chips.isEmpty {
                HStack(spacing: UGSpace.s) {
                    ForEach(chips, id: \.self) { c in
                        UGChip(text: c, style: .neutral)
                    }
                }
            }
            Text(game.title)
                .font(UGFont.display)
                .foregroundColor(UGColor.textPrimary)
                .lineLimit(2)
            UGPillButton(title: "▶ Play now", action: onPlay)
        }
        .padding(UGSpace.l)
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
