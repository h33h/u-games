import Foundation
import Combine

/// Locally tracks games the user has opened, ordered by recency. Backed by
/// UserDefaults — no auth required and survives across launches.
@MainActor
final class RecentGamesStore: ObservableObject {
    static let shared = RecentGamesStore()

    @Published private(set) var games: [Game] = []

    private let key = "recent_games"
    private let limit = 20

    init() {
        load()
    }

    func record(_ game: Game) {
        var current = games.filter { $0.appId != game.appId }
        current.insert(game, at: 0)
        if current.count > limit { current = Array(current.prefix(limit)) }
        games = current
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
