@testable import UGames
import WebKit
import XCTest

private final class FixtureSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_: WKWebView, start task: WKURLSchemeTask) {
        let name = task.request.url!.lastPathComponent
        guard ["sdk-lifecycle.html", "frame.html"].contains(name),
              let file = Bundle(for: ProtectedWebViewTests.self).url(
                  forResource: name,
                  withExtension: nil,
                  subdirectory: "fixtures"
              ),
              let data = try? Data(contentsOf: file),
              let html = String(data: data, encoding: .utf8)
        else {
            task.didFailWithError(NSError(domain: "Fixture", code: 404))
            return
        }
        let bytes = html.replacingOccurrences(
            of: "src=\"frame.html\"",
            with: "src=\"ugames-fixture://child/frame.html\""
        ).data(using: .utf8)!
        task.didReceive(URLResponse(
            url: task.request.url!,
            mimeType: "text/html",
            expectedContentLength: bytes.count,
            textEncodingName: "utf-8"
        ))
        task.didReceive(bytes)
        task.didFinish()
    }

    func webView(_: WKWebView, stop _: WKURLSchemeTask) {}
}

private final class NavigationOutcome: NSObject, WKNavigationDelegate {
    let completed: (Error?) -> Void
    init(completed: @escaping (Error?) -> Void) {
        self.completed = completed
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        completed(nil)
    }

    func webView(
        _: WKWebView,
        didFailProvisionalNavigation _: WKNavigation!,
        withError error: Error
    ) {
        completed(error)
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        completed(error)
    }
}

@MainActor
final class ProtectedWebViewTests: WebViewTestCase {
    func testSafeAreaBackgroundFollowsPageAndResetsForErrors() throws {
        let webView = try makeView()
        let controller = GameViewController(preparedView: webView)
        controller.loadViewIfNeeded()
        func assertBackground(red: CGFloat, green: CGFloat, blue: CGFloat) throws {
            let color = try XCTUnwrap(controller.view.backgroundColor)
            var actualRed: CGFloat = 0
            var actualGreen: CGFloat = 0
            var actualBlue: CGFloat = 0
            var alpha: CGFloat = 0
            XCTAssertTrue(color.getRed(
                &actualRed,
                green: &actualGreen,
                blue: &actualBlue,
                alpha: &alpha
            ))
            XCTAssertEqual(actualRed, red, accuracy: 1 / 255)
            XCTAssertEqual(actualGreen, green, accuracy: 1 / 255)
            XCTAssertEqual(actualBlue, blue, accuracy: 1 / 255)
            XCTAssertEqual(alpha, 1, accuracy: 0.01)
        }
        let dark = UIColor(red: 0.12, green: 0.15, blue: 0.18, alpha: 1)
        webView.underPageBackgroundColor = dark
        try assertBackground(red: 0.12, green: 0.15, blue: 0.18)

        webView.underPageBackgroundColor = .white
        try assertBackground(red: 1, green: 1, blue: 1)

        webView.underPageBackgroundColor = dark
        controller.showProtectionError()
        XCTAssertEqual(controller.view.backgroundColor, UGamesTheme.background)
        webView.underPageBackgroundColor = .red
        XCTAssertEqual(controller.view.backgroundColor, UGamesTheme.background)
    }

    func testFullscreenShellKeepsAnUnobtrusiveMenuAccessible() throws {
        let webView = try makeView()
        let controller = GameViewController(preparedView: webView)
        let navigation = UINavigationController(rootViewController: controller)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        navigation.view.layoutIfNeeded()

        XCTAssertTrue(navigation.isNavigationBarHidden)
        XCTAssertTrue(controller.prefersStatusBarHidden)
        XCTAssertEqual(webView.frame, controller.view.safeAreaLayoutGuide.layoutFrame)
        let menu = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? UIButton }.first)
        XCTAssertEqual(menu.accessibilityIdentifier, "ugames.menu")
        XCTAssertEqual(menu.bounds.size, CGSize(width: 44, height: 44))
        XCTAssertEqual(menu.menu?.children.count, 3)
        controller.showProtectionError()
        XCTAssertFalse(menu.isHidden)
        XCTAssertTrue(controller.view.hitTest(menu.center, with: nil)?
            .isDescendant(of: menu) == true)
        webView.isHidden = false
        XCTAssertTrue(controller.view.hitTest(CGPoint(x: 100, y: 400), with: nil)?
            .isDescendant(of: webView) == true)
    }

    private func fixtureResult(_ view: WKWebView) throws -> [String: Any] {
        try waitForJavaScript("""
        Boolean(window.fixtureResult && window.fixtureResult.closes === 1 &&
          window.fixtureResult.portalAdsHidden !== undefined &&
          window.fixtureResult.child && window.fixtureResult.child.closes === 1)
        """, in: view)
        let text = try XCTUnwrap(
            evaluateJavaScript("JSON.stringify(window.fixtureResult)", in: view) as? String
        )
        let data = try XCTUnwrap(text.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testAdapterRunsBeforePageSDKInAllFrames() throws {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(FixtureSchemeHandler(), forURLScheme: "ugames-fixture")
        let view = try makeView(configuration: configuration)
        defer { view.stopLoading() }
        try view
            .load(
                URLRequest(
                    url: XCTUnwrap(URL(string: "ugames-fixture://main/sdk-lifecycle.html"))
                )
            )
        let result = try fixtureResult(view)
        XCTAssertEqual(result["early"] as? Bool, true)
        XCTAssertEqual(result["original"] as? Int, 0)
        XCTAssertEqual(result["rewards"] as? Int, 1)
        XCTAssertEqual(result["fullscreen"] as? Int, 1)
        XCTAssertEqual(result["shadowClosed"] as? Int, 1)
        XCTAssertEqual(result["shadowMode"] as? String, "closed")
        XCTAssertEqual(result["innocentClosed"] as? Int, 0)
        XCTAssertEqual(result["obfuscatedClosed"] as? Int, 1)
        XCTAssertEqual(result["saltedBannerHidden"] as? Bool, true)
        XCTAssertEqual(result["portalAdsHidden"] as? Bool, true)
        XCTAssertEqual(result["portalControlsVisible"] as? Bool, true)
        XCTAssertEqual(result["catalogShadowAdHidden"] as? Bool, true)
        let child = try XCTUnwrap(result["child"] as? [String: Any])
        XCTAssertEqual(child["early"] as? Bool, true)
        XCTAssertEqual(child["original"] as? Int, 0)
        XCTAssertEqual(child["rewards"] as? Int, 1)
    }

    func testPopupKeepsAdapterAndDataStore() throws {
        let original = try makeView()
        let popupConfiguration = WKWebViewConfiguration()
        popupConfiguration.websiteDataStore = original.configuration.websiteDataStore
        popupConfiguration.processPool = original.configuration.processPool
        let child = ProtectedWebViewFactory.makePopup(
            configuration: popupConfiguration,
            parent: original
        )
        defer {
            original.stopLoading()
            child.stopLoading()
        }
        XCTAssertTrue(child.configuration.websiteDataStore === original.configuration
            .websiteDataStore)
        XCTAssertTrue(child.configuration.websiteDataStore.isPersistent)
        child.loadHTMLString(
            "<script>window.earlyProtection = !!window.__UGamesAdapter;</script>",
            baseURL: URL(string: "https://yandex.ru/games/")
        )
        try waitForJavaScript(
            "window.earlyProtection === true && document.readyState === 'complete'",
            in: child
        )
    }

    func testContentRulesInstalledBeforeNavigation() throws {
        let view = try makeView()
        defer { view.stopLoading() }
        let blocked = expectation(description: "Advertising URL blocked on the first navigation")
        let delegate = NavigationOutcome { error in
            XCTAssertNotNil(error)
            XCTAssertTrue(
                error?.localizedDescription.lowercased().contains("content blocker") == true,
                String(describing: error)
            )
            blocked.fulfill()
        }
        view.navigationDelegate = delegate
        try view
            .load(
                URLRequest(
                    url: XCTUnwrap(URL(string: "https://yandex.ru/ads/system/context.js"))
                )
            )
        try waitForWebView(blocked)
    }

    func testImmutableSDKShowsAnErrorInsteadOfReturningUnsafeMethods() throws {
        let view = try makeView()
        defer { view.stopLoading() }
        let controller = GameViewController(preparedView: view)
        controller.loadViewIfNeeded()
        view.loadHTMLString("""
        <script>
        setTimeout(function() {
          window.YaGames = {init:function(){return Promise.resolve({adv:Object.freeze({showFullscreenAdv:function(){}})});}};
          YaGames.init().catch(function(){});
        }, 20);
        </script>
        """, baseURL: URL(string: "https://yandex.ru/games/"))
        try waitUntil("Native shell hides unsupported game") {
            view.isHidden
        }
        XCTAssertTrue(view.isHidden)
    }

    func testFailedNavigationRetainsRetryTargetInRootAndPopup() throws {
        for popup in [false, true] {
            let controller = try popup ? GameViewController(preparedView: makeView()) :
                GameViewController()
            controller.loadViewIfNeeded()
            var surface: WKWebView?
            try waitUntil("Controller attaches its protected view") {
                surface = controller.view.subviews.compactMap { $0 as? WKWebView }.first
                return surface != nil
            }
            let webView = try XCTUnwrap(surface)
            defer { webView.stopLoading() }
            webView.stopLoading()
            let target =
                try XCTUnwrap(URL(string: "https://yandex.ru/games/app/failed-game?popup=\(popup)"))
            webView.loadHTMLString("<p>Game fixture</p>", baseURL: target)
            try waitUntil("Allowed game navigation sets the retry target") {
                webView.url == target && !webView.isLoading
            }
            controller.webView(
                webView,
                didFailProvisionalNavigation: nil,
                withError: NSError(
                    domain: NSURLErrorDomain,
                    code: NSURLErrorCannotConnectToHost
                )
            )
            XCTAssertTrue(webView.isHidden)
            XCTAssertEqual(controller.retryURL, target)
            let panel = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? UIStackView }
                .first)
            let retryButton = try XCTUnwrap(panel.arrangedSubviews.compactMap { $0 as? UIButton }
                .first)
            retryButton.sendActions(for: .touchUpInside)
            XCTAssertFalse(webView.isHidden)
            XCTAssertEqual(webView.url, target)
            webView.stopLoading()
        }
    }

    func testProcessTerminationDoesNotReplayReward() throws {
        let view = try makeView()
        defer { view.stopLoading() }
        let controller = GameViewController(preparedView: view)
        controller.loadViewIfNeeded()
        view.loadHTMLString("""
        <script>
        window.rewards = 0;
        window.YaGames = {init:function(){return Promise.resolve({adv:{showRewardedVideo:function(){}}});}};
        YaGames.init().then(function(sdk){sdk.adv.showRewardedVideo({callbacks:{onRewarded:function(){window.rewards++;}}});});
        </script>
        """, baseURL: URL(string: "https://yandex.ru/games/"))
        try waitForJavaScript("window.rewards === 1", in: view)
        controller.webViewWebContentProcessDidTerminate(view)
        XCTAssertTrue(view.isHidden)
        XCTAssertEqual(try evaluateJavaScript("window.rewards", in: view) as? Int, 1)
    }
}
