import CryptoKit
import Foundation
import UIKit
import WebKit

enum OfflineGameError: LocalizedError {
    case invalidReport, unsupportedGame, gameNotReady, tooLarge, invalidResponse, missingResource

    var errorDescription: String? {
        switch self {
        case .invalidReport: return "Не удалось получить данные игры. Открой игру ещё раз."
        case .unsupportedGame: return "Эту игру пока нельзя сохранить для игры без интернета."
        case .gameNotReady: return "Дождись загрузки игры и попробуй снова."
        case .tooLarge: return "Игра превышает доступное место в кэше."
        case .invalidResponse: return "Не удалось загрузить все файлы. Предыдущая копия сохранена."
        case .missingResource: return "Этот файл ещё не загружен. Открой игру с интернетом."
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
    let store: OfflineGameStore
    let connectivity: OfflineConnectivity
    var visitID = UUID()
    var scheduled: DispatchWorkItem?
    var saving = false
    var active = true
    var attemptedResources: Set<String>?
    var lastAttempt = Date.distantPast

    init(game: SavedOfflineGame?, store: OfflineGameStore, connectivity: OfflineConnectivity) {
        self.game = game
        self.store = store
        self.connectivity = connectivity
    }

    deinit { scheduled?.cancel() }
}

final class OfflineGameReportReceiver: NSObject, WKScriptMessageHandler {
    static let shared = OfflineGameReportReceiver()
    static let updated = Notification.Name("UGamesOfflineReportUpdated")
    private let states = NSMapTable<WKWebView, OfflineReportState>.weakToStrongObjects()

    func register(
        _ view: WKWebView,
        game: SavedOfflineGame? = nil,
        store: OfflineGameStore = .shared,
        connectivity: OfflineConnectivity = .shared
    ) {
        states.setObject(
            OfflineReportState(game: game, store: store, connectivity: connectivity),
            forKey: view
        )
    }

    func report(for view: WKWebView) -> OfflineGameReport? {
        states.object(forKey: view)?.report
    }

    func unregister(_ view: WKWebView) {
        states.object(forKey: view)?.scheduled?.cancel()
        states.removeObject(forKey: view)
    }

    func setActive(_ active: Bool, in view: WKWebView) {
        guard let state = states.object(forKey: view) else { return }
        state.active = active
        if !active {
            state.scheduled?.cancel()
        }
    }

    func noteNavigation(to url: URL, in view: WKWebView, mainFrame: Bool) {
        guard let state = states.object(forKey: view), state.game == nil,
              let old = state.report else { return }
        if mainFrame || (OfflineResourcePolicy.isGameURL(url) &&
            OfflineResourcePolicy.canonical(url) != OfflineResourcePolicy.canonical(old.url))
        {
            state.scheduled?.cancel()
            state.report = nil
            state.visitID = UUID()
            state.attemptedResources = nil
            NotificationCenter.default.post(name: Self.updated, object: view)
        }
    }

    /// Wait for a final storage read before replacing an offline WebView's context.
    func captureProgress(in view: WKWebView, completion: @escaping () -> Void) {
        guard let state = states.object(forKey: view), let game = state.game else {
            view
                .evaluateJavaScript(
                    "window.__UGamesOfflineCapture && window.__UGamesOfflineCapture()"
                ) { _, _ in
                    completion()
                }
            return
        }
        view.evaluateJavaScript("""
        (()=>{try{if(window.__UGamesOfflineCapture)window.__UGamesOfflineCapture();const values={};for(let i=0;i<localStorage.length;i++){const key=localStorage.key(i);values[key]=localStorage.getItem(key);}return JSON.stringify(values);}catch(_){return null;}})()
        """) { [view] value, _ in
            withExtendedLifetime(view) {}
            guard let string = value as? String, string.utf8.count <= 2 * 1024 * 1024,
                  let data = string.data(using: .utf8),
                  let storage = try? JSONDecoder().decode([String: String].self, from: data)
            else { completion()
                return
            }
            state.store.updateStorage(storage, for: game.id) { _ in completion() }
        }
    }

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let view = message.webView, let state = states.object(forKey: view) else { return }
        let origin = OfflineReportOrigin(message.frameInfo.securityOrigin)
        if state.game == nil, let body = message.body as? String, body.utf8.count <= 8192,
           let data = body.data(using: .utf8),
           let visit = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           visit["version"] as? Int == 1, visit["type"] as? String == "visit",
           let value = visit["url"] as? String, let url = URL(string: value),
           OfflineResourcePolicy.isGameURL(url), origin.scheme == "https",
           origin.host == url.host?.lowercased(), origin.port == 0 || origin.port == 443
        {
            state.scheduled?.cancel()
            state.report = nil
            state.visitID = UUID()
            state.attemptedResources = nil
            return
        }
        if state.game == nil, let metadata = try? OfflineCatalogMetadata.parse(
            message.body, origin: origin, frameURL: message.frameInfo.request.url,
            mainFrame: message.frameInfo.isMainFrame
        ) {
            let store = state.store
            store.recordCatalog(metadata) { [weak self] changed in
                guard changed, let self = self else { return }
                for key in self.states.keyEnumerator().allObjects {
                    guard let target = key as? WKWebView,
                          let candidate = self.states.object(forKey: target),
                          candidate.store === store, candidate.game == nil,
                          let report = candidate.report,
                          OfflineCatalogMetadata.gameID(for: report.url) == metadata.gameId
                    else { continue }
                    candidate.attemptedResources = nil
                    self.scheduleCache(in: target, state: candidate)
                }
            }
            return
        }
        guard state.game == nil || message.frameInfo.isMainFrame,
              let report = try? OfflineGameReport.parse(
                  message.body,
                  origin: origin,
                  offlineGame: state.game
              ) else { return }
        state.report = report
        if let game = state.game {
            state.store.updateStorage(report.storage, for: game.id)
        } else if report.ready, state.active, state.connectivity.status != .offline,
                  UIApplication.shared.applicationState != .background
        {
            state.store.touch(OfflineResourcePolicy.key(report.url))
            state.store.updateStorage(report.storage, for: OfflineResourcePolicy.key(report.url))
            scheduleCache(in: view, state: state)
        }
        NotificationCenter.default.post(name: Self.updated, object: view)
    }

    private func scheduleCache(in view: WKWebView, state: OfflineReportState) {
        guard state.active, !state.saving, let report = state.report, report.ready else { return }
        let resources = Set(([report.url] + report.resources)
            .map { OfflineResourcePolicy.canonical($0).absoluteString })
        guard state.attemptedResources != resources || Date()
            .timeIntervalSince(state.lastAttempt) >= 30 else { return }
        state.scheduled?.cancel()
        let visitID = state.visitID
        let work = DispatchWorkItem { [weak self, weak view, weak state] in
            guard let self = self, let view = view, let state = state,
                  self.states.object(forKey: view) === state, state.visitID == visitID,
                  state.active,
                  state.connectivity.status != .offline,
                  UIApplication.shared.applicationState != .background,
                  let report = state.report, report.ready else { return }
            state.saving = true
            state.attemptedResources = resources
            state.lastAttempt = Date()
            typealias Completion = (Result<SavedOfflineGame, Error>) -> Void
            let finished: Completion = { [weak self, weak view, weak state] result in
                guard let self = self, let view = view, let state = state else { return }
                state.saving = false
                if case .success = result {
                    state.lastAttempt = .distantFuture
                }
                self.scheduleCache(in: view, state: state)
            }
            state.store.save(report, visitID: visitID, playedAt: Date(), completion: finished)
        }
        state.scheduled = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }
}
