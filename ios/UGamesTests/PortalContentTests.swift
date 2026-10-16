@testable import UGames
import WebKit
import XCTest

@MainActor
final class PortalContentTests: WebViewTestCase {
    func testScriptedExternalNavigationKeepsTheGameAndItsFrame() throws {
        let view = try makeView()
        defer { view.stopLoading() }
        let controller = GameViewController(preparedView: view)
        controller.loadViewIfNeeded()
        let home = try XCTUnwrap(URL(string: "https://yandex.ru/games/"))
        view.loadHTMLString(
            "<p id='game'>Game</p><iframe srcdoc=\"<p id='child'>Child</p>\"></iframe>",
            baseURL: home
        )
        try waitForJavaScript(
            "document.readyState === 'complete' && !!document.getElementById('game') && !!document.querySelector('iframe')?.contentDocument?.getElementById('child')",
            in: view
        )
        let done = expectation(description: "Native policy rejects scripted external navigation")
        view.callAsyncJavaScript("""
            document.querySelector('iframe').contentWindow.location.href = 'https://external.example/';
            window.location.href = 'https://external.example/';
            await new Promise(resolve => setTimeout(resolve, 500));
            return Boolean(document.getElementById('game') && document.querySelector('iframe').contentDocument.getElementById('child'));
        """, arguments: [:], in: nil, in: .page) { result in
            XCTAssertEqual(try? result.get() as? Bool, true)
            XCTAssertEqual(view.url, home)
            XCTAssertFalse(view.isLoading)
            XCTAssertFalse(view.isHidden)
            done.fulfill()
        }
        try waitForWebView(done)
    }

    func testPortalCleanupPreservesGamesAndRestoresReusedNavigation() throws {
        let webView = try makeView()
        defer { webView.stopLoading() }
        webView.loadHTMLString("""
        <input id="search" placeholder="Найти игру">
        <div id="site" class="page-description">О сайте</div>
        <a id="shop" href="/games/shop">Магазин</a>
        <a id="game" href="/games/app/123">Играть</a>
        """, baseURL: URL(string: "https://yandex.ru/games/"))
        try waitForJavaScript(
            "document.readyState === 'complete' && !!document.getElementById('game')",
            in: webView
        )
        let done = expectation(description: "Portal cleanup in WKWebView")
        webView.callAsyncJavaScript("""
              const hidden = (id) => getComputedStyle(document.getElementById(id)).display === 'none';
              const initial = hidden('site') && hidden('shop') && !hidden('game') && !hidden('search');
              document.getElementById('shop').href = '/games/category/puzzles';
              await new Promise(resolve => setTimeout(resolve, 100));
              return initial && !hidden('shop');
        """, arguments: [:], in: nil, in: .page) { result in
            XCTAssertEqual(try? result.get() as? Bool, true, String(describing: result))
            done.fulfill()
        }
        try waitForWebView(done)
    }
}
