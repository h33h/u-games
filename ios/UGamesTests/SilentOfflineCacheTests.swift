@testable import UGames
import UIKit
import WebKit
import XCTest

@MainActor
final class SilentOfflineCacheTests: OfflineGameTestCase {
    func testSameViewFailureQueuedDuringReconnectIsIgnored() throws {
        let storage = try store()
        respond(entry, mime: "text/html", Data("<script>window.gameLoaded=true</script>".utf8))
        let game = try save(report(), to: storage)
        let network = OfflineConnectivity(status: .offline, monitoring: false)
        let controller = GameViewController(
            offlineGame: game,
            offlineStore: storage,
            connectivity: network
        )
        controller.loadViewIfNeeded()
        try waitUntil("Offline surface attaches") { controller.webView?.url == game.offlineURL }
        let old = try XCTUnwrap(controller.webView)
        try waitForJavaScript("window.gameLoaded===true", in: old)
        network.update(.online)
        controller.webView(
            old,
            didFailProvisionalNavigation: nil,
            withError: URLError(.notConnectedToInternet)
        )
        controller.webView(old, didFail: nil, withError: URLError(.cannotConnectToHost))
        XCTAssertEqual(network.status, .online)
        XCTAssertNil(controller.errorPanel)
        try waitUntil("Normal context replaces the stale cached surface") {
            controller.webView !== old
        }
        XCTAssertTrue(controller.webView?.configuration.websiteDataStore.isPersistent == true)
        controller.webView?.stopLoading()
    }

    func testMissingTruncatedAndUnreadableReplayFilesQuietlyReturnToCatalog() throws {
        let storage = try store()
        for index in 0 ... 4 {
            let url = entry + "&broken=\(index)"
            let dependency = "https://app-123.games.s3.yandex.net/game/dependency-\(index).js"
            let html = Data(("<script src='" + dependency + "'></script><p>Game</p>").utf8)
            respond(url, mime: "text/html", html)
            respond(dependency, mime: "application/javascript", Data("window.gameLoaded=true".utf8))
            let game = try save(report(resources: [dependency], entryURL: url), to: storage)
            let damagedURL = index < 2 || index == 4 ? url : dependency
            let file = try directory.appendingPathComponent(game.id)
                .appendingPathComponent(OfflineResourcePolicy
                    .key(XCTUnwrap(URL(string: damagedURL))))
            if index == 0 || index == 2 {
                try FileManager.default.removeItem(at: file)
            } else if index == 4 {
                try Data(repeating: 255, count: html.count).write(to: file)
            } else {
                try Data([0]).write(to: file)
            }
            let controller = GameViewController(offlineGame: game, offlineStore: storage)
            controller.loadViewIfNeeded()
            try waitForInitialOutcome(controller)
            assertQuietCatalog(controller)
            if controller.isOfflineCatalog, let view = controller.webView {
                XCTAssertEqual(
                    try evaluateJavaScript(
                        "window.__UGamesCachedCatalog.games.length",
                        in: view
                    ) as? Int,
                    0
                )
            }
            XCTAssertEqual(try storage.game(id: game.id).storage["level"], "7")
            XCTAssertTrue(FileManager.default
                .fileExists(atPath: directory.appendingPathComponent(game.id)
                    .appendingPathComponent("manifest.json").path))
            controller.webView?.stopLoading()
        }
        XCTAssertEqual(try storage.games().count, 5)
    }

    func testEvictedReplayHintQuietlyReturnsToCatalog() throws {
        let storage = try store()
        respond(entry, mime: "text/html", Data("<p>Game</p>".utf8))
        let game = try save(report(), to: storage)
        try storage.delete(game)
        let controller = GameViewController(offlineGame: game, offlineStore: storage)
        controller.loadViewIfNeeded()
        try waitForInitialOutcome(controller)
        assertQuietCatalog(controller)
        controller.webView?.stopLoading()
    }

    func testLateListedReadFailurePreservesProgressAndRecoversOnlyAfterFreshSnapshot() throws {
        let storage = try store()
        let payload = "https://app-123.games.s3.yandex.net/game/late.json"
        let bytes = Data("{\"level\":9}".utf8)
        respond(entry, mime: "text/html", Data("<script>window.gameLoaded=true</script>".utf8))
        respond(payload, mime: "application/json", bytes)
        let visit = UUID()
        let game = try save(
            report(resources: [payload], storage: ["level": "7", "coins": "100"]),
            to: storage,
            visitID: visit
        )
        let controller = GameViewController(offlineGame: game, offlineStore: storage)
        controller.loadViewIfNeeded()
        try waitUntil("Replay view attaches") { controller.webView?.url == game.offlineURL }
        let view = try XCTUnwrap(controller.webView)
        try waitForJavaScript("window.gameLoaded===true", in: view)
        try evaluateJavaScript(
            "localStorage.setItem('level','9');localStorage.removeItem('coins')",
            in: view
        )
        let file = try directory.appendingPathComponent(game.id)
            .appendingPathComponent(OfflineResourcePolicy.key(XCTUnwrap(URL(string: payload))))
        try FileManager.default.removeItem(at: file)
        try runSchemeRequest(
            "ugames-offline://app-123.games.s3.yandex.net/game/late.json",
            in: view
        )
        XCTAssertTrue(
            view.isHidden,
            "A failed cached dependency must immediately leave its broken replay surface"
        )
        guard view.isHidden else { return }
        try waitForInitialOutcome(controller)
        assertQuietCatalog(controller)
        XCTAssertEqual(try storage.game(id: game.id).storage["level"], "9")
        XCTAssertTrue(try storage.game(id: game.id).removedStorageKeys?.contains("coins") == true)
        try bytes.write(to: file)
        let reopened = try store()
        let catalog = GameViewController(
            offlineStore: reopened,
            connectivity: OfflineConnectivity(status: .offline, monitoring: false)
        )
        catalog.loadViewIfNeeded()
        try waitForInitialOutcome(catalog)
        XCTAssertEqual(
            try evaluateJavaScript(
                "window.__UGamesCachedCatalog.games.length",
                in: XCTUnwrap(catalog.webView)
            ) as? Int,
            0
        )
        respond(entry, mime: "text/html", Data("<script>window.freshSnapshot=true</script>".utf8))
        let refreshed = try save(
            report(resources: [payload], storage: ["level": "9"]),
            to: storage,
            visitID: visit
        )
        XCTAssertEqual(
            OfflineFixtureProtocol.requests.filter { $0.url?.absoluteString == self.entry }.count,
            2
        )
        let repaired = GameViewController(offlineGame: refreshed, offlineStore: storage)
        repaired.loadViewIfNeeded()
        try waitUntil("Refreshed replay attaches") { repaired.webView?.url == game.offlineURL }
        try waitForJavaScript("window.freshSnapshot===true", in: XCTUnwrap(repaired.webView))
        XCTAssertNil(repaired.errorPanel)
        repaired.webView?.stopLoading()
        catalog.webView?.stopLoading()
        controller.webView?.stopLoading()
    }

    func testBlockedUnlistedRequestsDoNotInvalidateAnActiveReplay() throws {
        let storage = try store()
        respond(entry, mime: "text/html", Data("<script>window.gameLoaded=true</script>".utf8))
        let game = try save(report(), to: storage)
        let controller = GameViewController(offlineGame: game, offlineStore: storage)
        controller.loadViewIfNeeded()
        try waitUntil("Replay starts") { controller.webView?.url == game.offlineURL }
        let view = try XCTUnwrap(controller.webView)
        try waitForJavaScript("window.gameLoaded===true", in: view)
        for path in ["api/player", "not-captured.json", "sdk.js"] {
            try runSchemeRequest("ugames-offline://app-123.games.s3.yandex.net/" + path, in: view)
        }
        XCTAssertTrue(controller.webView === view)
        XCTAssertFalse(view.isHidden)
        XCTAssertNil(controller.errorPanel)
        XCTAssertNotNil(controller.offlineGame)
    }

    func testFailedBackgroundSaveLeavesTheActiveGameAndSavedProgressUnchanged() throws {
        let storage = try store()
        respond(entry, mime: "text/html", Data("<p>Cached</p>".utf8))
        let game = try save(report(storage: ["level": "7", "coins": "10"]), to: storage)
        let progress = expectation(description: "Offline progress before a failed refresh persists")
        storage.updateStorage(["level": "8"], for: game.id) { error in XCTAssertNil(error)
            progress.fulfill()
        }
        wait(for: [progress], timeout: 5)
        let view = try makeView()
        let controller = GameViewController(
            preparedView: view,
            offlineStore: storage,
            connectivity: OfflineConnectivity(status: .online, monitoring: false)
        )
        controller.loadViewIfNeeded()
        view.loadHTMLString(
            "<script>window.activeGame=true</script>",
            baseURL: OfflineCatalog.onlineURL
        )
        try waitForJavaScript("window.activeGame===true", in: view)
        let failed = expectation(description: "Background refresh failure is silent")
        try storage.save(report(
            resources: ["https://app-123.games.s3.yandex.net/game/missing.js"],
            storage: ["level": "stale"]
        )) { result in
            if case .success = result {
                XCTFail("Missing dependencies cannot publish")
            }
            failed.fulfill()
        }
        wait(for: [failed], timeout: 10)
        XCTAssertTrue(controller.webView === view)
        XCTAssertEqual(try evaluateJavaScript("window.activeGame", in: view) as? Bool, true)
        XCTAssertNil(controller.errorPanel)
        XCTAssertNil(controller.presentedViewController)
        XCTAssertEqual(try storage.game(id: game.id).storage["level"], "8")
        XCTAssertTrue(try storage.game(id: game.id).removedStorageKeys?.contains("coins") == true)
        view.stopLoading()
    }

    func testStaleCachedViewFailuresCannotAffectCurrentOnlineErrorHandling() throws {
        let storage = try store()
        let network = OfflineConnectivity(status: .online, monitoring: false)
        let view = try makeView()
        let controller = GameViewController(
            preparedView: view,
            offlineStore: storage,
            connectivity: network
        )
        controller.loadViewIfNeeded()
        let old = WKWebView()
        controller.webView(
            old,
            didFailProvisionalNavigation: nil,
            withError: URLError(.notConnectedToInternet)
        )
        controller.webView(old, didFail: nil, withError: URLError(.cannotConnectToHost))
        XCTAssertEqual(network.status, .online)
        XCTAssertTrue(controller.webView === view)
        XCTAssertNil(controller.errorPanel)
        controller.webView(
            view,
            didFailProvisionalNavigation: nil,
            withError: URLError(.secureConnectionFailed)
        )
        XCTAssertNotNil(controller.errorPanel)
        XCTAssertEqual(
            controller.errorPanel?.arrangedSubviews.compactMap { $0 as? UIButton }.count,
            2
        )
        XCTAssertFalse(controller.isOfflineCatalog)
        view.stopLoading()
    }

    private func runSchemeRequest(_ url: String, in view: WKWebView) throws {
        let handler = try XCTUnwrap(view.configuration
            .urlSchemeHandler(forURLScheme: OfflineGameStore.scheme) as? OfflineGameSchemeHandler)
        let task = try OfflineTaskProbe(request: URLRequest(url: XCTUnwrap(URL(string: url))))
        let finished = expectation(description: "A cached resource read finishes")
        task.onFinish = { finished.fulfill() }
        handler.webView(view, start: task)
        wait(for: [finished], timeout: 5)
    }

    private func waitForInitialOutcome(_ controller: GameViewController) throws {
        try waitUntil("The cache attempt resolves to a page or an error") {
            if controller.errorPanel != nil {
                return true
            }
            guard let view = controller.webView, let url = view.url,
                  !view.isLoading else { return false }
            return url == OfflineCatalog
                .url || (!view.isHidden && url.scheme == OfflineGameStore.scheme)
        }
    }

    private func assertQuietCatalog(
        _ controller: GameViewController,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(controller.isOfflineCatalog, file: file, line: line)
        XCTAssertEqual(controller.webView?.url, OfflineCatalog.url, file: file, line: line)
        XCTAssertNil(controller.errorPanel, file: file, line: line)
        XCTAssertNil(controller.presentedViewController, file: file, line: line)
    }
}
