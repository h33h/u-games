import Foundation

struct SavedOfflineResource: Codable {
    let mimeType: String
    let textEncoding: String?
    let bytes: Int64
}

struct SavedOfflineCover: Codable {
    let mimeType: String
    let bytes: Int64
}

struct SavedOfflineGame: Codable {
    let version: Int
    let id: String
    let url: URL
    var title: String
    let savedAt: Date
    let bytes: Int64
    var storage: [String: String]
    let environment: [String: OfflineJSONValue]?
    let resources: [String: SavedOfflineResource]
    var lastPlayedAt: Date?
    var catalogURL: URL?
    var cover: SavedOfflineCover?
    var coverSourceURL: URL?
    var removedStorageKeys: [String]?

    mutating func replaceStorage(_ values: [String: String]) throws {
        let removed = Set(removedStorageKeys ?? []).union(storage.keys.filter { values[$0] == nil })
            .subtracting(values.keys).sorted()
        guard removed.count <= 65536, try JSONEncoder().encode(removed).count <= 2 * 1024 * 1024
        else { throw OfflineGameError.invalidReport }
        storage = values
        removedStorageKeys = removed.isEmpty ? nil : removed
    }

    var playedAt: Date {
        lastPlayedAt ?? savedAt
    }

    var offlineURL: URL {
        var value = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        value.scheme = OfflineGameStore.scheme
        return value.url!
    }
}

struct OfflineResourceResponse {
    let data: Data
    let mimeType: String
    let textEncoding: String?
}
