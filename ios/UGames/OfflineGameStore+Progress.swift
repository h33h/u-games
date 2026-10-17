import Foundation

struct PendingOfflineProgress: Encodable {
    let gameId: String
    let revision: String
    let origin: String
    let editedAt: Double
    let storage: [String: String]
    let removedKeys: [String]
}

extension OfflineGameStore {
    func progressValues(_ values: [String: String]) -> [String: String] {
        values
            .filter {
                !$0.key.hasPrefix("ugames.offline.restored.") && $0.key != "ugames.offline.progress"
            }
    }

    func hasPendingProgress(_ game: SavedOfflineGame) -> Bool {
        game.pendingProgressRevision
            .map { UUID(uuidString: $0) != nil && !restoredProgressRevisions.contains($0) } ?? false
    }

    func hasPendingProgress(for url: URL) -> Bool {
        locked {
            (try? games())?.contains { $0.url.host == url.host && hasPendingProgress($0) } ?? false
        }
    }

    func prepareProgressMetadata(_ previous: SavedOfflineGame?, in game: inout SavedOfflineGame) {
        game.lastPlayedAt = played[game.id] ?? now()
        game.offlineEditedAt = previous?.offlineEditedAt
        guard let previous = previous, hasPendingProgress(previous) else { return }
        game.pendingProgressRevision = previous.pendingProgressRevision
        game.removedStorageKeys = previous.removedStorageKeys
    }

    func pendingProgress() -> [PendingOfflineProgress] {
        locked {
            let games = ((try? self.games()) ?? []).filter(hasPendingProgress)
            let grouped = Dictionary(grouping: games) { $0.url.host?.lowercased() ?? "" }
            return grouped.values.compactMap { candidates in
                guard let newest = candidates
                    .max(by: {
                        ($0.offlineEditedAt ?? $0.playedAt) < ($1.offlineEditedAt ?? $1.playedAt)
                    }),
                    let revision = newest.pendingProgressRevision,
                    let host = newest.url.host else { return nil }
                let removed = Set(candidates.flatMap { $0.removedStorageKeys ?? [] })
                    .subtracting(newest.storage.keys).sorted()
                guard removed.count <= 65536,
                      (try? JSONEncoder().encode(removed).count) ?? Int.max <= 2 * 1024 * 1024
                else { return nil }
                return PendingOfflineProgress(
                    gameId: newest.id,
                    revision: revision,
                    origin: "https://" + host.lowercased(),
                    editedAt: (newest.offlineEditedAt ?? newest.playedAt)
                        .timeIntervalSince1970 * 1000,
                    storage: newest.storage,
                    removedKeys: removed
                )
            }
        }
    }

    func acknowledgeProgress(_ body: Any, origin: OfflineReportOrigin) -> (String, String)? {
        struct Ack: Decodable { let version: Int
            let type: String
            let gameId: String
            let revision: String
        }
        guard origin.scheme == "https", origin.port == 0 || origin.port == 443,
              let body = body as? String, body.utf8.count <= 8192,
              let data = body.data(using: .utf8),
              let ack = try? JSONDecoder().decode(Ack.self, from: data), ack.version == 1,
              ack.type == "progress-restored" else { return nil }
        return locked {
            guard let game = try? self.game(id: ack.gameId),
                  game.url.host?.lowercased() == origin.host,
                  game.pendingProgressRevision == ack.revision else { return nil }
            let appliedAt = game.offlineEditedAt ?? game.playedAt
            for var candidate in (try? games()) ?? []
                where candidate.url.host?.lowercased() == origin
                .host && (candidate.offlineEditedAt ?? candidate.playedAt) <= appliedAt
            {
                guard let revision = candidate.pendingProgressRevision else { continue }
                restoredProgressRevisions.insert(revision)
                candidate.pendingProgressRevision = nil
                try? writeManifest(candidate)
            }
            return (ack.gameId, ack.revision)
        }
    }
}
