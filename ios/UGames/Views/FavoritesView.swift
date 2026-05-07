import SwiftUI

struct FavoritesView: View {
    @ObservedObject var favorites: FavoritesStore
    let onGameClick: (Game) -> Void
    let onBrowse: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 12)]

    var body: some View {
        ZStack {
            UGColor.bg0.ignoresSafeArea()
            if favorites.games.isEmpty {
                EmptyState(
                    systemIcon: "heart",
                    title: "No favorites yet",
                    message: "Tap ♥ on any game to save it.",
                    ctaLabel: "Browse games",
                    onCta: onBrowse,
                )
            } else {
                ScrollView {
                    Text("Favorites · \(favorites.games.count)")
                        .font(UGFont.titleM)
                        .foregroundColor(UGColor.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(favorites.games) { game in
                            TileGameCard(
                                game: game,
                                isFavorite: true,
                                onTap: { onGameClick(game) },
                                onFavoriteToggle: { favorites.toggle(game) },
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 96)
                }
            }
        }
    }
}
