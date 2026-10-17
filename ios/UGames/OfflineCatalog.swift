import Foundation
import WebKit

struct OfflineCatalogMetadata: Codable, Equatable {
    let version: Int
    let type: String
    let gameId: String
    let url: URL
    let title: String
    let cover: URL?

    static let rasterMIMEs: Set<String> = [
        "image/jpeg",
        "image/png",
        "image/webp",
        "image/avif",
        "image/gif",
    ]

    static func parse(
        _ body: Any,
        origin: OfflineReportOrigin,
        frameURL: URL?,
        mainFrame: Bool
    ) throws -> Self {
        guard mainFrame, origin.scheme == "https", origin.port == 0 || origin.port == 443,
              ["yandex.ru", "www.yandex.ru", "yandex.com", "www.yandex.com"].contains(origin.host),
              let frameURL = frameURL, OfflineResourcePolicy.isHTTPS(frameURL),
              frameURL.host?.lowercased() == origin.host,
              frameURL.path == "/games" || frameURL.path.hasPrefix("/games/"),
              let string = body as? String, string.utf8.count <= 16 * 1024,
              let data = string.data(using: .utf8),
              let value = try? JSONDecoder().decode(Self.self, from: data), value.isValid
        else { throw OfflineGameError.invalidReport }
        return value
    }

    var isValid: Bool {
        version == 1 && type == "catalog" &&
            gameId.range(of: "^[1-9][0-9]{0,19}$", options: .regularExpression) != nil &&
            OfflineResourcePolicy.isHTTPS(url) &&
            ["yandex.ru", "www.yandex.ru", "yandex.com", "www.yandex.com"]
            .contains(url.host?.lowercased() ?? "") &&
            ["/games/app/" + gameId, "/games/app/" + gameId + "/"].contains(url.path) &&
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.utf8
            .count <= 4096 &&
            (cover == nil || Self.allowsCover(cover!))
    }

    static func gameID(for url: URL) -> String? {
        guard OfflineResourcePolicy.isGameURL(url), let host = url.host,
              let match = host.range(
                  of: "^app-[1-9][0-9]{0,19}(?=[.])",
                  options: .regularExpression
              )
        else { return nil }
        return String(host[match].dropFirst(4))
    }

    static func allowsCover(_ url: URL) -> Bool {
        OfflineResourcePolicy.isHTTPS(url) &&
            ["avatars.mds.yandex.net", "avatars.mds.yandex.ru", "avatars.mds.yandex.com"]
            .contains(url.host?.lowercased() ?? "") &&
            (url.path.hasPrefix("/get-games/") || url.path.hasPrefix("/get-games-avatars/"))
    }
}

enum OfflineCatalog {
    static let url = URL(string: "ugames-offline://yandex.ru/games/")!
    static let onlineURL = URL(string: "https://yandex.ru/games/")!

    static func isDocument(_ url: URL) -> Bool {
        url.scheme == OfflineGameStore.scheme && url.host == "yandex.ru" &&
            url.user == nil && url.password == nil && url.port == nil &&
            ["/games", "/games/"].contains(url.path) && url.query == nil
    }

    static func configuration(store: OfflineGameStore) throws -> String {
        struct Entry: Encodable { let url: URL
            let title: String
            let cover: String?
        }
        struct Catalog: Encodable { let version = 1
            let games: [Entry]
        }
        let entries = ((try? store.games()) ?? []).map { game in
            Entry(
                url: game.url,
                title: game.title,
                cover: game.cover == nil ? nil :
                    "ugames-offline://yandex.ru/games/_covers/" + game.id
            )
        }
        let json = try JSONEncoder().encode(Catalog(games: entries))
        guard let source = String(data: json, encoding: .utf8)
        else { throw OfflineGameError.invalidReport }
        return "window.__UGamesCachedCatalog=" + source + ";"
    }
}

/// This handler is installed only on a local catalog WebView, never on an online context.
final class OfflineCatalogSchemeHandler: NSObject, WKURLSchemeHandler {
    private let store: OfflineGameStore
    private let connectivity: OfflineConnectivity
    private let queue = DispatchQueue(label: "dev.ugames.offline-catalog", qos: .userInitiated)
    private var active = Set<ObjectIdentifier>()

    init(store: OfflineGameStore, connectivity: OfflineConnectivity = .shared) {
        self.store = store
        self.connectivity = connectivity
    }

    func webView(_: WKWebView, start task: WKURLSchemeTask) {
        guard connectivity.status == .offline else { task.didFailWithError(URLError(.cancelled))
            return
        }
        let id = ObjectIdentifier(task)
        active.insert(id)
        queue.async {
            let result = Result<OfflineResourceResponse, Error> {
                guard let url = task.request.url,
                      ["GET", "HEAD"].contains(task.request.httpMethod ?? "GET")
                else { throw OfflineGameError.missingResource }
                if OfflineCatalog.isDocument(url),
                   let file = Bundle.main.url(
                       forResource: "offline-catalog",
                       withExtension: "html"
                   )
                {
                    return try OfflineResourceResponse(
                        data: Data(contentsOf: file),
                        mimeType: "text/html",
                        textEncoding: "utf-8"
                    )
                }
                guard url.scheme == OfflineGameStore.scheme, url.host == "yandex.ru",
                      url.port == nil, url.user == nil, url.password == nil, url.query == nil,
                      url.path.hasPrefix("/games/_covers/"),
                      url.pathComponents.count == 4 else { throw OfflineGameError.missingResource }
                return try self.store.coverResponse(for: url.lastPathComponent)
            }
            DispatchQueue.main.async {
                guard self.active.remove(id) != nil else { return }
                guard self.connectivity.status == .offline
                else { task.didFailWithError(URLError(.cancelled))
                    return
                }
                switch result {
                case let .success(resource):
                    guard let url = task.request.url, let response = HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: [
                            "Content-Type": resource
                                .mimeType + (resource.textEncoding.map { "; charset=" + $0 } ?? ""),
                            "Cache-Control": "no-store",
                            "Content-Security-Policy": "default-src 'none'; img-src ugames-offline: data:; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'none'; form-action 'none'",
                            "Content-Length": String(resource.data.count),
                        ]
                    ) else { task.didFailWithError(OfflineGameError.invalidResponse)
                        return
                    }
                    task.didReceive(response)
                    if task.request.httpMethod != "HEAD" {
                        task.didReceive(resource.data)
                    }
                    task.didFinish()
                case let .failure(error): task.didFailWithError(error)
                }
            }
        }
    }

    func webView(_: WKWebView, stop task: WKURLSchemeTask) {
        active.remove(ObjectIdentifier(task))
    }
}
