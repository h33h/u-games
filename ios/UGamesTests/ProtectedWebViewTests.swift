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

private final class PageCompletion: NSObject, WKNavigationDelegate {
    let loaded: (WKWebView) -> Void
    init(loaded: @escaping (WKWebView) -> Void) {
        self.loaded = loaded
    }

    func webView(_ view: WKWebView, didFinish _: WKNavigation!) {
        loaded(view)
    }
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
final class ProtectedWebViewTests: XCTestCase {
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
        XCTAssertEqual(controller.view.backgroundColor, .systemBackground)
        webView.underPageBackgroundColor = .red
        XCTAssertEqual(controller.view.backgroundColor, .systemBackground)
    }

    func testMenuRestoresPositionAndStaysReachableAfterRotation() throws {
        let suite = "FloatingMenuTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(0.25, forKey: "gameMenu.x")
        defaults.set(0.75, forKey: "gameMenu.y")
        let button = FloatingMenuButton(defaults: defaults)
        let portrait = CGRect(x: 0, y: 44, width: 390, height: 766)
        button.place(in: portrait)
        XCTAssertEqual(button.frame.minX, 90.5, accuracy: 0.01)
        XCTAssertEqual(button.frame.minY, 581.5, accuracy: 0.01)

        let landscape = CGRect(x: 44, y: 0, width: 756, height: 369)
        button.place(in: landscape)
        XCTAssertTrue(landscape.contains(button.frame))
        XCTAssertEqual(button.frame.minX, 226, accuracy: 0.01)
        XCTAssertEqual(button.frame.minY, 239.75, accuracy: 0.01)

        defaults.set(1.0, forKey: "gameMenu.x")
        button.restorePosition()
        button.place(in: portrait)
        XCTAssertEqual(button.frame.maxX, 382, accuracy: 0.01)
    }

    func testFullscreenShellKeepsOnlyMenuButtonAboveGame() throws {
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
        let menu = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? UIButton }
            .first { $0.accessibilityLabel == "Меню" })
        XCTAssertTrue(controller.view.safeAreaLayoutGuide.layoutFrame.contains(menu.frame))
        XCTAssertGreaterThanOrEqual(menu.bounds.width, 44)
        XCTAssertTrue(controller.view.hitTest(CGPoint(x: 100, y: 400), with: nil)?
            .isDescendant(of: webView) == true)

        controller.showProtectionError()
        controller.view.layoutIfNeeded()
        menu.center = CGPoint(x: controller.view.bounds.midX, y: controller.view.bounds.midY)
        XCTAssertTrue(controller.view.hitTest(menu.center, with: nil)?
            .isDescendant(of: menu) == true)
    }

    private func makeView(configuration: WKWebViewConfiguration? = nil) throws -> WKWebView {
        let ready = expectation(description: "Protected view ready")
        var result: Result<WKWebView, Error>?
        ProtectedWebViewFactory.make(configuration: configuration) { value in result = value
            ready.fulfill()
        }
        wait(for: [ready], timeout: 15)
        return try XCTUnwrap(result).get()
    }

    private func fixtureResult(_ view: WKWebView) throws -> [String: Any] {
        let ready = expectation(description: "Both frames finish without ads")
        var result: [String: Any]?
        let deadline = Date().addingTimeInterval(10)
        func poll() {
            view.evaluateJavaScript("JSON.stringify(window.fixtureResult || null)") { value, _ in
                if let text = value as? String, let data = text.data(using: .utf8),
                   let candidate = (try? JSONSerialization
                       .jsonObject(with: data)) as? [String: Any],
                   (candidate["closes"] as? Int) == 1,
                   ((candidate["child"] as? [String: Any])?["closes"] as? Int) == 1
                {
                    result = candidate
                    ready.fulfill()
                } else if Date() < deadline {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
                } else {
                    ready.fulfill()
                }
            }
        }
        poll()
        wait(for: [ready], timeout: 12)
        return try XCTUnwrap(result)
    }

    func testAdapterRunsBeforePageSDKInAllFrames() throws {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(FixtureSchemeHandler(), forURLScheme: "ugames-fixture")
        let view = try makeView(configuration: configuration)
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
        XCTAssertTrue(child.configuration.websiteDataStore === original.configuration
            .websiteDataStore)
        XCTAssertTrue(child.configuration.websiteDataStore.isPersistent)
        let done = expectation(description: "Popup script acts before SDK")
        let loaded = PageCompletion { child in
            child.evaluateJavaScript("window.earlyProtection") { value, error in
                XCTAssertNil(error)
                XCTAssertEqual(value as? Bool, true)
                done.fulfill()
            }
        }
        child.navigationDelegate = loaded
        child.loadHTMLString(
            "<script>window.earlyProtection = !!window.__UGamesAdapter;</script>",
            baseURL: URL(string: "https://fixture.ugames.test/")
        )
        wait(for: [done], timeout: 5)
    }

    func testContentRulesInstalledBeforeNavigation() throws {
        let view = try makeView()
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
        wait(for: [blocked], timeout: 10)
    }

    func testImmutableSDKShowsAnErrorInsteadOfReturningUnsafeMethods() throws {
        let view = try makeView()
        let controller = GameViewController(preparedView: view)
        controller.loadViewIfNeeded()
        view.loadHTMLString("""
        <script>
        setTimeout(function() {
          window.YaGames = {init:function(){return Promise.resolve({adv:Object.freeze({showFullscreenAdv:function(){}})});}};
          YaGames.init().catch(function(){});
        }, 20);
        </script>
        """, baseURL: URL(string: "https://fixture.ugames.test/"))
        let notified = expectation(description: "Native shell hides unsupported game")
        let deadline = Date().addingTimeInterval(5)
        func poll() {
            if view.isHidden {
                notified.fulfill()
            } else if Date() < deadline {
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 0.05,
                    execute: poll
                )
            } else {
                notified.fulfill()
            }
        }
        poll()
        wait(for: [notified], timeout: 6)
        XCTAssertTrue(view.isHidden)
    }

    func testFailedNavigationRetainsRetryTargetInRootAndPopup() throws {
        for popup in [false, true] {
            let controller = try popup ? GameViewController(preparedView: makeView()) :
                GameViewController()
            controller.loadViewIfNeeded()
            let ready = expectation(description: "Controller attaches its protected view")
            var surface: WKWebView?
            let readyDeadline = Date().addingTimeInterval(10)
            func findView() {
                surface = controller.view.subviews.compactMap { $0 as? WKWebView }.first
                if surface != nil || Date() >= readyDeadline {
                    ready.fulfill()
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: findView)
                }
            }
            findView()
            wait(for: [ready], timeout: 12)
            let webView = try XCTUnwrap(surface)
            webView.stopLoading()
            let target = try XCTUnwrap(URL(string: "http://127.0.0.1:1/failed-game?popup=\(popup)"))
            webView.load(URLRequest(url: target))
            let failed = expectation(description: "Local closed port shows the error panel")
            let deadline = Date().addingTimeInterval(8)
            func pollError() {
                if webView.isHidden || Date() >= deadline {
                    failed.fulfill()
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: pollError)
                }
            }
            pollError()
            wait(for: [failed], timeout: 10)
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
        let controller = GameViewController(preparedView: view)
        controller.loadViewIfNeeded()
        view.loadHTMLString("""
        <script>
        window.rewards = 0;
        window.YaGames = {init:function(){return Promise.resolve({adv:{showRewardedVideo:function(){}}});}};
        YaGames.init().then(function(sdk){sdk.adv.showRewardedVideo({callbacks:{onRewarded:function(){window.rewards++;}}});});
        </script>
        """, baseURL: URL(string: "https://fixture.ugames.test/"))
        let done = expectation(description: "Reward completed before process termination callback")
        let deadline = Date().addingTimeInterval(5)
        func poll() {
            view.evaluateJavaScript("window.rewards") { value, _ in
                if value as? Int == 1 {
                    controller.webViewWebContentProcessDidTerminate(view)
                    XCTAssertTrue(view.isHidden)
                    view.evaluateJavaScript("window.rewards") { value, _ in
                        XCTAssertEqual(value as? Int, 1)
                        done.fulfill()
                    }
                } else if Date() < deadline {
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + 0.05,
                        execute: poll
                    )
                } else {
                    XCTFail("Reward was not completed")
                    done.fulfill()
                }
            }
        }
        poll()
        wait(for: [done], timeout: 6)
    }
}
