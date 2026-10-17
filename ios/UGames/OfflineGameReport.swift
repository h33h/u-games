import CryptoKit
import Foundation
import WebKit

enum OfflineGameError: LocalizedError {
    case invalidReport, unsupportedGame, gameNotReady, tooLarge, invalidResponse, missingResource

    var errorDescription: String? {
        switch self {
        case .invalidReport: return "Не удалось получить данные игры. Открой игру ещё раз."
        case .unsupportedGame: return "Эту игру пока нельзя сохранить для игры без интернета."
        case .gameNotReady: return "Дождись загрузки игры и попробуй снова."
        case .tooLarge: return "Игра превышает лимит сохранения: 512 МБ или 4096 файлов."
        case .invalidResponse: return "Не удалось загрузить все файлы. Предыдущая копия сохранена."
        case .missingResource: return "Этот файл ещё не сохранён. Открой игру с интернетом и сохрани её снова."
        }
    }
}

struct OfflineReportOrigin {
    let scheme: String
    let host: String
    let port: Int

    init(scheme: String, host: String, port: Int) {
        self.scheme = scheme
        self.host = host.lowercased()
        self.port = port
    }

    init(_ origin: WKSecurityOrigin) {
        self.init(scheme: origin.protocol, host: origin.host, port: origin.port)
    }
}

/// Environment values are opaque SDK data, never executable native instructions.
enum OfflineJSONValue: Codable {
    case string(String), number(Double), bool(Bool), object([String: OfflineJSONValue]),
         array([OfflineJSONValue]), null

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() {
            self = .null
        } else if let bool = try? value.decode(Bool.self) {
            self = .bool(bool)
        } else if let string = try? value.decode(String.self) {
            self = .string(string)
        } else if let number = try? value.decode(Double.self) {
            self = .number(number)
        } else if let object = try? value
            .decode([String: OfflineJSONValue].self)
        {
            self = .object(object)
        } else {
            self = try .array(value.decode([OfflineJSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case let .string(string): try value.encode(string)
        case let .number(number): try value.encode(number)
        case let .bool(bool): try value.encode(bool)
        case let .object(object): try value.encode(object)
        case let .array(array): try value.encode(array)
        case .null: try value.encodeNil()
        }
    }
}

struct OfflineGameReport: Decodable {
    let version: Int
    let url: URL
    let title: String
    let resources: [URL]
    let storage: [String: String]
    let environment: [String: OfflineJSONValue]?
    let ready: Bool

    static func parse(
        _ body: Any,
        origin: OfflineReportOrigin,
        offlineGame: SavedOfflineGame? = nil
    ) throws -> OfflineGameReport {
        guard let body = body as? String, body.utf8.count <= 2 * 1024 * 1024,
              let bytes = body.data(using: .utf8),
              let report = try? JSONDecoder().decode(Self.self, from: bytes),
              report.version == 1, report.resources.count <= 4096,
              report.title.utf8.count <= 4096,
              OfflineResourcePolicy.isGameURL(report.url),
              origin.host == report.url.host?.lowercased(),
              origin.port == 0 || origin.port == 443
        else { throw OfflineGameError.invalidReport }
        if let offlineGame = offlineGame {
            guard origin.scheme == OfflineGameStore.scheme,
                  OfflineResourcePolicy.canonical(report.url) == OfflineResourcePolicy
                  .canonical(offlineGame.url)
            else { throw OfflineGameError.invalidReport }
        } else {
            guard origin.scheme == "https" else { throw OfflineGameError.invalidReport }
        }
        return report
    }
}

struct OfflineResourcePolicy {
    private let blockedPatterns: [NSRegularExpression]

    init(bundle: Bundle = .main) {
        let rules = bundle.url(forResource: "content-rules", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []
        blockedPatterns = rules.compactMap { rule in
            guard let action = rule["action"] as? [String: Any],
                  action["type"] as? String == "block",
                  let trigger = rule["trigger"] as? [String: Any],
                  let pattern = trigger["url-filter"] as? String
            else { return nil }
            return try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        }
    }

    static func isGameURL(_ url: URL) -> Bool {
        guard isHTTPS(url), let host = url.host?.lowercased() else { return false }
        return host.hasSuffix(".games.yandex.net") || host.hasSuffix(".games.s3.yandex.net")
    }

    static func isHTTPS(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host != nil && url.user == nil && url
            .password == nil && (url.port == nil || url.port == 443)
    }

    static func canonical(_ url: URL) -> URL {
        guard var value = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        value.scheme = value.scheme?.lowercased()
        value.host = value.host?.lowercased()
        value.fragment = nil
        if value.port == 443 {
            value.port = nil
        }
        return value.url ?? url
    }

    static func key(_ url: URL) -> String {
        SHA256.hash(data: Data(canonical(url).absoluteString.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    static func isSDK(_ url: URL) -> Bool {
        url.path.lowercased()
            .range(of: "(^|/)sdk([.]js($|/)|/|$)", options: .regularExpression) != nil ||
            (url.host == "yandex.ru" && url.path.hasPrefix("/games/sdk/"))
    }

    func allows(_ url: URL) -> Bool {
        guard Self.isHTTPS(url), !Self.isSDK(url), let host = url.host?.lowercased(),
              Self.isGameURL(url) || host == "yastatic.net" || host.hasSuffix(".yastatic.net")
        else { return false }
        // Only static game files: no account, analytics, purchase, or server API snapshots.
        let path = url.path.lowercased()
        if path.range(
            of: "(^|/)(api|auth|oauth|login|logout|passport|account|payments?|billing|analytics|telemetry|metrics)(/|$)",
            options: .regularExpression
        ) != nil {
            return false
        }
        if let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           query.contains(where: { [
               "token",
               "access_token",
               "auth",
               "authorization",
               "session",
               "sessionid",
               "password",
           ].contains($0.name.lowercased()) })
        {
            return false
        }
        let value = url.absoluteString
        return !blockedPatterns.contains { $0.firstMatch(
            in: value,
            range: NSRange(value.startIndex..., in: value)
        ) != nil }
    }
}

private final class OfflineReportState: NSObject {
    var report: OfflineGameReport?
    let game: SavedOfflineGame?
    let store: OfflineGameStore?

    init(game: SavedOfflineGame? = nil, store: OfflineGameStore? = nil) {
        self.game = game
        self.store = store
    }
}

final class OfflineGameReportReceiver: NSObject, WKScriptMessageHandler {
    static let shared = OfflineGameReportReceiver()
    static let updated = Notification.Name("UGamesOfflineReportUpdated")
    private let states = NSMapTable<WKWebView, OfflineReportState>.weakToStrongObjects()

    func register(
        _ view: WKWebView,
        game: SavedOfflineGame? = nil,
        store: OfflineGameStore? = nil
    ) {
        states.setObject(OfflineReportState(game: game, store: store), forKey: view)
    }

    func report(for view: WKWebView) -> OfflineGameReport? {
        states.object(forKey: view)?.report
    }

    func unregister(_ view: WKWebView) {
        states.removeObject(forKey: view)
    }

    func noteNavigation(to url: URL, in view: WKWebView, mainFrame: Bool) {
        guard let state = states.object(forKey: view), state.game == nil,
              let old = state.report else { return }
        if mainFrame ||
            (OfflineResourcePolicy.isGameURL(url) && OfflineResourcePolicy
                .canonical(url) != OfflineResourcePolicy.canonical(old.url))
        {
            state.report = nil
            NotificationCenter.default.post(name: Self.updated, object: view)
        }
    }

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let view = message.webView, let state = states.object(forKey: view),
              state.game == nil || message.frameInfo.isMainFrame,
              let report = try? OfflineGameReport.parse(
                  message.body,
                  origin: OfflineReportOrigin(message.frameInfo.securityOrigin),
                  offlineGame: state.game
              )
        else { return }
        state.report = report
        if let game = state.game {
            state.store?.updateStorage(report.storage, for: game.id)
        }
        NotificationCenter.default.post(name: Self.updated, object: view)
    }
}
