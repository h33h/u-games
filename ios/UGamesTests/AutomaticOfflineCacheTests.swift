@testable import UGames
import UIKit
import WebKit
import XCTest

@MainActor
final class AutomaticOfflineCacheTests: OfflineGameTestCase {
    func testEvictedHintIsRejectedAndReplacementUsesTheCurrentSnapshot() throws {
        let storage = try store(maximumBytes: 10240)
        let urls = (1 ... 3).map { entry + "&hint=\($0)" }
        var saved: [SavedOfflineGame] = []
        for url in urls {
            respond(
                url,
                mime: "text/html",
                Data(("<p>Game</p>" + String(repeating: " ", count: 1980)).utf8)
            )
            try saved.append(save(report(entryURL: url), to: storage))
        }
        XCTAssertThrowsError(try storage.game(id: saved[0].id))
        let network = OfflineConnectivity(status: .offline, monitoring: false)
        let rejected = expectation(description: "An evicted hint cannot create a replay context")
        ProtectedWebViewFactory.make(
            offlineGame: saved[0],
            offlineStore: storage,
            connectivity: network
        ) { result in
            if case let .success(view) = result {
                view.stopLoading()
                XCTFail("An evicted snapshot must not be revived from its old hint")
            }
            rejected.fulfill()
        }
        try waitForWebView(rejected)
        let hint = saved[2]
        respond(
            urls[2],
            mime: "text/html",
            Data("<script>window.replacementLoaded=true</script>".utf8)
        )
        _ = try save(report(storage: ["level": "latest"], entryURL: urls[2]), to: storage)
        let ready = expectation(description: "A replacement is read and pinned together")
        var result: Result<WKWebView, Error>?
        ProtectedWebViewFactory.make(
            offlineGame: hint,
            offlineStore: storage,
            connectivity: network
        ) { result = $0
            ready.fulfill()
        }
        try waitForWebView(ready)
        let view = try XCTUnwrap(result).get()
        view.load(URLRequest(url: hint.offlineURL))
        try waitForJavaScript("window.replacementLoaded===true", in: view)
        XCTAssertEqual(
            try evaluateJavaScript("localStorage.getItem('level')", in: view) as? String,
            "latest"
        )
        view.stopLoading()
    }

    func testDownloadAdmissionKeepsSpaceForGrowingAndRewritingPinnedProgress() throws {
        let storage = try store(maximumBytes: 12288)
        var last: SavedOfflineGame?
        for index in 1 ... 6 {
            let url = entry + "&fixture=\(index)"
            respond(
                url,
                mime: "text/html",
                Data(("<p>Game</p>" + String(repeating: " ", count: 1500)).utf8)
            )
            last = try save(report(entryURL: url), to: storage)
        }
        let games = try storage.games()
        games.forEach { storage.pin($0.id) }
        defer { games.forEach { storage.unpin($0.id) } }
        let game = try XCTUnwrap(last)
        for level in ["8", "9"] {
            let updated = expectation(description: "Pinned progress grows and remains rewritable")
            storage.updateStorage(
                ["level": level, "payload": String(repeating: "x", count: 2000)],
                for: game.id
            ) { error in
                XCTAssertNil(error)
                updated.fulfill()
            }
            wait(for: [updated], timeout: 5)
            XCTAssertEqual(try storage.game(id: game.id).storage["level"], level)
        }
        XCTAssertEqual(try Set(storage.games().map(\.id)), Set(games.map(\.id)))
    }

    func testCacheBudgetEvictsTheLeastRecentlyPlayedGameAcrossSnapshots() throws {
        let storage = try store(maximumBytes: 10240)
        let entries = (1 ... 3).map { "https://app-123.games.s3.yandex.net/game/\($0).html" }
        for (index, url) in entries.enumerated() {
            respond(
                url,
                mime: "text/html",
                Data(("<p>\(index)</p>" + String(repeating: " ", count: 1990)).utf8)
            )
            _ = try save(report(entryURL: url), to: storage)
        }
        XCTAssertEqual(
            try Set(storage.games().map { $0.url.absoluteString }),
            Set(entries.suffix(2))
        )
        let files = try XCTUnwrap(FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        ))
        let bytes = try files.compactMap { $0 as? URL }.reduce(0) { total, url in
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            return total + (values.isRegularFile == true ? values.fileSize ?? 0 : 0)
        }
        XCTAssertLessThanOrEqual(bytes, 10240)
    }

    func testPlayingAFullScreenGameAddsNoNativeCacheControls() throws {
        let controller = try GameViewController(preparedView: WKWebView(), offlineStore: store())
        controller.loadViewIfNeeded()
        XCTAssertTrue(controller.view.subviews.compactMap { $0 as? UIButton }.isEmpty)
        XCTAssertNil(controller.presentedViewController)
    }

    func testTouchSurvivesReopeningAndEvictsByPlayTimeInsteadOfSaveCompletion() throws {
        var time = Date(timeIntervalSince1970: 100)
        let storage = try store(maximumBytes: 10240, now: { time })
        let firstURL = entry + "&first=1"
        let secondURL = entry + "&second=1"
        let thirdURL = entry + "&third=1"
        for url in [firstURL, secondURL, thirdURL] {
            respond(
                url,
                mime: "text/html",
                Data(("<p>Game</p>" + String(repeating: " ", count: 1980)).utf8)
            )
        }
        let first = try save(report(entryURL: firstURL), to: storage)
        time = Date(timeIntervalSince1970: 200)
        let second = try save(report(entryURL: secondURL), to: storage)
        // A legacy manual snapshot has no lastPlayedAt field.
        let manifest = directory.appendingPathComponent(first.id)
            .appendingPathComponent("manifest.json")
        var legacy = try XCTUnwrap(JSONSerialization
            .jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])
        legacy.removeValue(forKey: "lastPlayedAt")
        try JSONSerialization.data(withJSONObject: legacy).write(to: manifest)
        let reopened = try store(maximumBytes: 10240, now: { time })
        XCTAssertEqual(try reopened.game(id: first.id).playedAt, Date(timeIntervalSince1970: 100))
        reopened.touch(first.id, at: Date(timeIntervalSince1970: 300))
        try waitUntil("Play recency is persisted") {
            (try? reopened.game(id: first.id).playedAt) == Date(timeIntervalSince1970: 300)
        }
        time = Date(timeIntervalSince1970: 400)
        _ = try save(report(entryURL: thirdURL), to: reopened)
        XCTAssertEqual(
            try Set(reopened.games().map(\.id)),
            try Set([first.id, OfflineResourcePolicy.key(XCTUnwrap(URL(string: thirdURL)))])
        )
        XCTAssertThrowsError(try reopened.game(id: second.id))
        // An older visit finishing now must not become the newest played game.
        let spacious = try store(maximumBytes: 16384, now: { time })
        _ = try save(
            report(entryURL: firstURL),
            to: spacious,
            playedAt: Date(timeIntervalSince1970: 50)
        )
        XCTAssertEqual(try spacious.game(id: first.id).playedAt, Date(timeIntervalSince1970: 300))
    }

    func testStableReportsReuseOnlyTheCurrentVisitAndExtendNewResources() throws {
        let storage = try store()
        let visit = UUID()
        let script = "https://app-123.games.s3.yandex.net/game/late.js"
        respond(entry, mime: "text/html", Data("<p>First visit</p>".utf8))
        respond(script, mime: "application/javascript", Data("window.level=9".utf8))
        _ = try save(report(), to: storage, visitID: visit)
        _ = try save(report(storage: ["level": "8"]), to: storage, visitID: visit)
        XCTAssertEqual(OfflineFixtureProtocol.requests.count, 1)
        _ = try save(
            report(resources: [script], storage: ["level": "9"]),
            to: storage,
            visitID: visit
        )
        XCTAssertEqual(OfflineFixtureProtocol.requests.count, 2)
        respond(entry, mime: "text/html", Data("<p>New visit version</p>".utf8))
        let updated = try save(report(resources: [script]), to: storage, visitID: UUID())
        XCTAssertEqual(OfflineFixtureProtocol.requests.count, 4)
        XCTAssertTrue(try decoded(storage.response(for: updated.offlineURL, in: updated).data)
            .contains("New visit version"))
    }

    func testActiveReplayIsPinnedWhileOtherGamesAreEvicted() throws {
        let storage = try store(maximumBytes: 10240)
        let urls = (1 ... 3).map { entry + "&game=\($0)" }
        for url in urls {
            respond(
                url,
                mime: "text/html",
                Data(("<p>Game</p>" + String(repeating: " ", count: 1980)).utf8)
            )
        }
        let first = try save(report(entryURL: urls[0]), to: storage)
        let second = try save(report(entryURL: urls[1]), to: storage)
        let handler = try OfflineGameSchemeHandler(game: first, store: storage)
        _ = try save(report(entryURL: urls[2]), to: storage)
        XCTAssertNoThrow(try storage.game(id: first.id))
        XCTAssertThrowsError(try storage.game(id: second.id))
        XCTAssertNoThrow(try storage.response(for: first.offlineURL, in: first))
        _ = handler
    }

    func testARefreshCanReplaceItsOwnUnpinnedCopyWhenBothVersionsDoNotFit() throws {
        let storage = try store(maximumBytes: 8192)
        respond(
            entry,
            mime: "text/html",
            Data(("<p>Old</p>" + String(repeating: " ", count: 1990)).utf8)
        )
        let first = try save(report(), to: storage)
        respond(
            entry,
            mime: "text/html",
            Data(("<p>New</p>" + String(repeating: " ", count: 2490)).utf8)
        )
        let refreshed = try save(report(), to: storage)
        XCTAssertEqual(first.id, refreshed.id)
        XCTAssertTrue(try decoded(storage.response(for: refreshed.offlineURL, in: refreshed).data)
            .contains("New"))
    }

    func testProgressWritesDoNotWaitForDownloadsAndLatePublicationKeepsLatestProgress() throws {
        let storage = try store()
        respond(entry, mime: "text/html", Data("<p>First</p>".utf8))
        let first = try save(report(), to: storage)
        respond(entry, mime: "text/html", Data("<p>Refresh</p>".utf8), held: true)
        let refreshed = expectation(description: "Held refresh finishes")
        var result: Result<SavedOfflineGame, Error>?
        try storage.save(report(storage: ["level": "old-report"])) { result = $0
            refreshed.fulfill()
        }
        try waitUntil("Refresh request is held") { OfflineFixtureProtocol.lock.lock()
            defer { OfflineFixtureProtocol.lock.unlock() }
            return OfflineFixtureProtocol.pending[self.entry]?.isEmpty == false
        }
        let updated = expectation(description: "Progress saves while network is held")
        storage.updateStorage(["level": "latest"], for: first.id) { error in XCTAssertNil(error)
            updated.fulfill()
        }
        wait(for: [updated], timeout: 5)
        XCTAssertEqual(try storage.game(id: first.id).storage["level"], "latest")
        OfflineFixtureProtocol.resume(entry)
        wait(for: [refreshed], timeout: 10)
        XCTAssertEqual(try XCTUnwrap(result).get().storage["level"], "latest")
    }

    func testEnteringBackgroundCancelsDownloadsAndRemovesUnpublishedFiles() throws {
        let storage = try store()
        respond(entry, mime: "text/html", Data("<p>First</p>".utf8))
        let first = try save(report(), to: storage)
        respond(entry, mime: "text/html", Data("<p>Held refresh</p>".utf8), held: true)
        let controller = GameViewController(preparedView: WKWebView(), offlineStore: storage)
        controller.loadViewIfNeeded()
        let stopped = expectation(description: "Background cancels active download")
        try storage.save(report()) { result in
            if case .success = result {
                XCTFail("A background download must not publish")
            }
            stopped.fulfill()
        }
        try waitUntil("Background fixture request is held") { OfflineFixtureProtocol.lock.lock()
            defer { OfflineFixtureProtocol.lock.unlock() }
            return OfflineFixtureProtocol.pending[self.entry]?.isEmpty == false
        }
        NotificationCenter.default.post(
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        wait(for: [stopped], timeout: 5)
        OfflineFixtureProtocol.resume(entry)
        XCTAssertEqual(try storage.game(id: first.id).storage["level"], "7")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .allSatisfy { !$0.hasPrefix(".staging-") })
        _ = controller
    }
}
