@testable import UGames
import WebKit
import XCTest

@MainActor
final class PageAppearanceTests: XCTestCase {
    func testSafeAreaFollowsDocumentBackgroundAndLiveThemeChanges() throws {
        let ready = expectation(description: "Protected WebView is ready")
        var result: Result<WKWebView, Error>?
        ProtectedWebViewFactory.make { value in
            result = value
            ready.fulfill()
        }
        wait(for: [ready], timeout: 15)
        let webView = try XCTUnwrap(result).get()
        let controller = GameViewController(preparedView: webView)
        controller.loadViewIfNeeded()
        webView.loadHTMLString("""
        <html style="background:#eeeeee"><body style="background:#171520">
        <iframe srcdoc="<body style='background:red'></body>"></iframe>
        <script>window.appearanceReady = true;</script>
        </body></html>
        """, baseURL: URL(string: "https://passport.yandex.ru/pwl-yandex/auth/add"))
        let loaded = expectation(description: "Background fixture is loaded")
        let loadDeadline = Date().addingTimeInterval(5)
        func waitForDocument() {
            webView
                .evaluateJavaScript(
                    "window.appearanceReady === true && document.readyState === 'complete'"
                ) { value, _ in
                    if value as? Bool == true {
                        loaded.fulfill()
                    } else if Date() < loadDeadline {
                        DispatchQueue.main.asyncAfter(
                            deadline: .now() + 0.05,
                            execute: waitForDocument
                        )
                    }
                }
        }
        waitForDocument()
        wait(for: [loaded], timeout: 6)
        func components(_ color: UIColor?) -> [CGFloat] {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            guard color?.getRed(&red, green: &green, blue: &blue, alpha: &alpha) == true
            else { return [] }
            return [red, green, blue, alpha]
        }
        func waitForBackground(_ expected: UIColor) {
            let changed = expectation(description: "Safe area matches the document background")
            let deadline = Date().addingTimeInterval(5)
            func matches(_ color: UIColor?) -> Bool {
                let actual = components(color)
                return actual.count == 4 && zip(actual, components(expected))
                    .allSatisfy { abs($0 - $1) < 1 / 255 }
            }
            func poll() {
                if matches(controller.view.backgroundColor) || Date() >= deadline {
                    changed.fulfill()
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
                }
            }
            poll()
            wait(for: [changed], timeout: 6)
            XCTAssertTrue(matches(controller.view.backgroundColor))
            XCTAssertTrue(matches(webView.scrollView.backgroundColor))
        }
        waitForBackground(UIColor(red: 23 / 255, green: 21 / 255, blue: 32 / 255, alpha: 1))
        webView.evaluateJavaScript("document.body.style.backgroundColor = '#fafafa'")
        waitForBackground(UIColor(red: 250 / 255, green: 250 / 255, blue: 250 / 255, alpha: 1))
        controller.showProtectionError()
        webView.evaluateJavaScript("document.body.style.backgroundColor = 'red'")
        XCTAssertEqual(controller.view.backgroundColor, UGamesTheme.background)
    }
}
