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
        completion: @escaping (Result<WKWebView, Error>) -> Void
    ) {
        guard let scriptURL = Bundle.main.url(forResource: "ad-adapter", withExtension: "js"),
              let rulesURL = Bundle.main.url(forResource: "content-rules", withExtension: "json"),
              let script = try? String(contentsOf: scriptURL, encoding: .utf8),
              let rules = try? String(contentsOf: rulesURL, encoding: .utf8)
        else {
            completion(.failure(ProtectionSetupError.missingResources))
            return
        }
        let config = configuration ?? WKWebViewConfiguration()
        if configuration == nil {
            config.websiteDataStore = .default()
        }
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let controller = config.userContentController
        if !controller.userScripts.contains(where: { $0.source == script }) {
            controller.add(GameProtectionReceiver(), name: "ugamesProtection")
            controller.add(PageAppearanceReceiver(), name: "ugamesAppearance")
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
                    completion(.success(readyView(configuration: config)))
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

    static func makePopup(configuration: WKWebViewConfiguration, parent: WKWebView) -> WKWebView {
        // WKUIDelegate must return synchronously; inherit the already prepared controller.
        configuration.userContentController = parent.configuration.userContentController
        configuration.websiteDataStore = parent.configuration.websiteDataStore
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        return readyView(configuration: configuration)
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
