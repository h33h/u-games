import Foundation

/// Disk mutations are short and serialized. Downloads never hold the metadata lock.
final class OfflineGameStore {
    static let scheme = "ugames-offline"
    static let maximumCacheBytes: Int64 = 2 * 1024 * 1024 * 1024
    static let shared: OfflineGameStore = {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return OfflineGameStore(rootURL: support.appendingPathComponent(
            "OfflineGames",
            isDirectory: true
        ))
    }()

    let rootURL: URL
    let maximumBytes: Int64
    let configuration: URLSessionConfiguration
    let queue = DispatchQueue(label: "dev.ugames.offline-download", qos: .utility)
    let metadataQueue = DispatchQueue(label: "dev.ugames.offline-metadata", qos: .utility)
    let lock = NSRecursiveLock()
    let policy = OfflineResourcePolicy()
    let now: () -> Date
    var occupiedBytes: Int64?
    var visits: [String: UUID] = [:]
    var latestStorage: [String: [String: String]] = [:]
    var played: [String: Date] = [:]
    var pins: [String: Int] = [:]
    var downloads: [UUID: OfflineDownloadCancellation] = [:]
    var catalog: [String: OfflineCatalogMetadata]?
    var failedRevisions: [String: Date] = [:]
    var restoredProgressRevisions = Set<String>()

    init(
        rootURL: URL,
        maximumCacheBytes: Int64 = OfflineGameStore.maximumCacheBytes,
        sessionConfiguration: URLSessionConfiguration = .ephemeral,
        now: @escaping () -> Date = Date.init
    ) {
        self.rootURL = rootURL
        maximumBytes = max(0, maximumCacheBytes)
        self.now = now
        configuration = sessionConfiguration
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
    }

    func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    func games() throws -> [SavedOfflineGame] {
        try locked {
            if occupiedBytes == nil {
                try prepareRoot()
            }
            guard FileManager.default.fileExists(atPath: rootURL.path) else { return [] }
            return try FileManager.default.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: nil
            )
            .compactMap { try? game(id: $0.lastPathComponent) }
            .sorted { max($0.playedAt, played[$0.id] ?? .distantPast) > max(
                $1.playedAt,
                played[$1.id] ?? .distantPast
            ) }
        }
    }

    func game(id: String) throws -> SavedOfflineGame {
        try locked {
            guard Self.validID(id) else { throw OfflineGameError.invalidReport }
            let bytes = try Data(contentsOf: directory(id).appendingPathComponent("manifest.json"))
            guard bytes.count <= 4 * 1024 * 1024 else { throw OfflineGameError.invalidReport }
            let game = try JSONDecoder().decode(SavedOfflineGame.self, from: bytes)
            guard game.version == 1, game.id == id, OfflineResourcePolicy.isGameURL(game.url),
                  id == OfflineResourcePolicy.key(game.url), game.resources.count <= 4096,
                  game.resources[OfflineResourcePolicy.canonical(game.url).absoluteString] != nil,
                  game.resources.allSatisfy({ key, resource in
                      guard let url = URL(string: key) else { return false }
                      return policy.allows(url) && resource.bytes >= 0 && resource.bytes <= Self
                          .maximumCacheBytes
                  })
            else { throw OfflineGameError.invalidReport }
            return game
        }
    }

    func game(matching url: URL) -> SavedOfflineGame? {
        guard OfflineResourcePolicy.isHTTPS(url) else { return nil }
        return (try? replayableGames())?.first {
            OfflineResourcePolicy.canonical($0.url) == OfflineResourcePolicy.canonical(url) ||
                ($0.catalogURL.map(OfflineResourcePolicy.canonical) == OfflineResourcePolicy
                    .canonical(url))
        }
    }

    func pin(_ id: String) {
        locked { pins[id, default: 0] += 1 }
    }

    func pinnedGame(id: String) throws -> SavedOfflineGame {
        try locked {
            do {
                let current = try game(id: id)
                try validateReplay(current)
                pins[id, default: 0] += 1
                return current
            } catch { throw OfflineGameError.missingResource }
        }
    }

    func replayableGames() throws -> [SavedOfflineGame] {
        try locked { try games().filter { (try? validateReplay($0)) != nil } }
    }

    private func validateReplay(_ game: SavedOfflineGame) throws {
        guard game.requiresRefresh != true, failedRevisions[game.id] != game.savedAt else {
            throw OfflineGameError.missingResource
        }
        for (url, resource) in game.resources {
            guard let url = URL(string: url),
                  let attributes = try? FileManager.default
                  .attributesOfItem(atPath: directory(game.id)
                      .appendingPathComponent(OfflineResourcePolicy.key(url)).path),
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.size] as? NSNumber)?.int64Value == resource.bytes
            else { throw OfflineGameError.missingResource }
        }
    }

    func suppressReplay(_ failed: SavedOfflineGame) {
        locked {
            if let current = try? game(id: failed.id), current.savedAt != failed.savedAt {
                return
            }
            failedRevisions[failed.id] = failed.savedAt
        }
        metadataQueue.async {
            try? self.locked {
                var current = try self.game(id: failed.id)
                guard current.savedAt == failed.savedAt,
                      self.failedRevisions[failed.id] == failed.savedAt,
                      current.requiresRefresh != true else { return }
                current.requiresRefresh = true
                try self.writeManifest(current)
            }
        }
    }

    func unpin(_ id: String) {
        locked { pins[id] = max(0, (pins[id] ?? 0) - 1) }
    }

    func cancelDownloads() {
        let active = locked { Array(downloads.values) }
        active.forEach { $0.cancel() }
    }

    func touch(_ id: String, at date: Date? = nil) {
        let date = date ?? now()
        locked { played[id] = max(played[id] ?? .distantPast, date) }
        metadataQueue.async {
            try? self.locked {
                var game = try self.game(id: id)
                game.lastPlayedAt = max(game.playedAt, self.played[id] ?? date)
                try self.writeManifest(game)
            }
        }
    }

    func updateStorage(
        _ storage: [String: String],
        for id: String,
        offline: Bool = false,
        completion: ((Error?) -> Void)? = nil
    ) {
        guard let data = try? JSONEncoder().encode(storage), data.count <= 2 * 1024 * 1024 else {
            DispatchQueue.main.async { completion?(OfflineGameError.invalidReport) }
            return
        }
        let accepted = locked { () -> Bool in
            if !offline, let current = try? game(id: id),
               hasPendingProgress(current)
            {
                return false
            }
            latestStorage[id] = storage
            return true
        }
        guard accepted else { DispatchQueue.main.async { completion?(nil) }
            return
        }
        metadataQueue.async {
            do {
                try self.locked {
                    var game = try self.game(id: id)
                    if !offline, self.hasPendingProgress(game) {
                        return
                    }
                    guard game.storage != storage else { return }
                    let values = self.latestStorage[id] ?? storage
                    let changedOffline = offline && self.progressValues(game.storage) != self
                        .progressValues(values)
                    try game.replaceStorage(values)
                    if changedOffline {
                        game.pendingProgressRevision = UUID().uuidString
                        game.offlineEditedAt = self.now()
                    } else if game.pendingProgressRevision
                        .map(self.restoredProgressRevisions.contains) == true
                    {
                        game.pendingProgressRevision = nil
                    }
                    try self.writeManifest(game)
                }
                DispatchQueue.main.async { completion?(nil) }
            } catch { DispatchQueue.main.async { completion?(error) } }
        }
    }

    func delete(_ game: SavedOfflineGame) throws {
        try locked {
            guard game.id == OfflineResourcePolicy.key(game.url),
                  pins[game.id, default: 0] == 0 else { throw OfflineGameError.invalidReport }
            try remove(game.id)
        }
    }

    func response(
        for offlineURL: URL,
        in game: SavedOfflineGame
    ) throws -> OfflineResourceResponse {
        guard offlineURL.scheme == Self.scheme, offlineURL.user == nil, offlineURL.password == nil,
              offlineURL.port == nil || offlineURL.port == 443,
              var components = URLComponents(url: offlineURL, resolvingAgainstBaseURL: false)
        else { throw OfflineGameError.missingResource }
        components.scheme = "https"
        guard let candidate = components.url else { throw OfflineGameError.missingResource }
        let original = OfflineResourcePolicy.canonical(candidate)
        if OfflineResourcePolicy.isSDK(original) {
            return OfflineResourceResponse(
                data: Data("/* SDK supplied by UGames offline runtime. */".utf8),
                mimeType: "application/javascript",
                textEncoding: "utf-8"
            )
        }
        guard let resource = game.resources[original.absoluteString],
              policy.allows(original) else { throw OfflineGameError.missingResource }
        let data = try Data(
            contentsOf: directory(game.id)
                .appendingPathComponent(OfflineResourcePolicy.key(original)),
            options: .mappedIfSafe
        )
        guard Int64(data.count) == resource.bytes else { throw OfflineGameError.missingResource }
        return try OfflineResourceResponse(
            data: OfflineResourceRewriter.rewrite(
                data,
                mimeType: resource.mimeType,
                textEncoding: resource.textEncoding
            ),
            mimeType: resource.mimeType,
            textEncoding: OfflineResourceRewriter.isText(resource.mimeType) ? "utf-8" : resource
                .textEncoding
        )
    }
}
