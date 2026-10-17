import Foundation

extension OfflineGameStore {
    func save(
        _ report: OfflineGameReport,
        visitID: UUID? = nil,
        playedAt: Date? = nil,
        progress: ((Int, Int) -> Void)? = nil,
        completion: @escaping (Result<SavedOfflineGame, Error>) -> Void
    ) {
        let id = OfflineResourcePolicy.key(report.url)
        let time = playedAt ?? now()
        let tokenID = UUID()
        let token = OfflineDownloadCancellation()
        locked {
            latestStorage[id] = report.storage
            played[id] = max(
                played[id] ?? .distantPast,
                (try? game(id: id).playedAt) ?? .distantPast,
                time
            )
            downloads[tokenID] = token
        }
        queue.async {
            let result: Result<SavedOfflineGame, Error> = Result {
                guard report.ready else { throw OfflineGameError.gameNotReady }
                return try self.download(report, visitID: visitID, token: token, progress: progress)
            }
            _ = self.locked { self.downloads.removeValue(forKey: tokenID) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func download(
        _ report: OfflineGameReport,
        visitID: UUID?,
        token: OfflineDownloadCancellation,
        progress: ((Int, Int) -> Void)?
    ) throws -> SavedOfflineGame {
        let entry = OfflineResourcePolicy.canonical(report.url)
        guard OfflineResourcePolicy.isGameURL(entry),
              policy.allows(entry) else { throw OfflineGameError.unsupportedGame }
        let id = OfflineResourcePolicy.key(entry)
        let urls = Set(([entry] + report.resources).map(OfflineResourcePolicy.canonical))
            .filter(policy.allows).sorted { $0.absoluteString < $1.absoluteString }
        guard urls.count <= 4096 else { throw OfflineGameError.tooLarge }
        let staging = rootURL.appendingPathComponent(
            ".staging-" + UUID().uuidString,
            isDirectory: true
        )
        let prior: SavedOfflineGame? = try locked {
            try token.check()
            try prepareRoot()
            let previous = try? game(id: id)
            if let visitID = visitID, visits[id] == visitID, let previous = previous,
               Set(previous.resources.keys) == Set(urls.map(\.absoluteString))
            {
                return previous
            }
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
            return visitID != nil && visits[id] == visitID ? previous : nil
        }
        if !FileManager.default.fileExists(atPath: staging.path), let prior = prior {
            let metadata = catalogMetadata(for: entry)
            var updated = refreshCover(prior, metadata: metadata, token: token)
            try locked {
                try token.check()
                updated.title = metadata?.title ?? updated.title
                updated.catalogURL = metadata?.url ?? updated.catalogURL
                try updated.replaceStorage(latestStorage[id] ?? report.storage)
                updated.lastPlayedAt = max(prior.playedAt, played[id] ?? now())
                try writeManifest(updated)
            }
            return updated
        }
        defer {
            locked {
                try? FileManager.default.removeItem(at: staging)
                occupiedBytes = diskBytes(rootURL)
            }
        }
        let resources = try downloadResources(
            urls,
            entry: entry,
            id: id,
            staging: staging,
            prior: prior,
            token: token,
            progress: progress
        )
        let totalBytes = resources.values.reduce(Int64(0)) { $0 + $1.bytes }
        let metadata = catalogMetadata(for: entry)
        let cover = downloadCover(metadata?.cover, id: id, staging: staging, token: token)
        return try locked {
            try token.check()
            guard pins[id, default: 0] == 0 else { throw URLError(.cancelled) }
            var game = SavedOfflineGame(
                version: 1, id: id, url: report.url,
                title: metadata?
                    .title ??
                    (report.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty ? (entry.host ?? "Игра") : report.title),
                savedAt: now(), bytes: totalBytes, storage: latestStorage[id] ?? report.storage,
                environment: report.environment, resources: resources
            )
            game.lastPlayedAt = played[id] ?? now()
            game.catalogURL = metadata?.url
            game.cover = cover
            game.coverSourceURL = cover == nil ? nil : metadata?.cover
            let manifest = try JSONEncoder().encode(game)
            guard manifest.count <= 4 * 1024 * 1024 else { throw OfflineGameError.tooLarge }
            try ensureCapacity(
                Int64(manifest.count) + max(metadataReserveBytes, 2 * Int64(manifest.count)),
                protecting: [id],
                replacing: id
            )
            try write(
                manifest,
                to: staging.appendingPathComponent("manifest.json"),
                protecting: [id],
                atomic: false,
                replacing: id
            )
            let destination = directory(id)
            let oldBytes = diskBytes(destination)
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
            } else {
                try FileManager.default.moveItem(at: staging, to: destination)
            }
            occupiedBytes = max(0, (occupiedBytes ?? 0) - oldBytes)
            if let visitID = visitID {
                visits[id] = visitID
            } else {
                visits.removeValue(forKey: id)
            }
            return game
        }
    }

    private func downloadResources(
        _ urls: [URL], entry: URL, id: String, staging: URL, prior: SavedOfflineGame?,
        token: OfflineDownloadCancellation, progress: ((Int, Int) -> Void)?
    ) throws -> [String: SavedOfflineResource] {
        var resources: [String: SavedOfflineResource] = [:]
        for (index, url) in urls.enumerated() {
            try token.check()
            let file = staging.appendingPathComponent(OfflineResourcePolicy.key(url))
            var reused: SavedOfflineResource?
            if let cached = prior?.resources[url.absoluteString],
               let old = prior
               .map({ directory($0.id).appendingPathComponent(OfflineResourcePolicy.key(url)) }),
               FileManager.default.fileExists(atPath: old.path)
            {
                try locked {
                    try ensureDownloadCapacity(cached.bytes, for: id)
                    if FileManager.default.fileExists(atPath: old.path) {
                        try FileManager.default.copyItem(at: old, to: file)
                        occupiedBytes = (occupiedBytes ?? 0) + cached.bytes
                        reused = cached
                    }
                }
            }
            let resource = try reused ?? OfflineResourceDownload.fetch(
                url, to: file, configuration: configuration,
                remainingBytes: maximumBytes, allows: policy.allows,
                cancellation: token,
                reserve: { count in try self.locked {
                    try self.ensureDownloadCapacity(count, for: id)
                    self.occupiedBytes = (self.occupiedBytes ?? 0) + count
                } }
            )
            if url == entry,
               resource.bytes == 0 || !["text/html", "application/xhtml+xml"]
               .contains(resource.mimeType)
            {
                throw OfflineGameError.invalidResponse
            }
            resources[url.absoluteString] = resource
            DispatchQueue.main.async { progress?(index + 1, urls.count) }
        }
        return resources
    }

    private func downloadCover(
        _ url: URL?, id: String, staging: URL, token: OfflineDownloadCancellation
    ) -> SavedOfflineCover? {
        if let url = url {
            let file = staging.appendingPathComponent("cover")
            do {
                let resource = try OfflineResourceDownload.fetch(
                    url, to: file, configuration: configuration,
                    remainingBytes: 1024 * 1024, allows: OfflineCatalogMetadata.allowsCover,
                    cancellation: token,
                    reserve: { count in try self.locked {
                        try self.ensureDownloadCapacity(count, for: id)
                        self.occupiedBytes = (self.occupiedBytes ?? 0) + count
                    } }
                )
                guard OfflineCatalogMetadata.rasterMIMEs.contains(resource.mimeType)
                else { throw OfflineGameError.invalidResponse }
                return SavedOfflineCover(mimeType: resource.mimeType, bytes: resource.bytes)
            } catch {
                locked {
                    try? FileManager.default.removeItem(at: file)
                    occupiedBytes = diskBytes(rootURL)
                }
            }
        }
        return nil
    }
}
