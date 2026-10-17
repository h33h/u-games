@testable import UGames
import WebKit
import XCTest

@MainActor
final class OfflineGameTests: OfflineGameTestCase {
    func testEmptyOrPartialHTTPResponsesCannotReplaceAnExistingGame() throws {
        respond(entry, mime: "text/html", Data("<p>Original game</p>".utf8))
        let storage = try store()
        _ = try save(report(), to: storage)
        for (status, data) in [
            (204, Data()),
            (206, Data("<p>Partial game</p>".utf8)),
            (200, Data()),
        ] {
            respond(entry, mime: "text/html", data, status: status)
            XCTAssertThrowsError(try save(report(title: "Invalid replacement"), to: storage))
            let existing = try XCTUnwrap(storage.games().first)
            XCTAssertEqual(existing.title, "Тестовая игра")
            XCTAssertTrue(try decoded(storage.response(for: existing.offlineURL, in: existing).data)
                .contains("Original game"))
        }
    }

    func testEntryFragmentSurvivesSavingAndReplayWithoutChangingResourceKeys() throws {
        respond(entry, mime: "text/html", Data("<p>Game</p>".utf8))
        let storage = try store()
        let saved = try save(report(entryURL: entry + "#level=7"), to: storage)
        XCTAssertEqual(saved.url.fragment, "level=7")
        XCTAssertEqual(saved.offlineURL.fragment, "level=7")
        let restored = try XCTUnwrap(storage.games().first)
        XCTAssertEqual(restored.url.fragment, "level=7")
        XCTAssertEqual(restored.resources.count, 1)
        XCTAssertTrue(try decoded(storage.response(for: restored.offlineURL, in: restored).data)
            .contains("Game"))
    }

    func testRejectsUntrustedOrMalformedReportsBeforeSaving() throws {
        let valid = try JSONSerialization.data(withJSONObject: [
            "version": 1,
            "url": entry,
            "title": "Game",
            "resources": [],
            "storage": [:],
            "ready": true,
        ])
        let body = try decoded(valid)
        for origin in [
            OfflineReportOrigin(scheme: "https", host: "yandex.ru", port: 443),
            OfflineReportOrigin(
                scheme: "https",
                host: "app-123.games.s3.yandex.net.evil.test",
                port: 443
            ),
            OfflineReportOrigin(scheme: "http", host: "app-123.games.s3.yandex.net", port: 80),
            OfflineReportOrigin(scheme: "https", host: "app-123.games.s3.yandex.net", port: 444),
        ] {
            XCTAssertThrowsError(try OfflineGameReport.parse(body, origin: origin))
        }
        let origin = OfflineReportOrigin(
            scheme: "https",
            host: "app-123.games.s3.yandex.net",
            port: 443
        )
        for invalid in [
            "{}",
            "[]",
            "null",
            "not JSON",
            String(repeating: "x", count: 2 * 1024 * 1024 + 1),
        ] {
            XCTAssertThrowsError(try OfflineGameReport.parse(invalid, origin: origin))
        }
        var invalid = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        invalid["storage"] = ["level": 7]
        let badStorage = try JSONSerialization.data(withJSONObject: invalid)
        XCTAssertThrowsError(try OfflineGameReport.parse(
            decoded(badStorage),
            origin: origin
        ))
        invalid["storage"] = [:]
        invalid["resources"] = Array(repeating: entry, count: 4097)
        let tooMany = try JSONSerialization.data(withJSONObject: invalid)
        XCTAssertThrowsError(try OfflineGameReport.parse(
            decoded(tooMany),
            origin: origin
        ))
        XCTAssertEqual(try report().storage["level"], "7")
    }

    func testSnapshotSurvivesANewStoreAndNeverDownloadsSDKAdsOrAPIs() throws {
        let script = "https://app-123.games.s3.yandex.net/game/main.js?v=2"
        let binary = "https://app-123.games.s3.yandex.net/game/build.wasm"
        let excluded = [
            "https://yandex.ru/games/sdk/v2",
            "https://app-123.games.s3.yandex.net/sdk.js",
            "https://app-123.games.s3.yandex.net/sdk/assets.js",
            "https://app-123.games.s3.yandex.net/api/player",
            "https://an.yandex.ru/ads.js",
            "https://evil.test/asset.js",
        ]
        respond(
            entry,
            mime: "text/html; charset=utf-8",
            Data("<script src='main.js?v=2'></script>".utf8)
        )
        respond(script, mime: "application/javascript", Data("window.saved = true".utf8))
        let bytes = Data([0, 97, 115, 109, 1, 0, 0, 0])
        respond(binary, mime: "application/wasm", bytes)
        let first = try store()
        let saved = try save(report(resources: [script, binary] + excluded), to: first)
        let reopened = try store()
        let reloaded = try XCTUnwrap(reopened.games().first)
        XCTAssertEqual(reloaded.id, saved.id)
        XCTAssertEqual(reloaded.storage["level"], "7")
        XCTAssertEqual(reloaded.resources.count, 3)
        let result = try reopened.response(
            for: XCTUnwrap(
                URL(string: "ugames-offline://app-123.games.s3.yandex.net/game/build.wasm")
            ),
            in: reloaded
        )
        XCTAssertEqual(result.data, bytes)
        XCTAssertEqual(result.mimeType, "application/wasm")
        XCTAssertThrowsError(try reopened.response(
            for: XCTUnwrap(
                URL(string: "ugames-offline://app-123.games.s3.yandex.net/game/missing.json")
            ),
            in: reloaded
        ))
        XCTAssertThrowsError(try reopened.response(
            for: XCTUnwrap(URL(string: "https://app-123.games.s3.yandex.net/game/build.wasm")),
            in: reloaded
        ))
        let requests = OfflineFixtureProtocol.requests
        XCTAssertEqual(
            Set(requests.compactMap { $0.url?.absoluteString }),
            Set([entry, script, binary])
        )
        XCTAssertTrue(requests
            .allSatisfy {
                $0.value(forHTTPHeaderField: "Cookie") == nil && $0
                    .value(forHTTPHeaderField: "Authorization") == nil
            })
        try reopened.delete(reloaded)
        XCTAssertTrue(try store().games().isEmpty)
    }

    func testIncompleteOrOversizeReplacementKeepsTheExistingGame() throws {
        respond(entry, mime: "text/html", Data("<p>Original</p>".utf8))
        let storage = try store(maximumBytes: 32)
        let original = try save(report(), to: storage)
        XCTAssertThrowsError(try save(
            report(
                resources: ["https://app-123.games.s3.yandex.net/game/missing.js"],
                title: "Broken"
            ),
            to: storage
        ))
        respond(entry, mime: "text/html", Data(repeating: 65, count: 33))
        XCTAssertThrowsError(try save(report(title: "Too big"), to: storage))
        let existing = try XCTUnwrap(storage.games().first)
        XCTAssertEqual(existing.title, "Тестовая игра")
        XCTAssertEqual(existing.id, original.id)
        let response = try storage.response(for: existing.offlineURL, in: existing)
        XCTAssertTrue(try decoded(response.data).contains("Original"))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .filter { $0.hasPrefix(".staging-") }.count,
            0
        )
    }

    func testOfflineProgressIsPersistedWithoutRedownloadingResources() throws {
        respond(entry, mime: "text/html", Data("<p>Game</p>".utf8))
        let storage = try store()
        let game = try save(report(), to: storage)
        let updated = expectation(description: "Progress metadata saved atomically")
        storage.updateStorage(["level": "8", "coins": "12"], for: game.id) { error in
            XCTAssertNil(error)
            updated.fulfill()
        }
        wait(for: [updated], timeout: 5)
        XCTAssertEqual(try store().games().first?.storage, ["level": "8", "coins": "12"])
        XCTAssertEqual(OfflineFixtureProtocol.requests.count, 1)
    }

    func testSuccessfulRefreshReplacesTheCompleteSnapshot() throws {
        respond(entry, mime: "text/html", Data("<p>First</p>".utf8))
        let storage = try store()
        let first = try save(report(), to: storage)
        respond(entry, mime: "text/html", Data("<p>Updated version</p>".utf8))
        _ = try save(report(title: "Обновлённая игра", storage: ["level": "10"]), to: storage)
        let games = try store().games()
        XCTAssertEqual(games.count, 1)
        let refreshed = try XCTUnwrap(games.first)
        XCTAssertEqual(refreshed.id, first.id)
        XCTAssertEqual(refreshed.title, "Обновлённая игра")
        XCTAssertEqual(refreshed.storage["level"], "10")
        XCTAssertTrue(try decoded(storage.response(for: refreshed.offlineURL, in: refreshed).data)
            .contains("Updated version"))
    }

    func testSavingFailureStillLeavesTheLibraryAvailable() throws {
        try Data("A file prevents creating the storage directory".utf8).write(to: directory)
        let storage = try store()
        let library = OfflineLibraryViewController(store: storage) { _ in
            XCTFail("An empty library cannot launch a game")
        }
        library.loadViewIfNeeded()
        XCTAssertEqual(library.tableView(library.tableView, numberOfRowsInSection: 0), 0)
        XCTAssertThrowsError(try save(report(), to: storage))
    }

    func testReplaySupportsMediaByteRangesAndStopsCancelledTasks() throws {
        respond(entry, mime: "text/html", Data("<p>Game</p>".utf8))
        let sound = "https://app-123.games.s3.yandex.net/game/sound.ogg"
        respond(sound, mime: "audio/ogg", Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]))
        let storage = try store()
        let game = try save(report(resources: [sound]), to: storage)
        let handler = OfflineGameSchemeHandler(game: game, store: storage)
        let view = WKWebView()
        let soundURL =
            try XCTUnwrap(
                URL(string: "ugames-offline://app-123.games.s3.yandex.net/game/sound.ogg")
            )
        var request = URLRequest(url: soundURL)
        request.setValue("bytes=2-5", forHTTPHeaderField: "Range")
        let range = OfflineTaskProbe(request: request)
        let finished = expectation(description: "Media byte range delivered")
        range.onFinish = { finished.fulfill() }
        handler.webView(view, start: range)
        wait(for: [finished], timeout: 5)
        XCTAssertNil(range.error)
        XCTAssertEqual(range.response?.statusCode, 206)
        XCTAssertEqual(range.response?.value(forHTTPHeaderField: "Content-Range"), "bytes 2-5/10")
        XCTAssertEqual(range.data, Data([2, 3, 4, 5]))
        let cancelled = OfflineTaskProbe(request: request)
        let noCallbacks = expectation(description: "Stopped scheme tasks receive no late callbacks")
        noCallbacks.isInverted = true
        cancelled.onEvent = { noCallbacks.fulfill() }
        handler.webView(view, start: cancelled)
        handler.webView(view, stop: cancelled)
        wait(for: [noCallbacks], timeout: 0.15)
    }
}
