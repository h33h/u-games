@testable import UGames
import WebKit
import XCTest

private final class PortalPageCompletion: NSObject, WKNavigationDelegate {
    let loaded: (WKWebView) -> Void
    init(loaded: @escaping (WKWebView) -> Void) {
        self.loaded = loaded
    }

    func webView(_ view: WKWebView, didFinish _: WKNavigation!) {
        loaded(view)
    }
}

@MainActor
final class PortalContentTests: XCTestCase {
    func testScriptedExternalNavigationKeepsTheGameAndItsFrame() throws {
        let ready = expectation(description: "Protected view ready")
        var prepared: Result<WKWebView, Error>?
        ProtectedWebViewFactory.make { result in
            prepared = result
            ready.fulfill()
        }
        wait(for: [ready], timeout: 15)
        let view = try XCTUnwrap(prepared).get()
        let controller = GameViewController(preparedView: view)
        controller.loadViewIfNeeded()
        let home = try XCTUnwrap(URL(string: "https://yandex.ru/games/"))
        view.loadHTMLString(
            "<p id='game'>Game</p><iframe srcdoc=\"<p id='child'>Child</p>\"></iframe>",
            baseURL: home
        )
        let done = expectation(description: "Native policy rejects scripted external navigation")
        let deadline = Date().addingTimeInterval(5)
        func poll() {
            if view.isLoading, Date() < deadline {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
                return
            }
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
        }
        poll()
        wait(for: [done], timeout: 10)
    }

    func testPortalCleanupPreservesGamesAndRestoresReusedNavigation() throws {
        let ready = expectation(description: "Protected view ready")
        var prepared: Result<WKWebView, Error>?
        ProtectedWebViewFactory.make { result in
            prepared = result
            ready.fulfill()
        }
        wait(for: [ready], timeout: 15)
        let webView = try XCTUnwrap(prepared).get()
        let done = expectation(description: "Portal cleanup in WKWebView")
        let loaded = PortalPageCompletion { view in
            view.callAsyncJavaScript("""
              const hidden = (id) => getComputedStyle(document.getElementById(id)).display === 'none';
              const initial = hidden('site') && hidden('shop') && !hidden('game') && !hidden('search');
              document.getElementById('shop').href = '/games/category/puzzles';
              await new Promise(resolve => setTimeout(resolve, 100));
              return initial && !hidden('shop');
            """, arguments: [:], in: nil, in: .page) { result in
                do {
                    XCTAssertEqual(try result.get() as? Bool, true)
                } catch {
                    XCTFail(String(describing: error))
                }
                done.fulfill()
            }
        }
        webView.navigationDelegate = loaded
        webView.loadHTMLString("""
        <input id="search" placeholder="Найти игру">
        <div id="site" class="page-description">О сайте</div>
        <a id="shop" href="/games/shop">Магазин</a>
        <a id="game" href="/games/app/123">Играть</a>
        """, baseURL: URL(string: "https://yandex.ru/games/"))
        wait(for: [done], timeout: 10)
    }
}
