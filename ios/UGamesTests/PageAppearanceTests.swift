@testable import UGames
import WebKit
import XCTest

@MainActor
final class PageAppearanceTests: WebViewTestCase {
    func testSafeAreaFollowsDocumentBackgroundAndLiveThemeChanges() throws {
        let webView = try makeView()
        defer { webView.stopLoading() }
        let controller = GameViewController(preparedView: webView)
        controller.loadViewIfNeeded()
        webView.loadHTMLString("""
        <html style="background:#eeeeee"><body style="background:#171520">
        <iframe srcdoc="<body style='background:red'></body>"></iframe>
        <script>window.appearanceReady = true;</script>
        </body></html>
        """, baseURL: URL(string: "https://passport.yandex.ru/pwl-yandex/auth/add"))
        try waitForJavaScript(
            "window.appearanceReady === true && document.readyState === 'complete'",
            in: webView
        )
        func components(_ color: UIColor?) -> [CGFloat] {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            guard color?.getRed(&red, green: &green, blue: &blue, alpha: &alpha) == true
            else { return [] }
            return [red, green, blue, alpha]
        }
        func waitForBackground(_ expected: UIColor) throws {
            func matches(_ color: UIColor?) -> Bool {
                let actual = components(color)
                return actual.count == 4 && zip(actual, components(expected))
                    .allSatisfy { abs($0 - $1) < 1 / 255 }
            }
            try waitUntil("Safe area and scroll view match the document background") {
                matches(controller.view.backgroundColor) &&
                    matches(webView.scrollView.backgroundColor)
            }
            XCTAssertTrue(matches(controller.view.backgroundColor))
            XCTAssertTrue(matches(webView.scrollView.backgroundColor))
        }
        try waitForBackground(UIColor(red: 23 / 255, green: 21 / 255, blue: 32 / 255, alpha: 1))
        try evaluateJavaScript("document.body.style.backgroundColor = '#fafafa'", in: webView)
        try waitForBackground(UIColor(red: 250 / 255, green: 250 / 255, blue: 250 / 255, alpha: 1))
        controller.showProtectionError()
        try evaluateJavaScript("document.body.style.backgroundColor = 'red'", in: webView)
        XCTAssertEqual(controller.view.backgroundColor, UGamesTheme.background)
    }
}
