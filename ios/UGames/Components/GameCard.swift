import SwiftUI

/// Tile card for grids (Browse / Favorites / Similar).
struct TileGameCard: View {
    let game: Game
    let isFavorite: Bool
    let onTap: () -> Void
    let onFavoriteToggle: () -> Void

    private var halo: Color { Color(hex: game.mainColor) ?? UGColor.accent }
    private var placeholder: Color { Color(hex: game.mainColor) ?? UGColor.elevated }

    var body: some View {
        VStack(alignment: .leading, spacing: UGSpace.s) {
            // Cover ZStack: placeholder + image share the same clip + stroke,
            // so the image never bleeds past the rounded border. Heart and
            // rating pill are siblings inside the same ZStack so they
            // overlap the cover, not the surrounding shadow.
            ZStack {
                CoverImage(url: URL(string: game.coverUrl), placeholder: placeholder)

                UGCircleIconButton(
                    systemName: isFavorite ? "heart.fill" : "heart",
                    tint: isFavorite ? UGColor.danger : UGColor.textPrimary,
                    diameter: UGSize.buttonSm,
                    iconSize: 14,
                    action: onFavoriteToggle
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(UGSpace.s)

                if game.ratingCount > 0 {
                    UGChip(text: String(format: "★ %.1f", game.rating), style: .overlayRating)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(UGSpace.s)
                }
            }
            .aspectRatio(16.0/10.0, contentMode: .fit)
            .haloChrome(halo, size: .lg)

            // Title + meta wrapped in a fixed-height block so cards in the
            // same row don't end up at different heights when one has a
            // 1-line title and the next has 2 lines / no meta.
            VStack(alignment: .leading, spacing: UGSpace.xs) {
                Text(game.title)
                    .font(UGFont.bodyS)
                    .foregroundColor(UGColor.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                let meta = [
                    game.categories.first,
                    game.ratingCount > 0 ? "\(game.ratingCount) ratings" : nil,
                ].compactMap { $0 }.joined(separator: " · ")
                Text(meta.isEmpty ? " " : meta)
                    .font(UGFont.caption)
                    .foregroundColor(UGColor.textMuted)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: UGSize.tileTitleH, alignment: .topLeading)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

@available(iOS 17.0, *)
#Preview(traits: .fixedLayout(width: 200, height: 220)) {
    ZStack {
        Color.black.ignoresSafeArea()
        TileGameCard(
            game: Game(
                appId: 1, title: "Block Puzzle: Falling Shapes",
                rating: 4.9, ratingCount: 39,
                coverUrl: "", iconUrl: "",
                categories: ["Puzzle"], developer: "studio",
                mainColor: "#41B4F6"
            ),
            isFavorite: true,
            onTap: {}, onFavoriteToggle: {}
        )
        .padding(12)
    }
}

/// Wide card (140×96) for Continue / Trending / Favorites rows on Home.
struct WideGameCard: View {
    let game: Game
    let onTap: () -> Void

    private var halo: Color { Color(hex: game.mainColor) ?? UGColor.accent }
    private var placeholder: Color { Color(hex: game.mainColor) ?? UGColor.elevated }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CoverImage(url: URL(string: game.coverUrl), placeholder: placeholder)
            Text(game.title)
                .font(UGFont.caption)
                .foregroundColor(UGColor.textPrimary)
                .lineLimit(1)
                .padding(UGSpace.s)
                .ugShadow(.overlayText)
        }
        .frame(width: UGSize.wideCardW, height: UGSize.wideCardH)
        .haloChrome(halo, size: .lg)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

@available(iOS 17.0, *)
#Preview("Wide", traits: .fixedLayout(width: 180, height: 130)) {
    ZStack {
        Color.black.ignoresSafeArea()
        WideGameCard(
            game: Game(
                appId: 2, title: "Drift King",
                rating: 4.5, ratingCount: 12,
                coverUrl: "", iconUrl: "",
                categories: ["Racing"], developer: "studio",
                mainColor: "#FFC700"
            ),
            onTap: {}
        )
    }
}

/// 130×130 icon card with title underneath. Per-genre rows on Home.
struct SquareGameCard: View {
    let game: Game
    let onTap: () -> Void

    private var halo: Color {
        Color(hex: game.iconMainColor ?? game.mainColor) ?? UGColor.accent
    }
    private var placeholder: Color {
        Color(hex: game.iconMainColor ?? game.mainColor) ?? UGColor.elevated
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UGSpace.s) {
            CoverImage(
                url: URL(string: game.iconUrl.isEmpty ? game.coverUrl : game.iconUrl),
                placeholder: placeholder
            )
            .frame(width: UGSize.squareCard, height: UGSize.squareCard)
            .haloChrome(halo, size: .lg)
            Text(game.title)
                .font(UGFont.bodyS)
                .foregroundColor(UGColor.textPrimary)
                .lineLimit(1)
                .frame(width: UGSize.squareCard, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

@available(iOS 17.0, *)
#Preview("Square", traits: .fixedLayout(width: 160, height: 180)) {
    ZStack {
        Color.black.ignoresSafeArea()
        SquareGameCard(
            game: Game(
                appId: 3, title: "Lily's Tea",
                rating: 4.8, ratingCount: 24,
                coverUrl: "", iconUrl: "",
                categories: ["Casual"], developer: "studio",
                mainColor: "#FF7EB9",
                iconMainColor: "#FF7EB9"
            ),
            onTap: {}
        )
    }
}
