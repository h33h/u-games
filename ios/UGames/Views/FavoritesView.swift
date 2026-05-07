import SwiftUI

struct FavoritesView: View {
    @ObservedObject var favorites: FavoritesStore
    let onGameClick: (Game) -> Void
    let onBrowse: () -> Void

    private let columns = [GridItem(.adaptive(minimum: UGSize.tileGridMin, maximum: UGSize.tileGridMax), spacing: UGSpace.m)]

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
                        .padding(.horizontal, UGSpace.l)
                        .padding(.top, UGSpace.m)
                    LazyVGrid(columns: columns, spacing: UGSpace.m) {
                        ForEach(favorites.games) { game in
                            TileGameCard(
                                game: game,
                                isFavorite: true,
                                onTap: { onGameClick(game) },
                                onFavoriteToggle: { favorites.toggle(game) },
                            )
                        }
                    }
                    .padding(.horizontal, UGSpace.m)
                    .padding(.top, UGSpace.s)
                    .padding(.bottom, UGSize.tabBarInset)
                }
            }
        }
    }
}
