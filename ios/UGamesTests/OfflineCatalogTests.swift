@testable import UGames
import UIKit
import WebKit
import XCTest

@MainActor
final class OfflineCatalogTests: OfflineGameTestCase {
    func testUnreadableCacheStillRendersAnEmptyOfflineCatalog() throws {
        try Data("Unavailable cache directory".utf8).write(to: directory)
        let network = OfflineConnectivity(status: .offline, monitoring: false)
        let controller = try GameViewController(offlineStore: store(), connectivity: network)
        controller.loadViewIfNeeded()
        try waitUntil("A cache write failure does not prevent the catalog from opening") {
            controller.webView?.url == OfflineCatalog.url && controller.webView?.isLoading == false
        }
        let view = try XCTUnwrap(controller.webView)
        try waitForJavaScript(
            "document.documentElement.hasAttribute('data-ugames-cached-catalog')",
            in: view
        )
        XCTAssertNil(controller.presentedViewController)
        XCTAssertTrue(controller.view.subviews.compactMap { $0 as? UIButton }.isEmpty)
        view.stopLoading()
    }

    func testCatalogMetadataRequiresATrustedMainFrameAndSafeCoverOrigin() throws {
        let origin = OfflineReportOrigin(scheme: "https", host: "yandex.ru", port: 443)
        let frame = try XCTUnwrap(URL(string: "https://yandex.ru/games/"))
        let valid =
            try catalogBody(cover: "https://avatars.mds.yandex.net/get-games/123/cover/square")
        XCTAssertEqual(
            try OfflineCatalogMetadata
                .parse(valid, origin: origin, frameURL: frame, mainFrame: true).gameId,
            "123"
        )
        XCTAssertThrowsError(try OfflineCatalogMetadata.parse(
            valid,
            origin: origin,
            frameURL: frame,
            mainFrame: false
        ))
        XCTAssertThrowsError(try OfflineCatalogMetadata.parse(
            valid,
            origin: origin,
            frameURL: URL(string: "https://yandex.ru/profile"),
            mainFrame: true
        ))
        XCTAssertThrowsError(try OfflineCatalogMetadata.parse(
            valid,
            origin: .init(scheme: "https", host: "evil.test", port: 443),
            frameURL: frame,
            mainFrame: true
        ))
        for cover in [
            "http://avatars.mds.yandex.net/get-games/a",
            "https://avatars.mds.yandex.net.evil.test/get-games/a",
            "https://avatars.mds.yandex.net/other/a",
            "https://avatars.mds.yandex.net:444/get-games/a",
        ] {
            XCTAssertThrowsError(try OfflineCatalogMetadata.parse(
                catalogBody(cover: cover),
                origin: origin,
                frameURL: frame,
                mainFrame: true
            ))
        }
    }

    func testCatalogTitlesAndLocalCoversSurviveReopeningAndCoverFailuresAreOptional() throws {
        let storage = try store()
        let cover = "https://avatars.mds.yandex.net/get-games/123/cover/square"
        let metadata = try OfflineCatalogMetadata.parse(
            catalogBody(cover: cover),
            origin: .init(scheme: "https", host: "yandex.ru", port: 443),
            frameURL: URL(string: "https://yandex.ru/games/"),
            mainFrame: true
        )
        storage.recordCatalog(metadata)
        try waitUntil("Catalog metadata persists") {
            FileManager.default
                .fileExists(atPath: self.directory.appendingPathComponent("catalog.json").path)
        }
        let png =
            try XCTUnwrap(
                Data(
                    base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Z6M8AAAAASUVORK5CYII="
                )
            )
        respond(entry, mime: "text/html", Data("<p>Game</p>".utf8))
        respond(cover, mime: "image/png", png)
        let game = try save(report(title: "app-123"), to: storage)
        XCTAssertEqual(game.title, "Настоящее название")
        XCTAssertEqual(game.catalogURL?.absoluteString, "https://yandex.ru/games/app/123")
        let reopened = try store()
        XCTAssertEqual(try reopened.coverResponse(for: game.id).data, png)
        let config = try OfflineCatalog.configuration(store: reopened)
        XCTAssertTrue(config.contains("ugames-offline:"))
        respond(cover, mime: "image/svg+xml", Data("<svg onload='alert(1)'/>".utf8))
        XCTAssertNil(try save(report(), to: storage).cover)
        respond(cover, mime: "image/png", Data(repeating: 0, count: 1024 * 1024 + 1))
        XCTAssertNil(try save(report(), to: storage).cover)
    }

    func testOfflineStartupShowsTheCatalogBeforeOpeningACachedGame() throws {
        let storage = try store()
        respond(entry, mime: "text/html", Data("<p>Cached game</p>".utf8))
        _ = try save(report(), to: storage)
        let network = OfflineConnectivity(status: .offline, monitoring: false)
        let controller = GameViewController(offlineStore: storage, connectivity: network)
        let navigation = UINavigationController(rootViewController: controller)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try waitUntil("Offline startup opens the normal catalog") {
            controller.webView?.url == OfflineCatalog.url && controller.webView?.isLoading == false
        }
        let catalog = try XCTUnwrap(controller.webView)
        XCTAssertNil(controller.offlineGame)
        XCTAssertTrue(controller.isOfflineCatalog)
        try waitForJavaScript(
            "Array.from(document.links).some(link=>link.href===" + js(entry) + ")",
            in: catalog
        )
        XCTAssertEqual(
            try evaluateJavaScript(
                "window.__UGamesOfflineConfig === undefined",
                in: catalog
            ) as? Bool,
            true
        )
        try evaluateJavaScript(
            "Array.from(document.links).find(link=>link.href===" + js(entry) + ").click()",
            in: catalog
        )
        try waitUntil("Catalog card opens a local game") {
            (navigation.topViewController as? GameViewController)?.offlineGame != nil
        }
        XCTAssertEqual(navigation.viewControllers.count, 2)
        let gameController = try XCTUnwrap(navigation.topViewController as? GameViewController)
        try waitUntil("The pushed game loads") {
            gameController.webView?.url?.scheme == OfflineGameStore.scheme
        }
        XCTAssertEqual(OfflineFixtureProtocol.requests.count, 1)
        XCTAssertTrue(gameController.view.subviews.compactMap { $0 as? UIButton }.isEmpty)
        XCTAssertTrue(navigation.interactivePopGestureRecognizer?.isEnabled == true)
        navigation.popViewController(animated: false)
        XCTAssertTrue(navigation.topViewController === controller)
        XCTAssertEqual(controller.webView?.url, OfflineCatalog.url)
        XCTAssertTrue(controller.isOfflineCatalog)
        controller.webView?.stopLoading()
        gameController.webView?.stopLoading()
    }

    func testOfflineStartupWithNoCachedGamesStillOpensTheNormalCatalog() throws {
        let network = OfflineConnectivity(status: .offline, monitoring: false)
        let controller = try GameViewController(offlineStore: store(), connectivity: network)
        controller.loadViewIfNeeded()
        try waitUntil("An empty cache opens a catalog document") {
            controller.webView?.url == OfflineCatalog.url && controller.webView?.isLoading == false
        }
        let view = try XCTUnwrap(controller.webView)
        try waitForJavaScript(
            "document.documentElement.hasAttribute('data-ugames-cached-catalog') && document.querySelector('h1')?.textContent==='Игры'",
            in: view
        )
        XCTAssertNil(controller.offlineGame)
        XCTAssertNil(controller.presentedViewController)
        XCTAssertTrue(controller.view.subviews.compactMap { $0 as? UIButton }.isEmpty)
        view.stopLoading()
    }

    private func catalogBody(cover: String) throws -> String {
        try decoded(JSONSerialization.data(withJSONObject: [
            "version": 1,
            "type": "catalog",
            "gameId": "123",
            "url": "https://yandex.ru/games/app/123",
            "title": "Настоящее название",
            "cover": cover,
        ]))
    }

    private func js(_ string: String) throws -> String {
        try decoded(JSONEncoder().encode(string))
    }
}
