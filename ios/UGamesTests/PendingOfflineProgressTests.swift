@testable import UGames
import WebKit
import XCTest

@MainActor
final class PendingOfflineProgressTests: OfflineGameTestCase {
    func testInactivePeriodicReportsCannotChangeTheFinalPendingRevision() throws {
        let storage = try store()
        respond(entry, mime: "text/html", Data("<script>window.gameLoaded=true</script>".utf8))
        let game = try save(report(), to: storage)
        let controller = GameViewController(offlineGame: game, offlineStore: storage)
        controller.loadViewIfNeeded()
        try waitUntil("Offline view attaches") { controller.webView?.url == game.offlineURL }
        let view = try XCTUnwrap(controller.webView)
        try waitForJavaScript("window.gameLoaded===true", in: view)
        try evaluateJavaScript("localStorage.setItem('level','8')", in: view)
        try capture(view)
        let revision = try XCTUnwrap(storage.game(id: game.id).pendingProgressRevision)
        controller.viewWillDisappear(false)
        let body = try decoded(JSONSerialization.data(withJSONObject: [
            "version": 1,
            "url": entry,
            "title": "Late report",
            "resources": [],
            "storage": ["level": "stale-periodic"],
            "ready": true,
        ]))
        let quoted = try decoded(JSONEncoder().encode(body))
        try evaluateJavaScript(
            "webkit.messageHandlers.ugamesOffline.postMessage(" + quoted + ");true",
            in: view
        )
        let drained = expectation(description: "Late bridge work settles")
        storage.metadataQueue.async { drained.fulfill() }
        wait(for: [drained], timeout: 5)
        XCTAssertEqual(try storage.game(id: game.id).storage["level"], "8")
        XCTAssertEqual(try storage.game(id: game.id).pendingProgressRevision, revision)
        try evaluateJavaScript("localStorage.setItem('level','9')", in: view)
        try capture(view)
        XCTAssertEqual(try storage.game(id: game.id).storage["level"], "9")
        XCTAssertNotEqual(try storage.game(id: game.id).pendingProgressRevision, revision)
        controller.switchContext(to: OfflineCatalog.url, game: nil, catalog: true)
        XCTAssertTrue(view.isHidden)
        try waitUntil("Catalog transition completes") {
            controller.webView?.url == OfflineCatalog.url
        }
        controller.webView?.stopLoading()
    }

    func testNormalRestoreBeforeControllerFinishCannotRestoreTwice() throws {
        let storage = try store()
        respond(entry, mime: "text/html", Data("<script>window.gameLoaded=true</script>".utf8))
        let game = try save(report(storage: ["level": "7", "coins": "100"]), to: storage)
        let controller = GameViewController(
            offlineGame: game,
            offlineStore: storage
        )
        controller.loadViewIfNeeded()
        try waitUntil("Offline game attaches") { controller.webView?.url == game.offlineURL }
        let old = try XCTUnwrap(controller.webView)
        try waitForJavaScript("window.gameLoaded===true", in: old)
        try evaluateJavaScript(
            "localStorage.setItem('level','9');localStorage.removeItem('coins')",
            in: old
        )
        try capture(old)
        // The same production factory serves normal startup and reconnect. Use a
        // fresh context so a real HTTPS navigation cannot replace this fixture.
        let view = try normalView(store: storage)
        let initial = restoreScripts(in: view).joined(separator: ";")
        XCTAssertFalse(initial.isEmpty)
        try loadHTMLFixture(
            "<p>A document before the controller finishes</p>",
            baseURL: URL(string: entry),
            in: view
        )
        try evaluateJavaScript(
            "window.values={level:'old',coins:'100',auth:'keep'};Object.defineProperty(window,'localStorage',{value:{getItem:k=>window.values[k]??null,setItem:(k,v)=>window.values[k]=v,removeItem:k=>delete window.values[k]}});" +
                initial + ";true",
            in: view
        )
        XCTAssertEqual(try evaluateJavaScript("window.values.level", in: view) as? String, "9")
        XCTAssertEqual(
            try evaluateJavaScript("window.values.coins===undefined", in: view) as? Bool,
            true
        )
        XCTAssertEqual(try evaluateJavaScript("window.values.auth", in: view) as? String, "keep")
        try waitUntil("Pending one-shot restoration acknowledges") {
            !view.configuration.userContentController.userScripts
                .contains { $0.source.hasPrefix("/* UGames pending progress ") }
        }
        try evaluateJavaScript(
            "window.values.level='10';window.values.coins='200';" + initial + ";true",
            in: view
        )
        XCTAssertEqual(try evaluateJavaScript("window.values.level", in: view) as? String, "10")
        XCTAssertEqual(try evaluateJavaScript("window.values.coins", in: view) as? String, "200")
        XCTAssertTrue(restoreScripts(in: view).isEmpty)
        view.stopLoading()
        old.stopLoading()
    }

    func testQuietRecoveryAndRelaunchRestorePendingDeletesWithoutRollingBackLaterOnlinePlay(
    ) throws {
        let storage = try store()
        _ = try makeOfflineEdit("9", to: storage)
        let reopened = try store()
        let view = try normalView(store: reopened)
        let source = try pendingScript(in: view)
        try loadHTMLFixture(
            "<p>Normal game after catalog navigation</p>",
            baseURL: URL(string: entry),
            in: view
        )
        try evaluateJavaScript(
            "window.values={level:'old-online',coins:'100',auth:'keep'};Object.defineProperty(window,'localStorage',{value:{getItem:k=>window.values[k]??null,setItem:(k,v)=>window.values[k]=v,removeItem:k=>delete window.values[k]}});" +
                source + ";true",
            in: view
        )
        XCTAssertEqual(try evaluateJavaScript("window.values.level", in: view) as? String, "9")
        XCTAssertEqual(
            try evaluateJavaScript("window.values.coins===undefined", in: view) as? Bool,
            true
        )
        XCTAssertEqual(try evaluateJavaScript("window.values.auth", in: view) as? String, "keep")
        try evaluateJavaScript(
            "window.values.level='10';window.values.coins='200';" + source + ";true",
            in: view
        )
        XCTAssertEqual(try evaluateJavaScript("window.values.level", in: view) as? String, "10")
        XCTAssertEqual(try evaluateJavaScript("window.values.coins", in: view) as? String, "200")
        try waitUntil("A validated matching-origin acknowledgement removes the pending hook") {
            !view.configuration.userContentController.userScripts
                .contains { $0.source.hasPrefix("/* UGames pending progress ") }
        }
        let next = try normalView(store: store())
        XCTAssertFalse(next.configuration.userContentController.userScripts
            .contains { $0.source.hasPrefix("/* UGames pending progress ") })
        view.stopLoading()
    }

    func testOnlineCaptureBeforeAcknowledgementCannotOverwritePendingOfflineEdits() throws {
        let storage = try store()
        let game = try makeOfflineEdit("9", to: storage)
        let updated = expectation(description: "Unrestored online capture is ignored")
        storage
            .updateStorage(["level": "stale-online", "coins": "100"], for: game.id) { error in
                XCTAssertNil(error)
                updated.fulfill()
            }
        wait(for: [updated], timeout: 5)
        XCTAssertEqual(try storage.game(id: game.id).storage["level"], "9")
        XCTAssertTrue(try storage.game(id: game.id).removedStorageKeys?.contains("coins") == true)
        _ = try save(report(storage: ["level": "stale-online", "coins": "100"]), to: storage)
        XCTAssertEqual(try storage.game(id: game.id).storage["level"], "9")
        XCTAssertTrue(try storage.game(id: game.id).removedStorageKeys?.contains("coins") == true)
    }

    func testOnlyNewestPendingEditForTheSameOriginCanRestore() throws {
        let storage = try store()
        _ = try makeOfflineEdit("9", to: storage, url: entry + "&version=old")
        let oldSource = try pendingScript(in: normalView(store: storage))
        _ = try makeOfflineEdit("11", to: storage, url: entry + "&version=new")
        let view = try normalView(store: store())
        XCTAssertEqual(
            view.configuration.userContentController.userScripts
                .filter { $0.source.hasPrefix("/* UGames pending progress ") }.count,
            1
        )
        let newest = try pendingScript(in: view)
        try loadHTMLFixture("<p>Normal game</p>", baseURL: URL(string: entry), in: view)
        try evaluateJavaScript(
            "window.values={auth:'keep'};Object.defineProperty(window,'localStorage',{value:{getItem:k=>window.values[k]??null,setItem:(k,v)=>window.values[k]=v,removeItem:k=>delete window.values[k]}});" +
                newest + ";true",
            in: view
        )
        try evaluateJavaScript(oldSource + ";true", in: view)
        XCTAssertEqual(try evaluateJavaScript("window.values.level", in: view) as? String, "11")
        XCTAssertEqual(try evaluateJavaScript("window.values.auth", in: view) as? String, "keep")
        try waitUntil("Superseded pending revisions cannot be installed again") {
            !view.configuration.userContentController.userScripts
                .contains { $0.source.hasPrefix("/* UGames pending progress ") }
        }
        let next = try normalView(store: store())
        XCTAssertFalse(next.configuration.userContentController.userScripts
            .contains { $0.source.hasPrefix("/* UGames pending progress ") })
        view.stopLoading()
    }

    private func makeOfflineEdit(
        _ level: String,
        to storage: OfflineGameStore,
        url: String? = nil
    ) throws -> SavedOfflineGame {
        let url = url ?? entry
        respond(url, mime: "text/html", Data("<script>window.gameLoaded=true</script>".utf8))
        let game = try save(
            report(storage: ["level": "7", "coins": "100"], entryURL: url),
            to: storage
        )
        let controller = GameViewController(offlineGame: game, offlineStore: storage)
        controller.loadViewIfNeeded()
        try waitUntil("Offline game attaches") { controller.webView?.url == game.offlineURL }
        let view = try XCTUnwrap(controller.webView)
        try waitForJavaScript("window.gameLoaded===true", in: view)
        try evaluateJavaScript(
            "localStorage.setItem('level','\(level)');localStorage.removeItem('coins')",
            in: view
        )
        controller.webView(view, didFail: nil, withError: OfflineGameError.missingResource)
        try waitUntil("Quiet recovery returns to catalog") {
            controller.webView?.url == OfflineCatalog.url && controller.webView?.isLoading == false
        }
        XCTAssertNil(controller.errorPanel)
        XCTAssertEqual(try storage.game(id: game.id).storage["level"], level)
        controller.webView?.stopLoading()
        return game
    }

    private func normalView(store: OfflineGameStore) throws -> WKWebView {
        let ready = expectation(description: "Normal protected context prepares")
        var result: Result<WKWebView, Error>?
        ProtectedWebViewFactory.make(
            offlineStore: store,
            connectivity: OfflineConnectivity(status: .online, monitoring: false)
        ) { result = $0
            ready.fulfill()
        }
        try waitForWebView(ready)
        return try XCTUnwrap(result).get()
    }

    private func pendingScript(in view: WKWebView) throws -> String {
        try XCTUnwrap(view.configuration.userContentController.userScripts
            .first { $0.source.hasPrefix("/* UGames pending progress ") }?.source)
    }

    private func restoreScripts(in view: WKWebView) -> [String] {
        view.configuration.userContentController.userScripts.map(\.source)
            .filter {
                $0.hasPrefix("/* UGames pending progress ") || $0
                    .hasPrefix("/* UGames progress restore */")
            }
    }

    private func capture(_ view: WKWebView) throws {
        let done = expectation(description: "Explicit final capture persists")
        OfflineGameReportReceiver.shared.captureProgress(in: view) { done.fulfill() }
        try waitForWebView(done)
    }
}
