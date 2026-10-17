import CryptoKit
import UIKit
import WebKit

enum ProtectionSetupError: Error {
    case missingResources
}

private final class GameProtectionReceiver: NSObject, WKScriptMessageHandler {
    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.body as? String == "unsupported", let view = message.webView else { return }
        view.stopLoading()
        (view.navigationDelegate as? GameViewController)?.showProtectionError()
    }
}

private final class PageAppearanceReceiver: NSObject, WKScriptMessageHandler {
    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let value = message.body as? String,
              value.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil,
              let rgb = UInt32(value.dropFirst(), radix: 16), let view = message.webView
        else { return }
        let color = UIColor(
            red: CGFloat((rgb >> 16) & 255) / 255,
            green: CGFloat((rgb >> 8) & 255) / 255,
            blue: CGFloat(rgb & 255) / 255,
            alpha: 1
        )
        view.underPageBackgroundColor = color
        view.backgroundColor = color
        view.scrollView.backgroundColor = color
    }
}

enum ProtectedWebViewFactory {
    static func make(
        configuration: WKWebViewConfiguration? = nil,
        offlineGame: SavedOfflineGame? = nil,
        offlineCatalog: Bool = false,
        offlineStore: OfflineGameStore = .shared,
        connectivity: OfflineConnectivity = .shared,
        completion: @escaping (Result<WKWebView, Error>) -> Void
    ) {
        guard let scriptURL = Bundle.main.url(forResource: "ad-adapter", withExtension: "js"),
              let rulesURL = Bundle.main.url(forResource: "content-rules", withExtension: "json"),
              let script = try? String(contentsOf: scriptURL, encoding: .utf8),
              var rules = try? String(contentsOf: rulesURL, encoding: .utf8)
        else {
            completion(.failure(ProtectionSetupError.missingResources))
            return
        }
        let config = configuration ?? WKWebViewConfiguration()
        var currentOfflineGame: SavedOfflineGame?
        let currentOfflineCatalog = offlineCatalog && connectivity.status == .offline
        if connectivity.status == .offline, let game = offlineGame {
            do { (currentOfflineGame, rules) = try prepareOffline(
                config: config,
                game: game,
                store: offlineStore,
                connectivity: connectivity,
                rules: rules
            ) } catch { completion(.failure(error))
                return
            }
        } else if currentOfflineCatalog {
            do {
                config.websiteDataStore = .nonPersistent()
                config.setURLSchemeHandler(
                    OfflineCatalogSchemeHandler(store: offlineStore, connectivity: connectivity),
                    forURLScheme: OfflineGameStore.scheme
                )
                try config.userContentController.addUserScript(WKUserScript(
                    source: OfflineCatalog.configuration(store: offlineStore),
                    injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page
                ))
                rules = try blockingNetwork(in: rules)
            } catch { completion(.failure(error))
                return
            }
        } else if configuration == nil {
            config.websiteDataStore = .default()
        }
        if currentOfflineGame == nil, !currentOfflineCatalog {
            installPendingProgress(offlineStore.pendingProgress(), in: config.userContentController)
        }
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let controller = config.userContentController
        if !controller.userScripts.contains(where: { $0.source == script }) {
            controller.add(GameProtectionReceiver(), name: "ugamesProtection")
            controller.add(PageAppearanceReceiver(), name: "ugamesAppearance")
            controller.add(OfflineGameReportReceiver.shared, name: "ugamesOffline")
            if currentOfflineGame == nil, !currentOfflineCatalog {
                controller.addUserScript(WKUserScript(source: """
                if(location.protocol==='https:'&&/(\\.games\\.yandex\\.net|\\.games\\.s3\\.yandex\\.net)$/.test(location.hostname)){try{webkit.messageHandlers.ugamesOffline.postMessage(JSON.stringify({version:1,type:'visit',url:location.href}));}catch(_){}}
                """, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))
            }
            controller.addUserScript(WKUserScript(
                source: script,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: .page
            ))
        }
        let hash = SHA256.hash(data: Data(rules.utf8)).map { String(format: "%02x", $0) }.joined()
        let identifier = "ugames-" + hash
        let store = WKContentRuleListStore.default()!
        func finish(_ list: WKContentRuleList?, _ error: Error?) {
            DispatchQueue.main.async {
                if let list = list {
                    controller.add(list)
                    let view = readyView(configuration: config)
                    OfflineGameReportReceiver.shared.register(
                        view,
                        game: currentOfflineGame,
                        store: offlineStore,
                        connectivity: connectivity
                    )
                    completion(.success(view))
                } else {
                    completion(.failure(error ?? ProtectionSetupError.missingResources))
                }
            }
        }
        store.lookUpContentRuleList(forIdentifier: identifier) { cached, _ in
            if let cached = cached {
                finish(cached, nil)
            } else {
                store.compileContentRuleList(
                    forIdentifier: identifier,
                    encodedContentRuleList: rules,
                    completionHandler: finish
                )
            }
        }
    }

    private static func prepareOffline(
        config: WKWebViewConfiguration,
        game: SavedOfflineGame,
        store: OfflineGameStore,
        connectivity: OfflineConnectivity,
        rules: String
    ) throws -> (SavedOfflineGame, String) {
        let handler = try OfflineGameSchemeHandler(
            game: game,
            store: store,
            connectivity: connectivity
        )
        let game = handler.game
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(
            handler,
            forURLScheme: OfflineGameStore.scheme
        )
        struct RuntimeConfig: Encodable {
            let gameId: String
            let url: String
            let scheme: String
            let storage: [String: String]
            let environment: [String: OfflineJSONValue]?
        }
        let runtime = RuntimeConfig(
            gameId: game.id,
            url: game.url.absoluteString,
            scheme: OfflineGameStore.scheme + ":",
            storage: game.storage,
            environment: game.environment
        )
        let json = try JSONEncoder().encode(runtime)
        guard let source = String(data: json, encoding: .utf8)
        else { throw ProtectionSetupError.missingResources }
        config.userContentController.addUserScript(WKUserScript(
            source: "window.__UGamesOfflineConfig=" + source + ";",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .page
        ))
        return try (game, blockingNetwork(in: rules))
    }

    private static func blockingNetwork(in rules: String) throws -> String {
        guard var contentRules = try JSONSerialization
            .jsonObject(with: Data(rules.utf8)) as? [[String: Any]]
        else { throw ProtectionSetupError.missingResources }
        for pattern in ["^https?://", "^wss?://"] {
            contentRules.append([
                "trigger": ["url-filter": pattern, "url-filter-is-case-sensitive": false],
                "action": ["type": "block"],
            ])
        }
        let encoded = try JSONSerialization.data(withJSONObject: contentRules)
        guard let result = String(data: encoded, encoding: .utf8)
        else { throw ProtectionSetupError.missingResources }
        return result
    }

    static func makePopup(configuration: WKWebViewConfiguration, parent: WKWebView) -> WKWebView {
        // WKUIDelegate must return synchronously; inherit the already prepared controller.
        configuration.userContentController = parent.configuration.userContentController
        configuration.websiteDataStore = parent.configuration.websiteDataStore
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let view = readyView(configuration: configuration)
        OfflineGameReportReceiver.shared.register(view)
        return view
    }

    private static func readyView(configuration: WKWebViewConfiguration) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: configuration)
        let background = UGamesTheme.background
        view.underPageBackgroundColor = background
        view.backgroundColor = background
        view.scrollView.backgroundColor = background
        view.allowsBackForwardNavigationGestures = true
        #if DEBUG
        if #available(iOS 16.4, *) {
            view.isInspectable = true
        }
        #endif
        return view
    }
}
