import Foundation

extension OfflineGameStore {
    var metadataReserveBytes: Int64 {
        min(8 * 1024 * 1024, maximumBytes / 2)
    }

    func ensureDownloadCapacity(_ bytes: Int64, for id: String) throws {
        try ensureCapacity(bytes + metadataReserveBytes, protecting: [id], replacing: id)
    }

    func prepareRoot() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        var root = rootURL
        var flags = URLResourceValues()
        flags.isExcludedFromBackup = true
        try root.setResourceValues(flags)
        if occupiedBytes == nil {
            // An interrupted download is never published or used for replay.
            for child in try FileManager.default.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: nil
            )
                where child.lastPathComponent.hasPrefix(".staging-")
            {
                try? FileManager.default.removeItem(at: child)
            }
            occupiedBytes = diskBytes(rootURL)
            try ensureCapacity(metadataReserveBytes, protecting: [])
        }
    }

    func ensureCapacity(
        _ extra: Int64,
        protecting ids: Set<String>,
        replacing id: String? = nil
    ) throws {
        if occupiedBytes == nil {
            occupiedBytes = diskBytes(rootURL)
        }
        guard extra >= 0, extra <= maximumBytes else { throw OfflineGameError.tooLarge }
        for game in try games().reversed()
            where (occupiedBytes ?? 0) + extra > maximumBytes && !ids.contains(game.id) && pins[
                game.id,
                default: 0
            ] == 0
        {
            try remove(game.id)
        }
        // Keep the previous complete snapshot while space permits. A refresh may use the
        // full shared budget by dropping its own unpinned old copy as the final candidate.
        if (occupiedBytes ?? 0) + extra > maximumBytes, let id = id,
           pins[id, default: 0] == 0, FileManager.default.fileExists(atPath: directory(id).path)
        {
            try remove(id)
        }
        guard (occupiedBytes ?? 0) + extra <= maximumBytes else { throw OfflineGameError.tooLarge }
    }

    func remove(_ id: String) throws {
        let bytes = diskBytes(directory(id))
        try FileManager.default.removeItem(at: directory(id))
        occupiedBytes = max(0, (occupiedBytes ?? 0) - bytes)
        visits.removeValue(forKey: id)
    }

    func writeManifest(_ game: SavedOfflineGame) throws {
        let data = try JSONEncoder().encode(game)
        guard data.count <= 4 * 1024 * 1024 else { throw OfflineGameError.tooLarge }
        try write(
            data,
            to: directory(game.id).appendingPathComponent("manifest.json"),
            protecting: [game.id]
        )
    }

    func write(
        _ data: Data,
        to file: URL,
        protecting ids: Set<String>,
        atomic: Bool = true,
        replacing id: String? = nil
    ) throws {
        let old = diskBytes(file)
        try ensureCapacity(
            atomic ? Int64(data.count) : max(0, Int64(data.count) - old),
            protecting: ids,
            replacing: id
        )
        try data.write(to: file, options: atomic ? .atomic : [])
        occupiedBytes = max(0, (occupiedBytes ?? 0) + Int64(data.count) - old)
    }

    func directory(_ id: String) -> URL {
        rootURL.appendingPathComponent(id, isDirectory: true)
    }

    static func validID(_ id: String) -> Bool {
        id.range(
            of: "^[a-f0-9]{64}$",
            options: .regularExpression
        ) != nil
    }

    func diskBytes(_ url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        else { return 0 }
        if attributes[.type] as? FileAttributeType ==
            .typeRegular
        {
            return (attributes[.size] as? NSNumber)?.int64Value ?? 0
        }
        guard let files = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return 0 }
        return files.compactMap { $0 as? URL }.reduce(0) { sum, file in
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            return sum + (values?.isRegularFile == true ? Int64(values?.fileSize ?? 0) : 0)
        }
    }
}
