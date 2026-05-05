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
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                placeholder
                    .aspectRatio(16.0/10.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        AsyncImage(url: URL(string: game.coverUrl)) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFill()
                            default: Color.clear
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    )
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(halo.opacity(UGColor.haloBorderAlpha)))
                    .shadow(color: halo.opacity(UGColor.haloAlpha), radius: 14, x: 0, y: 12)

                Button(action: onFavoriteToggle) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isFavorite ? UGColor.danger : UGColor.textPrimary)
                        .frame(width: 30, height: 30)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Circle())
                }
                .buttonStyle(.borderless)
                .padding(8)

                if game.ratingCount > 0 {
                    HStack {
                        Text(String(format: "★ %.1f", game.rating))
                            .font(UGFont.caption)
                            .foregroundColor(UGColor.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Capsule())
                        Spacer()
                    }
                    .padding(8)
                    .frame(maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
            Text(game.title)
                .font(UGFont.bodyS)
                .foregroundColor(UGColor.textPrimary)
                .lineLimit(2)
            let meta = [
                game.categories.first,
                game.ratingCount > 0 ? "\(game.ratingCount) ratings" : nil,
            ].compactMap { $0 }.joined(separator: " · ")
            if !meta.isEmpty {
                Text(meta)
                    .font(UGFont.caption)
                    .foregroundColor(UGColor.textMuted)
                    .lineLimit(1)
            }
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
