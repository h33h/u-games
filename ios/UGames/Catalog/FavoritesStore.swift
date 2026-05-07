import Foundation
import Combine

/// Persists the user's favorited games as JSON in UserDefaults. Mirrors
/// Android's Room-backed favorites table without dragging in SwiftData.
/// (Recents are NOT persisted locally — they come from Yandex's
/// server-side `recentGames` field tied to the authenticated profile.)
@MainActor
final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()

    @Published private(set) var games: [Game] = []

    private let key = "favorite_games"

    init() {
        load()
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
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        if let decoded = try? JSONDecoder().decode([Game].self, from: data) {
            games = decoded
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(games) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
