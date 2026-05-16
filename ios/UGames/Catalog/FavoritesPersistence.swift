import Foundation

struct FavoritesPersistence {
    private let key = "favorite_games"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [Game] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Game].self, from: data)
        else { return [] }
        return decoded
    }

    func save(_ games: [Game]) {
        if let data = try? JSONEncoder().encode(games) {
            defaults.set(data, forKey: key)
        }
    }
}
