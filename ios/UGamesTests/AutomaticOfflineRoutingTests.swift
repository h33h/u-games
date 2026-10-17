@testable import UGames
import UIKit
import WebKit
import XCTest

@MainActor
final class AutomaticOfflineRoutingTests: OfflineGameTestCase {
    func testCatalogDocumentAndCoverStopServingAfterReconnect() throws {
        let storage = try store()
        let cover =
            try XCTUnwrap(URL(string: "https://avatars.mds.yandex.net/get-games/123/cover/square"))
        try storage.recordCatalog(OfflineCatalogMetadata(
            version: 1,
            type: "catalog",
            gameId: "123",
            url: XCTUnwrap(URL(string: "https://yandex.ru/games/app/123")),
            title: "Game",
            cover: cover
        ))
        try waitUntil("Catalog metadata commits") {
            FileManager.default
                .fileExists(atPath: self.directory.appendingPathComponent("catalog.json").path)
        }
        respond(entry, mime: "text/html", Data("<p>Game</p>".utf8))
        respond(cover.absoluteString, mime: "image/png", Data([137, 80, 78, 71]))
        let game = try save(report(), to: storage)
        let network = OfflineConnectivity(status: .offline, monitoring: false)
        let handler = OfflineCatalogSchemeHandler(store: storage, connectivity: network)
        let view = WKWebView()
        let urls = [
            OfflineCatalog.url,
            URL(string: "ugames-offline://yandex.ru/games/_covers/" + game.id)!,
        ]
        for status in [OfflineConnectionStatus.offline, .online] {
            network.update(status)
            for url in urls {
                let task = OfflineTaskProbe(request: URLRequest(url: url))
                let finished =
                    expectation(description: "Catalog response respects current connectivity")
                task.onFinish = { finished.fulfill() }
                handler.webView(view, start: task)
                wait(for: [finished], timeout: 5)
                if status == .offline {
                    XCTAssertNil(task.error)
                    XCTAssertFalse(task.data.isEmpty)
                } else {
                    XCTAssertNotNil(task.error)
                    XCTAssertTrue(task.data.isEmpty)
                }
            }
        }
    }

    func testDeletedOfflineKeysStayDeletedAcrossRestartWithoutClearingUnrelatedKeys() throws {
        let storage = try store()
        respond(entry, mime: "text/html", Data("<p>Game</p>".utf8))
        let game = try save(report(storage: ["level": "7", "coins": "100"]), to: storage)
        let first = expectation(description: "Offline reset persists")
        storage
            .updateStorage(["level": "8"], for: game.id, offline: true) { error in
                XCTAssertNil(error)
                first.fulfill()
            }
        wait(for: [first], timeout: 5)
        let reopened = try store()
        let second = expectation(description: "Further offline progress after restart persists")
        reopened
            .updateStorage(["level": "9"], for: game.id, offline: true) { error in
                XCTAssertNil(error)
                second.fulfill()
            }
        wait(for: [second], timeout: 5)
        let ready = expectation(description: "Normal restoration context prepares")
        var result: Result<WKWebView, Error>?
        ProtectedWebViewFactory.make(
            offlineStore: reopened,
            connectivity: OfflineConnectivity(status: .online, monitoring: false)
        ) { result = $0
            ready.fulfill()
        }
        try waitForWebView(ready)
        let view = try XCTUnwrap(result).get()
        let restore = try XCTUnwrap(view.configuration.userContentController.userScripts
            .first { $0.source.hasPrefix("/* UGames pending progress ") })
        view.loadHTMLString("<p>Normal game</p>", baseURL: URL(string: entry))
        try waitForJavaScript("document.readyState==='complete'", in: view)
        try evaluateJavaScript(
            "window.restored={coins:'old-online-coins',auth:'unrelated-auth',other:'keep'};Object.defineProperty(window,'localStorage',{value:{getItem:k=>window.restored[k]??null,setItem:(k,v)=>window.restored[k]=v,removeItem:k=>delete window.restored[k]}});" +
                restore.source,
            in: view
        )
        XCTAssertEqual(try evaluateJavaScript("window.restored.level", in: view) as? String, "9")
        XCTAssertEqual(
            try evaluateJavaScript("window.restored.coins===undefined", in: view) as? Bool,
            true
        )
        XCTAssertEqual(
            try evaluateJavaScript("window.restored.auth", in: view) as? String,
            "unrelated-auth"
        )
        XCTAssertEqual(try evaluateJavaScript("window.restored.other", in: view) as? String, "keep")
        view.stopLoading()
        let readded = expectation(description: "Re-added progress keys clear their tombstones")
        reopened
            .updateStorage(["level": "10", "coins": "200"], for: game.id) { error in
                XCTAssertNil(error)
                readded.fulfill()
            }
        wait(for: [readded], timeout: 5)
        XCTAssertFalse(try reopened.game(id: game.id).removedStorageKeys?
            .contains("coins") ?? false)
    }

    func testLateCatalogMetadataAddsCoverWithoutDownloadingGameFilesAgain() throws {
        let storage = try store()
        let network = OfflineConnectivity(status: .online, monitoring: false)
        respond(entry, mime: "text/html", Data("<p>Cached before catalog metadata</p>".utf8))
        let cover = "https://avatars.mds.yandex.net/get-games/123/late/square"
        respond(cover, mime: "image/png", Data([137, 80, 78, 71]))
        let view = try onlineView(store: storage, network: network)
        view.loadHTMLString(
            "<script>const sdk={features:{LoadingAPI:{ready(){}}}};window.__UGamesOfflineRuntime.trackSDK(sdk);sdk.features.LoadingAPI.ready();</script>",
            baseURL: URL(string: entry)
        )
        try waitForJavaScript("document.readyState==='complete'", in: view)
        let body = try decoded(JSONSerialization.data(withJSONObject: [
            "version": 1,
            "url": entry,
            "title": "Game",
            "resources": [],
            "storage": ["level": "7"],
            "ready": true,
        ]))
        try evaluateJavaScript(
            "webkit.messageHandlers.ugamesOffline.postMessage(" + js(body) + ");true",
            in: view
        )
        try waitUntil("Game caches before metadata arrives") { (try? storage.games().count) == 1 }
        let catalog = try onlineView(store: storage, network: network)
        catalog.loadHTMLString("<title>Game</title>", baseURL: OfflineCatalog.onlineURL)
        try waitForJavaScript("document.readyState==='complete'", in: catalog)
        let metadata = try decoded(JSONSerialization.data(withJSONObject: [
            "version": 1,
            "type": "catalog",
            "gameId": "123",
            "url": "https://yandex.ru/games/app/123",
            "title": "Late catalog title",
            "cover": cover,
        ]))
        try evaluateJavaScript(
            "webkit.messageHandlers.ugamesOffline.postMessage(" + js(metadata) + ");true",
            in: catalog
        )
        try evaluateJavaScript(
            "webkit.messageHandlers.ugamesOffline.postMessage(" + js(body) + ");true",
            in: view
        )
        try waitUntil("A valid late cover enriches the existing cached game") {
            (try? storage.games().first?.cover) != nil
        }
        XCTAssertEqual(
            OfflineFixtureProtocol.requests.filter { $0.url?.absoluteString == self.entry }.count,
            1
        )
        XCTAssertEqual(
            OfflineFixtureProtocol.requests.filter { $0.url?.absoluteString == cover }.count,
            1
        )
        view.stopLoading()
        catalog.stopLoading()
    }

    private func onlineView(
        store: OfflineGameStore,
        network: OfflineConnectivity
    ) throws -> WKWebView {
        let ready = expectation(description: "Online bridge view prepares")
        var result: Result<WKWebView, Error>?
        ProtectedWebViewFactory.make(offlineStore: store, connectivity: network) { result = $0
            ready.fulfill()
        }
        try waitForWebView(ready)
        return try XCTUnwrap(result).get()
    }

    func testGameSchemeStopsServingWhenInternetReturnsAndOnlineFactoryIgnoresSnapshots() throws {
        let storage = try store()
        respond(entry, mime: "text/html", Data("<p>Cached</p>".utf8))
        let game = try save(report(), to: storage)
        let network = OfflineConnectivity(status: .offline, monitoring: false)
        let handler = try OfflineGameSchemeHandler(
            game: game,
            store: storage,
            connectivity: network
        )
        let view = WKWebView()
        let offlineTask = OfflineTaskProbe(request: URLRequest(url: game.offlineURL))
        let served = expectation(description: "No-internet request uses its cached resource")
        offlineTask.onFinish = { served.fulfill() }
        handler.webView(view, start: offlineTask)
        wait(for: [served], timeout: 5)
        XCTAssertNil(offlineTask.error)
        XCTAssertFalse(offlineTask.data.isEmpty)
        network.update(.online)
        let onlineTask = OfflineTaskProbe(request: URLRequest(url: game.offlineURL))
        handler.webView(view, start: onlineTask)
        XCTAssertNotNil(onlineTask.error)
        XCTAssertTrue(onlineTask.data.isEmpty)

        let ready = expectation(description: "An online context always uses the normal data store")
        var result: Result<WKWebView, Error>?
        ProtectedWebViewFactory.make(
            offlineGame: game,
            offlineCatalog: true,
            offlineStore: storage,
            connectivity: network
        ) {
            result = $0
            ready.fulfill()
        }
        try waitForWebView(ready)
        let online = try XCTUnwrap(result).get()
        XCTAssertTrue(online.configuration.websiteDataStore.isPersistent)
        XCTAssertNil(online.configuration.urlSchemeHandler(forURLScheme: OfflineGameStore.scheme))
        online.loadHTMLString("<p>Normal online document</p>", baseURL: OfflineCatalog.onlineURL)
        try waitForJavaScript("document.readyState==='complete'", in: online)
        XCTAssertEqual(
            try evaluateJavaScript(
                "window.__UGamesOfflineConfig===undefined && window.__UGamesCachedCatalog===undefined",
                in: online
            ) as? Bool,
            true
        )
        online.stopLoading()
    }

    func testUnknownAndOnlineConnectionsNeverReplayCacheForServerOrTLSErrors() throws {
        let storage = try store()
        respond(entry, mime: "text/html", Data("<p>Cached game</p>".utf8))
        _ = try save(report(), to: storage)
        for status in [OfflineConnectionStatus.unknown, .online] {
            let network = OfflineConnectivity(status: status, monitoring: false)
            let view = WKWebView()
            let controller = GameViewController(
                preparedView: view,
                offlineStore: storage,
                connectivity: network
            )
            controller.loadViewIfNeeded()
            for error in [
                URLError(.cannotConnectToHost),
                URLError(.secureConnectionFailed),
                URLError(.badServerResponse),
            ] {
                controller.webView(view, didFailProvisionalNavigation: nil, withError: error)
                XCTAssertFalse(controller.isOfflineCatalog)
                XCTAssertNil(controller.offlineGame)
                XCTAssertEqual(network.status, status)
            }
            controller.webView(
                view,
                didFailProvisionalNavigation: nil,
                withError: URLError(.notConnectedToInternet)
            )
            try waitUntil("A strong no-internet error opens the offline catalog") {
                controller.isOfflineCatalog
            }
            controller.webView?.stopLoading()
        }
    }

    func testReconnectCapturesFinalOfflineProgressBeforeCreatingANormalContext() throws {
        let storage = try store()
        respond(entry, mime: "text/html", Data("<script>window.cachedLoaded=true</script>".utf8))
        let game = try save(report(), to: storage)
        let network = OfflineConnectivity(status: .offline, monitoring: false)
        let controller = GameViewController(
            offlineGame: game,
            offlineStore: storage,
            connectivity: network
        )
        controller.loadViewIfNeeded()
        try waitUntil("Offline game view attaches") { controller.webView?.url == game.offlineURL }
        let offline = try XCTUnwrap(controller.webView)
        try waitForJavaScript("window.cachedLoaded === true", in: offline)
        try evaluateJavaScript("localStorage.setItem('level','final-offline-level')", in: offline)
        network.update(.online)
        try waitUntil("Reconnect replaces the offline context") {
            controller.webView !== offline && controller.offlineGame == nil
        }
        XCTAssertEqual(try storage.game(id: game.id).storage["level"], "final-offline-level")
        let online = try XCTUnwrap(controller.webView)
        XCTAssertTrue(online.configuration.websiteDataStore.isPersistent)
        let restore = try XCTUnwrap(online.configuration.userContentController.userScripts
            .first { $0.source.hasPrefix("/* UGames pending progress ") })
        online.stopLoading()
        online.loadHTMLString("<p>Normal online game</p>", baseURL: URL(string: entry))
        try waitForJavaScript("document.readyState==='complete'", in: online)
        // loadHTMLString has an opaque storage origin; execute the real restoration script
        // against controlled storage without relaxing native bridge origin validation.
        try evaluateJavaScript(
            "window.restored={};Object.defineProperty(window,'localStorage',{value:{getItem:key=>window.restored[key]??null,setItem:(key,value)=>window.restored[key]=value,removeItem:key=>delete window.restored[key]}});" +
                restore.source,
            in: online
        )
        XCTAssertEqual(
            try evaluateJavaScript("window.restored.level", in: online) as? String,
            "final-offline-level"
        )
        XCTAssertEqual(
            try evaluateJavaScript(
                "window.__UGamesOfflineConfig === undefined",
                in: online
            ) as? Bool,
            true
        )
        online.stopLoading()
    }

    func testReadyReportsAutomaticallyCacheAndCoalesceProgressWithoutNativeUI() throws {
        let storage = try store()
        respond(entry, mime: "text/html", Data("<p>Automatic game</p>".utf8))
        let ready = expectation(description: "Online view ready")
        var result: Result<WKWebView, Error>?
        let network = OfflineConnectivity(status: .online, monitoring: false)
        ProtectedWebViewFactory.make(offlineStore: storage, connectivity: network) { result = $0
            ready.fulfill()
        }
        try waitForWebView(ready)
        let view = try XCTUnwrap(result).get()
        let controller = GameViewController(
            preparedView: view,
            offlineStore: storage,
            connectivity: network
        )
        controller.loadViewIfNeeded()
        view.loadHTMLString("<p>Playing online</p>", baseURL: URL(string: entry))
        try waitForJavaScript("document.readyState==='complete'", in: view)
        func send(level: String) throws {
            let report = try decoded(JSONSerialization.data(withJSONObject: [
                "version": 1, "url": entry, "title": "Автоматическая игра", "resources": [],
                "storage": ["level": level], "ready": true,
            ]))
            let sent = try evaluateJavaScript(
                "(()=>{try{webkit.messageHandlers.ugamesOffline.postMessage(" + js(report) +
                    ");return 'sent';}catch(error){return String(error);}})()",
                in: view
            )
            XCTAssertEqual(sent as? String, "sent")
        }
        try send(level: "1")
        try waitUntil("A ready played game is cached without a save action") {
            (try? storage.games().first?.storage["level"]) == "1"
        }
        try send(level: "2")
        try send(level: "3")
        try waitUntil("Repeated reports update progress") {
            (try? storage.games().first?.storage["level"]) == "3"
        }
        XCTAssertEqual(OfflineFixtureProtocol.requests.count, 1)
        XCTAssertTrue(controller.view.subviews.compactMap { $0 as? UIButton }.isEmpty)
        XCTAssertNil(controller.presentedViewController)
        view.stopLoading()
    }

    private func js(_ string: String) throws -> String {
        try decoded(JSONEncoder().encode(string))
    }
}
