import Foundation
import Combine

/// Drives `GameDetailView`. Loads "More like this" via the
/// `similar_games` endpoint and exposes the seed `Game` directly. Keep
/// the seed mutable so any callsite that wants to swap to a fresher
/// `Game` (e.g. after a feed refetch) can — Phase 3 doesn't, but we
/// don't lose anything by keeping the door open.
@MainActor
final class GameDetailViewModel: ObservableObject {
    @Published private(set) var game: Game
    @Published private(set) var similar: [Game] = []
    @Published private(set) var isLoadingSimilar: Bool = false
    @Published private(set) var similarError: String?

    private let service: CatalogService
    private var loadTask: Task<Void, Never>?

    init(game: Game, service: CatalogService) {
        self.game = game
        self.service = service
        loadTask = Task { [weak self] in await self?.loadSimilar() }
    }

    deinit { loadTask?.cancel() }

    func loadSimilar() async {
        if isLoadingSimilar { return }
        isLoadingSimilar = true
        similarError = nil
        defer { isLoadingSimilar = false }
        let result = await service.fetchSimilar(appId: game.appId)
        // Drop the same game if the server happens to include it.
        similar = result.filter { $0.appId != game.appId }
    }
}
