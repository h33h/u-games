import Foundation
import Combine

@MainActor
final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()

    @Published private(set) var games: [Game] = []

    private let persistence: FavoritesPersistence

    init(persistence: FavoritesPersistence = FavoritesPersistence()) {
        self.persistence = persistence
        games = persistence.load()
    }

    func contains(_ appId: Int64) -> Bool {
        games.contains(where: { $0.appId == appId })
    }

    func toggle(_ game: Game) {
        if contains(game.appId) {
            games.removeAll { $0.appId == game.appId }
        } else {
            games.insert(game, at: 0)
        }
        persistence.save(games)
    }
}
