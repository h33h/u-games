import Foundation

extension OfflineGameStore {
    /// Catalog metadata can arrive after a game's resources have finished caching.
    /// Enrich only its cover; the stable resource snapshot stays in place.
    func refreshCover(
        _ game: SavedOfflineGame,
        metadata: OfflineCatalogMetadata?,
        token: OfflineDownloadCancellation
    ) -> SavedOfflineGame {
        guard let url = metadata?.cover,
              game.cover == nil || game.coverSourceURL != url else { return game }
        let file = rootURL.appendingPathComponent(".staging-cover-" + UUID().uuidString)
        defer {
            locked {
                try? FileManager.default.removeItem(at: file)
                occupiedBytes = diskBytes(rootURL)
            }
        }
        do {
            let resource = try OfflineResourceDownload.fetch(
                url, to: file, configuration: configuration,
                remainingBytes: 1024 * 1024, allows: OfflineCatalogMetadata.allowsCover,
                cancellation: token,
                reserve: { count in try self.locked {
                    try self.ensureCapacity(
                        count + self.metadataReserveBytes,
                        protecting: [game.id]
                    )
                    self.occupiedBytes = (self.occupiedBytes ?? 0) + count
                } }
            )
            guard OfflineCatalogMetadata.rasterMIMEs.contains(resource.mimeType)
            else { throw OfflineGameError.invalidResponse }
            return try locked {
                try token.check()
                var current = try self.game(id: game.id)
                guard OfflineCatalogMetadata.gameID(for: current.url)
                    .flatMap({ catalogMetadata()[$0]?.cover }) == url else { return current }
                let destination = directory(game.id).appendingPathComponent("cover")
                let previousBytes = diskBytes(destination)
                if FileManager.default.fileExists(atPath: destination.path) {
                    _ = try FileManager.default.replaceItemAt(destination, withItemAt: file)
                } else {
                    try FileManager.default.moveItem(at: file, to: destination)
                }
                occupiedBytes = max(0, (occupiedBytes ?? 0) - previousBytes)
                current.cover = SavedOfflineCover(
                    mimeType: resource.mimeType,
                    bytes: resource.bytes
                )
                current.coverSourceURL = url
                try writeManifest(current)
                return current
            }
        } catch { return (try? self.game(id: game.id)) ?? game }
    }
}
