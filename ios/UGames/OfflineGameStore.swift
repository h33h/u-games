import Foundation
import UniformTypeIdentifiers

struct SavedOfflineResource: Codable {
    let mimeType: String
    let textEncoding: String?
    let bytes: Int64
}

struct SavedOfflineGame: Codable {
    let version: Int
    let id: String
    let url: URL
    let title: String
    let savedAt: Date
    let bytes: Int64
    var storage: [String: String]
    let environment: [String: OfflineJSONValue]?
    let resources: [String: SavedOfflineResource]

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

final class OfflineGameStore {
    static let scheme = "ugames-offline"
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

    private let rootURL: URL
    private let maximumGameBytes: Int64
    private let configuration: URLSessionConfiguration
    private let queue = DispatchQueue(label: "dev.ugames.offline-download", qos: .utility)
    private let policy = OfflineResourcePolicy()

    init(
        rootURL: URL,
        maximumGameBytes: Int64 = 512 * 1024 * 1024,
        sessionConfiguration: URLSessionConfiguration = .ephemeral
    ) {
        self.rootURL = rootURL
        self.maximumGameBytes = maximumGameBytes
        configuration = sessionConfiguration
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 180
    }

    func games() throws -> [SavedOfflineGame] {
        guard FileManager.default.fileExists(atPath: rootURL.path) else { return [] }
        let children = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        )
        return children.compactMap { child in
            guard child.lastPathComponent
                .range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { return nil }
            return try? game(id: child.lastPathComponent)
        }.sorted { $0.savedAt > $1.savedAt }
    }

    func game(id: String) throws -> SavedOfflineGame {
        guard id.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
        else { throw OfflineGameError.invalidReport }
        let bytes = try Data(contentsOf: rootURL.appendingPathComponent(id)
            .appendingPathComponent("manifest.json"))
        guard bytes.count <= 4 * 1024 * 1024 else { throw OfflineGameError.invalidReport }
        let game = try JSONDecoder().decode(SavedOfflineGame.self, from: bytes)
        guard game.version == 1, game.id == id, OfflineResourcePolicy.isGameURL(game.url),
              id == OfflineResourcePolicy.key(game.url), game.resources.count <= 4096,
              game.resources[OfflineResourcePolicy.canonical(game.url).absoluteString] != nil,
              game.resources.allSatisfy({ key, resource in
                  guard let url = URL(string: key) else { return false }
                  return policy.allows(url) && resource.bytes >= 0 && resource
                      .bytes <= maximumGameBytes
              })
        else { throw OfflineGameError.invalidReport }
        return game
    }

    func save(
        _ report: OfflineGameReport,
        progress: ((Int, Int) -> Void)? = nil,
        completion: @escaping (Result<SavedOfflineGame, Error>) -> Void
    ) {
        queue.async {
            do {
                guard report.ready else { throw OfflineGameError.gameNotReady }
                let game = try self.download(report, progress: progress)
                DispatchQueue.main.async { completion(.success(game)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private func download(
        _ report: OfflineGameReport,
        progress: ((Int, Int) -> Void)?
    ) throws -> SavedOfflineGame {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        var directory = rootURL
        var flags = URLResourceValues()
        flags.isExcludedFromBackup = true
        try directory.setResourceValues(flags)
        let entry = OfflineResourcePolicy.canonical(report.url)
        guard OfflineResourcePolicy.isGameURL(entry),
              policy.allows(entry) else { throw OfflineGameError.unsupportedGame }
        let urls = Set(([entry] + report.resources).map(OfflineResourcePolicy.canonical))
            .filter(policy.allows).sorted { $0.absoluteString < $1.absoluteString }
        guard urls.count <= 4096 else { throw OfflineGameError.tooLarge }
        let staging = rootURL.appendingPathComponent(
            ".staging-" + UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: staging) }
        var resources: [String: SavedOfflineResource] = [:]
        var totalBytes: Int64 = 0
        for (index, url) in urls.enumerated() {
            let file = staging.appendingPathComponent(OfflineResourcePolicy.key(url))
            let resource = try OfflineResourceDownload.fetch(
                url,
                to: file,
                configuration: configuration,
                remainingBytes: maximumGameBytes - totalBytes,
                policy: policy
            )
            if url == entry,
               resource.bytes == 0 || !["text/html", "application/xhtml+xml"]
               .contains(resource.mimeType)
            {
                throw OfflineGameError.invalidResponse
            }
            resources[url.absoluteString] = resource
            totalBytes += resource.bytes
            DispatchQueue.main.async { progress?(index + 1, urls.count) }
        }
        let game = SavedOfflineGame(
            version: 1,
            id: OfflineResourcePolicy.key(entry),
            url: report.url,
            title: report.title.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty ? (entry.host ?? "Игра") : report.title,
            savedAt: Date(),
            bytes: totalBytes,
            storage: report.storage,
            environment: report.environment,
            resources: resources
        )
        try JSONEncoder().encode(game).write(
            to: staging.appendingPathComponent("manifest.json"),
            options: .atomic
        )
        let destination = rootURL.appendingPathComponent(game.id, isDirectory: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
        } else {
            try FileManager.default.moveItem(at: staging, to: destination)
        }
        return game
    }

    func updateStorage(
        _ storage: [String: String],
        for id: String,
        completion: ((Error?) -> Void)? = nil
    ) {
        queue.async {
            do {
                let encoded = try JSONEncoder().encode(storage)
                guard encoded.count <= 2 * 1024 * 1024 else { throw OfflineGameError.invalidReport }
                var game = try self.game(id: id)
                if game.storage == storage {
                    DispatchQueue.main.async { completion?(nil) }
                    return
                }
                game.storage = storage
                try JSONEncoder().encode(game).write(
                    to: self.rootURL.appendingPathComponent(id)
                        .appendingPathComponent("manifest.json"),
                    options: .atomic
                )
                DispatchQueue.main.async { completion?(nil) }
            } catch { DispatchQueue.main.async { completion?(error) } }
        }
    }

    func delete(_ game: SavedOfflineGame) throws {
        guard game.id == OfflineResourcePolicy.key(game.url)
        else { throw OfflineGameError.invalidReport }
        try FileManager.default.removeItem(at: rootURL.appendingPathComponent(game.id))
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
            contentsOf: rootURL.appendingPathComponent(game.id)
                .appendingPathComponent(OfflineResourcePolicy.key(original)),
            options: .mappedIfSafe
        )
        guard Int64(data.count) == resource.bytes else { throw OfflineGameError.missingResource }
        return try OfflineResourceResponse(
            data: OfflineResourceRewriter
                .rewrite(data, mimeType: resource.mimeType, textEncoding: resource.textEncoding),
            mimeType: resource.mimeType,
            textEncoding: OfflineResourceRewriter.isText(resource.mimeType) ? "utf-8" : resource
                .textEncoding
        )
    }
}

private final class OfflineResourceDownload: NSObject, URLSessionDataDelegate {
    private let output: FileHandle
    private let remainingBytes: Int64
    private let policy: OfflineResourcePolicy
    private let completed = DispatchSemaphore(value: 0)
    private var bytes: Int64 = 0
    private var response: HTTPURLResponse?
    private var failure: Error?
    private var redirects = 0

    private init(destination: URL, remainingBytes: Int64, policy: OfflineResourcePolicy) throws {
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        output = try FileHandle(forWritingTo: destination)
        self.remainingBytes = remainingBytes
        self.policy = policy
    }

    static func fetch(
        _ url: URL,
        to destination: URL,
        configuration: URLSessionConfiguration,
        remainingBytes: Int64,
        policy: OfflineResourcePolicy
    ) throws -> SavedOfflineResource {
        guard remainingBytes >= 0 else { throw OfflineGameError.tooLarge }
        let operation = try OfflineResourceDownload(
            destination: destination,
            remainingBytes: remainingBytes,
            policy: policy
        )
        let session = URLSession(
            configuration: configuration,
            delegate: operation,
            delegateQueue: nil
        )
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpShouldHandleCookies = false
        session.dataTask(with: request).resume()
        operation.completed.wait()
        session.finishTasksAndInvalidate()
        try operation.output.close()
        if let error = operation.failure {
            throw error
        }
        guard let response = operation.response else { throw OfflineGameError.invalidResponse }
        let mime = response.mimeType ?? UTType(filenameExtension: url.pathExtension)?
            .preferredMIMEType ?? "application/octet-stream"
        return SavedOfflineResource(
            mimeType: mime.lowercased(),
            textEncoding: response.textEncodingName,
            bytes: operation.bytes
        )
    }

    func urlSession(
        _: URLSession,
        dataTask _: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200,
              let url = response.url, policy.allows(url)
        else { failure = OfflineGameError.invalidResponse
            completionHandler(.cancel)
            return
        }
        guard response.expectedContentLength <= remainingBytes else {
            failure = OfflineGameError.tooLarge
            completionHandler(.cancel)
            return
        }
        self.response = response
        completionHandler(.allow)
    }

    func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard bytes + Int64(data.count) <= remainingBytes else {
            failure = OfflineGameError.tooLarge
            dataTask.cancel()
            return
        }
        do { try output.write(contentsOf: data)
            bytes += Int64(data.count)
        } catch { failure = error
            dataTask.cancel()
        }
    }

    func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
        if failure == nil {
            failure = error
        }
        completed.signal()
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        redirects += 1
        guard redirects <= 8, let url = request.url, policy.allows(url) else {
            failure = OfflineGameError.invalidResponse
            completionHandler(nil)
            return
        }
        var clean = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        clean.httpShouldHandleCookies = false
        completionHandler(clean)
    }

    func urlSession(
        _: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completionHandler(
            challenge.protectionSpace
                .authenticationMethod == NSURLAuthenticationMethodServerTrust ?
                .performDefaultHandling : .cancelAuthenticationChallenge,
            nil
        )
    }
}
