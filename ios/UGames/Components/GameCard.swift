import SwiftUI

enum GameCardStyle {
    case tile
    case wide
    case square
}

struct GameCard: View {
    let game: Game
    let style: GameCardStyle
    var isFavorite: Bool = false
    let onTap: () -> Void
    var onFavoriteToggle: (() -> Void)? = nil

    private var halo: Color {
        let hex = style == .square ? (game.iconMainColor ?? game.mainColor) : game.mainColor
        return Color(hex: hex) ?? UGColor.Accent.primary
    }
    private var placeholder: Color { halo }

    private var coverUrl: URL? {
        switch style {
        case .tile, .wide:
            URL(string: game.coverUrl(size: "pjpg250x140"))
        case .square:
            URL(string: game.iconUrl(size: "pjpg256x256"))
        }
    }

    var body: some View {
        Button {
            UGHaptics.tap()
            onTap()
        } label: {
            Group {
                switch style {
                case .tile: tileBody
                case .wide: wideBody
                case .square: squareBody
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(game.title)
    }

    private var tileBody: some View {
        VStack(alignment: .leading, spacing: UGSpace.s) {
            ZStack {
                CoverImage(url: coverUrl, placeholder: placeholder)
                if let onFavoriteToggle {
                    UGCircleIconButton(
                        systemName: isFavorite ? "heart.fill" : "heart",
                        accessibilityLabel: isFavorite ? "Remove from favorites" : "Add to favorites",
                        tint: isFavorite ? UGColor.Feedback.danger : UGColor.Text.primary,
                        diameter: UGSize.buttonSm,
                        iconSize: 14,
                        action: onFavoriteToggle
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(UGSpace.s)
                }
                if game.ratingCount > 0 {
                    UGChip(text: String(format: "★ %.1f", game.rating), style: .overlayRating)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(UGSpace.s)
                }
            }
            .aspectRatio(16.0/10.0, contentMode: .fit)
            .haloChrome(halo, size: .lg)

            VStack(alignment: .leading, spacing: UGSpace.xs) {
                Text(game.title)
                    .font(UGFont.bodyS)
                    .foregroundColor(UGColor.Text.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                let meta = [
                    game.categories.first,
                    game.ratingCount > 0 ? "\(game.ratingCount) ratings" : nil,
                ].compactMap { $0 }.joined(separator: " · ")
                if !meta.isEmpty {
                    Text(meta)
                        .font(UGFont.caption)
                        .foregroundColor(UGColor.Text.muted)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var wideBody: some View {
        ZStack(alignment: .bottomLeading) {
            CoverImage(url: coverUrl, placeholder: placeholder)
            Text(game.title)
                .font(UGFont.caption)
                .foregroundColor(UGColor.Text.primary)
                .lineLimit(1)
                .padding(UGSpace.s)
                .ugShadow(.elevation(.text))
        }
        .frame(width: UGSize.wideCardW, height: UGSize.wideCardH)
        .haloChrome(halo, size: .lg)
    }

    private var squareBody: some View {
        VStack(alignment: .leading, spacing: UGSpace.s) {
            CoverImage(url: coverUrl, placeholder: placeholder)
                .frame(width: UGSize.squareCard, height: UGSize.squareCard)
                .haloChrome(halo, size: .lg)
            Text(game.title)
                .font(UGFont.bodyS)
                .foregroundColor(UGColor.Text.primary)
                .lineLimit(1)
                .frame(width: UGSize.squareCard, alignment: .leading)
        }
    }
}

@available(iOS 17.0, *)
#Preview("Tile", traits: .fixedLayout(width: 200, height: 240)) {
    ZStack {
        Color.black.ignoresSafeArea()
        GameCard(
            game: Game(
                appId: 1, title: "Block Puzzle: Falling Shapes",
                rating: 4.9, ratingCount: 39,
                coverUrl: "", iconUrl: "",
                categories: ["Puzzle"], developer: "studio",
                mainColor: "#41B4F6"
            ),
            style: .tile,
            isFavorite: true,
            onTap: {},
            onFavoriteToggle: {}
        )
        .padding(12)
    }
}

@available(iOS 17.0, *)
#Preview("Wide", traits: .fixedLayout(width: 180, height: 130)) {
    ZStack {
        Color.black.ignoresSafeArea()
        GameCard(
            game: Game(
                appId: 2, title: "Drift King",
                rating: 4.5, ratingCount: 12,
                coverUrl: "", iconUrl: "",
                categories: ["Racing"], developer: "studio",
                mainColor: "#FFC700"
            ),
            style: .wide,
            onTap: {}
        )
    }
}

@available(iOS 17.0, *)
#Preview("Square", traits: .fixedLayout(width: 160, height: 180)) {
    ZStack {
        Color.black.ignoresSafeArea()
        GameCard(
            game: Game(
                appId: 3, title: "Lily's Tea",
                rating: 4.8, ratingCount: 24,
                coverUrl: "", iconUrl: "",
                categories: ["Casual"], developer: "studio",
                mainColor: "#FF7EB9",
                iconMainColor: "#FF7EB9"
            ),
            style: .square,
            onTap: {}
        )
    }
}
