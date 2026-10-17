import Foundation

extension OfflineGameStore {
    func recordCatalog(_ metadata: OfflineCatalogMetadata, completion: ((Bool) -> Void)? = nil) {
        metadataQueue.async {
            let changed = (try? self.locked { () -> Bool in
                guard metadata.isValid else { return false }
                try self.prepareRoot()
                var catalog = self.catalogMetadata()
                guard catalog[metadata.gameId] != metadata else { return false }
                if catalog.count >= 4096, catalog[metadata.gameId] == nil {
                    return false
                }
                catalog[metadata.gameId] = metadata
                let data = try JSONEncoder().encode(catalog)
                guard data.count <= 2 * 1024 * 1024 else { return false }
                try self.ensureCapacity(
                    Int64(data.count) + self.metadataReserveBytes,
                    protecting: []
                )
                try self.write(
                    data,
                    to: self.rootURL.appendingPathComponent("catalog.json"),
                    protecting: []
                )
                self.catalog = catalog
                for var game in try self.games()
                    where OfflineCatalogMetadata.gameID(for: game.url) == metadata.gameId
                {
                    game.title = metadata.title
                    game.catalogURL = metadata.url
                    try? self.writeManifest(game)
                }
                return true
            }) ?? false
            DispatchQueue.main.async { completion?(changed) }
        }
    }

    func catalogMetadata(for entry: URL) -> OfflineCatalogMetadata? {
        locked { OfflineCatalogMetadata.gameID(for: entry).flatMap { catalogMetadata()[$0] } }
    }

    func catalogMetadata() -> [String: OfflineCatalogMetadata] {
        if let catalog = catalog {
            return catalog
        }
        let file = rootURL.appendingPathComponent("catalog.json")
        let data = (try? Data(contentsOf: file)) ?? Data()
        let decoded = data.count <= 2 * 1024 * 1024 ?
            (try? JSONDecoder().decode([String: OfflineCatalogMetadata].self, from: data)) : nil
        let values = (decoded ?? [:]).filter { $0.key == $0.value.gameId && $0.value.isValid }
        catalog = values
        return values
    }

    func coverResponse(for id: String) throws -> OfflineResourceResponse {
        let game = try game(id: id)
        guard let cover = game.cover, OfflineCatalogMetadata.rasterMIMEs.contains(cover.mimeType),
              cover.bytes <= 1024 * 1024 else { throw OfflineGameError.missingResource }
        let data = try Data(contentsOf: directory(id).appendingPathComponent("cover"))
        guard Int64(data.count) == cover.bytes else { throw OfflineGameError.missingResource }
        return OfflineResourceResponse(data: data, mimeType: cover.mimeType, textEncoding: nil)
    }
}
