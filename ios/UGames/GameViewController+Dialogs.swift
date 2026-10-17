import UIKit
import WebKit

extension GameViewController {
    func webView(
        _ parent: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for action: WKNavigationAction,
        windowFeatures _: WKWindowFeatures
    ) -> WKWebView? {
        guard offlineGame == nil, !isOfflineCatalog,
              connectivity.status != .offline else { return nil }
        guard let url = action.request.url, GameNavigationPolicy.allows(url) else { return nil }
        let child = ProtectedWebViewFactory.makePopup(configuration: configuration, parent: parent)
        let controller = GameViewController(
            preparedView: child,
            offlineStore: offlineStore,
            connectivity: connectivity
        )
        navigationController?.pushViewController(controller, animated: true)
        return child
    }

    func webViewDidClose(_: WKWebView) {
        navigationController?.popViewController(animated: true)
    }

    func webView(
        _: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame _: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.overrideUserInterfaceStyle = .dark
        alert.view.tintColor = UGamesTheme.mint
        alert.addAction(UIAlertAction(title: "ОК", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(
        _: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame _: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.overrideUserInterfaceStyle = .dark
        alert.view.tintColor = UGamesTheme.mint
        alert
            .addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in
                completionHandler(false)
            })
        alert
            .addAction(UIAlertAction(title: "ОК", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    func webView(
        _: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame _: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.overrideUserInterfaceStyle = .dark
        alert.view.tintColor = UGamesTheme.mint
        alert.addTextField {
            $0.text = defaultText
            $0.textColor = UGamesTheme.text
            $0.backgroundColor = UGamesTheme.surface
            $0.tintColor = UGamesTheme.mint
        }
        alert
            .addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in
                completionHandler(nil)
            })
        alert
            .addAction(UIAlertAction(title: "ОК", style: .default) { _ in
                completionHandler(alert.textFields?.first?.text)
            })
        present(alert, animated: true)
    }
}
