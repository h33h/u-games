import CryptoKit
@testable import UGames
import WebKit
import XCTest

@MainActor
final class OfflineReplayTests: OfflineGameTestCase {
    func testReplayFetchesExternalAddressablesFromBinaryCatalogueWithoutNetwork() throws {
        let storageURL = "https://storage.yandexcloud.net/itsjasonstudiobasebacket/GamersMod/Adressables/1.4/"
        let hash = storageURL + "catalog.hash"
        let catalogue = storageURL + "catalog.bin"
        let bundle = storageURL + "level.bundle"
        respond(entry, mime: "text/html", Data("""
        <!doctype html><html><head></head><body><script>
        window.fixtureResult = {pending:true};
        const storage = ['https:', '', 'storage.yandexcloud.net', 'itsjasonstudiobasebacket/GamersMod/Adressables/1.4/'].join('/');
        Promise.all([
          fetch(new Request(storage + 'catalog.hash')).then(response => response.text()),
          fetch(storage + 'catalog.bin').then(response => response.arrayBuffer())
        ]).then(async ([hash, catalogue]) => {
          const bundleURL = new TextDecoder().decode(new Uint8Array(catalogue).subarray(4));
          const bytes = await new Promise((resolve, reject) => {
            const request = new XMLHttpRequest();
            request.open('GET', bundleURL);
            request.responseType = 'arraybuffer';
            request.onload = () => request.status === 200 ? resolve(Array.from(new Uint8Array(request.response))) : reject(new Error('Bundle HTTP ' + request.status));
            request.onerror = () => reject(new Error('Bundle request failed'));
            request.send();
          });
          window.fixtureResult = {pending:false, hash, bundleURL, bytes};
        }).catch(error => { window.fixtureResult = {error:String(error)}; });
        </script></body></html>
        """.utf8))
        respond(hash, mime: "text/plain", Data("catalogue-revision".utf8))
        respond(
            catalogue,
            mime: "application/octet-stream",
            Data([0, 255, 1, 0]) + Data(bundle.utf8)
        )
        respond(bundle, mime: "application/octet-stream", Data([0, 1, 127, 128, 254, 255]))
        let storage = try store()
        let saved = try save(report(resources: [hash, catalogue, bundle]), to: storage)
        let downloadCount = OfflineFixtureProtocol.requests.count
        let (view, controller) = try openOfflineView(saved, storage: storage)
        let value = try fixtureResult(in: view)
        _ = controller
        XCTAssertNil(value["error"], String(describing: value))
        XCTAssertEqual(value["hash"] as? String, "catalogue-revision")
        XCTAssertEqual(value["bundleURL"] as? String, bundle)
        XCTAssertEqual(value["bytes"] as? [Int], [0, 1, 127, 128, 254, 255])
        XCTAssertEqual(OfflineFixtureProtocol.requests.count, downloadCount)
    }

    private func saveReplayFixture(to storage: OfflineGameStore) throws -> SavedOfflineGame {
        let origin = "https://app-123.games.s3.yandex.net/game/"
        let integrityScript = Data(
            "window.integrityLoaded=true; window.integrityURL='https://app-123.games.s3.yandex.net/game/payload.json';"
                .utf8
        )
        let integrityHash = Data(SHA256.hash(data: integrityScript)).base64EncodedString()
        respond(entry, mime: "text/html; charset=utf-8", Data("""
        <!doctype html><html><head><meta http-equiv="Content-Security-Policy" content="default-src 'none'">
        <link rel="stylesheet" href="https://app-123.games.s3.yandex.net/game/style.css"></head><body>
        <script src="https://app-123.games.s3.yandex.net/sdk.js" onload="window.sdkLoaded=true"></script>
        <script>window.earlyConfig = !!window.__UGamesOfflineConfig; window.earlySDK = !!window.YaGames;</script>
        <script src="https://app-123.games.s3.yandex.net/game/integrity.js" integrity="sha256-\(
            integrityHash
        )" crossorigin="anonymous"></script>
        <script type="module" src="https://app-123.games.s3.yandex.net/game/entry.mjs"></script>
        <script src="https://app-123.games.s3.yandex.net/game/main.js"></script></body></html>
        """.utf8))
        respond(origin + "main.js", mime: "application/javascript", Data("""
        window.fixtureResult = {pending:true};
        const workerReady = new Promise((resolve,reject) => { const worker = new Worker('worker.js'); worker.onmessage = event => {worker.terminate(); resolve(event.data);}; worker.onerror = event => reject(new Error('Worker: '+event.message)); setTimeout(() => reject(new Error('Worker timeout')), 3000); });
        Promise.all([fetch('payload.json').then(r => r.json()), fetch('https://app-123.games.s3.yandex.net/game/build.wasm').then(r => r.arrayBuffer()), import('./entry.mjs').then(m => m.ready), workerReady]).then(async ([json, bytes, moduleAnswer, workerAnswer]) => {
          await WebAssembly.instantiate(bytes);
          const sdk = await YaGames.init();
          window.fixtureResult = {pending:false, answer:json.answer, moduleAnswer, workerAnswer, integrityLoaded:window.integrityLoaded, integrityURL:window.integrityURL, rewrittenJSONURL:json.url, bytes:bytes.byteLength, earlyConfig:window.earlyConfig, earlySDK:window.earlySDK, sdkLoaded:window.sdkLoaded, sdk:!!sdk.adv, level:localStorage.getItem('level'), compatMode:document.compatMode, cssURL:getComputedStyle(document.body).backgroundImage};
        }).catch(error => { window.fixtureResult = {error:String(error)}; });
        """.utf8))
        respond(origin + "integrity.js", mime: "application/javascript", integrityScript)
        respond(
            origin + "worker.js",
            mime: "application/javascript",
            Data("importScripts('./worker-helper.js'); postMessage(self.workerValue);".utf8)
        )
        respond(
            origin + "worker-helper.js",
            mime: "application/javascript",
            Data("self.workerValue=42;".utf8)
        )
        respond(
            origin + "entry.mjs",
            mime: "application/javascript",
            Data(
                "import {base} from './nested/dependency.mjs'; export const ready = import('./nested/dynamic.mjs').then(m => base + m.extra);"
                    .utf8
            )
        )
        respond(
            origin + "nested/dependency.mjs",
            mime: "application/javascript",
            Data("export const base = 40;".utf8)
        )
        respond(
            origin + "nested/dynamic.mjs",
            mime: "application/javascript",
            Data("export const extra = 2;".utf8)
        )
        respond(
            origin + "payload.json",
            mime: "application/json",
            Data("{\"answer\":42,\"url\":\"https:\\/\\/app-123.games.s3.yandex.net/game/other\"}"
                .utf8)
        )
        respond(
            origin + "build.wasm",
            mime: "application/wasm",
            Data([0, 97, 115, 109, 1, 0, 0, 0])
        )
        respondStylesAndImages(origin: origin)
        let saved = try save(
            report(resources: [
                origin + "main.js",
                origin + "payload.json",
                origin + "build.wasm",
                origin + "style.css",
                origin + "pixel.svg",
                origin + "entry.mjs",
                origin + "nested/dependency.mjs",
                origin + "nested/dynamic.mjs",
                origin + "worker.js",
                origin + "worker-helper.js",
                origin + "integrity.js",
            ]),
            to: storage
        )
        let svg = try storage.response(
            for: XCTUnwrap(
                URL(string: "ugames-offline://app-123.games.s3.yandex.net/game/pixel.svg")
            ),
            in: saved
        )
        XCTAssertTrue(try decoded(svg.data)
            .contains("xmlns='http://www.w3.org/2000/svg'"))
        return saved
    }

    private func respondStylesAndImages(origin: String) {
        respond(
            origin + "style.css",
            mime: "text/css",
            Data(
                "body { background-image:url(https://app-123.games.s3.yandex.net/game/pixel.svg); }"
                    .utf8
            )
        )
        respond(
            origin + "pixel.svg",
            mime: "image/svg+xml",
            Data("<svg xmlns='http://www.w3.org/2000/svg' width='1' height='1'></svg>".utf8)
        )
    }

    func testPersistentReplayRunsScriptsFetchesAndWASMBeforeAnyNetwork() throws {
        let storage = try store()
        let saved = try saveReplayFixture(to: storage)
        let (view, controller) = try openOfflineView(saved, storage: storage)
        let value = try fixtureResult(in: view)
        _ = controller

        XCTAssertNil(value["error"], String(describing: value))
        XCTAssertEqual(value["answer"] as? Int, 42)
        XCTAssertEqual(value["moduleAnswer"] as? Int, 42)
        XCTAssertEqual(value["workerAnswer"] as? Int, 42)
        XCTAssertEqual(value["integrityLoaded"] as? Bool, true)
        XCTAssertEqual(
            value["integrityURL"] as? String,
            "ugames-offline://app-123.games.s3.yandex.net/game/payload.json"
        )
        XCTAssertEqual(value["bytes"] as? Int, 8)
        XCTAssertEqual(value["earlyConfig"] as? Bool, true)
        XCTAssertEqual(value["earlySDK"] as? Bool, true)
        XCTAssertEqual(value["sdk"] as? Bool, true)
        XCTAssertEqual(value["sdkLoaded"] as? Bool, true)
        XCTAssertEqual(value["level"] as? String, "7")
        XCTAssertEqual(value["compatMode"] as? String, "CSS1Compat")
        XCTAssertEqual(
            value["rewrittenJSONURL"] as? String,
            "ugames-offline://app-123.games.s3.yandex.net/game/other"
        )
        XCTAssertTrue((value["cssURL"] as? String)?.contains("ugames-offline://") == true)
        try assertOfflineProgressPersists(in: view, storage: storage, level: "9")
        try assertChildFrameCannotOverwriteProgress(in: view, storage: storage)
        XCTAssertTrue(OfflineNavigationPolicy.allows(
            saved.offlineURL,
            in: saved,
            isMainFrame: true
        ))
        for target in [
            "https://yandex.ru/games/",
            "ugames-offline://evil.test/",
            "file:///etc/passwd",
            "javascript:alert(1)",
        ] {
            XCTAssertFalse(try OfflineNavigationPolicy.allows(
                XCTUnwrap(URL(string: target)),
                in: saved,
                isMainFrame: true
            ))
        }
    }

    func testOpeningAndRetryingUsesTheLatestSavedProgress() throws {
        let storage = try store()
        let originalSnapshot = try saveReplayFixture(to: storage)
        let updated = expectation(description: "New progress persisted before reopening")
        storage
            .updateStorage(["level": "9"], for: originalSnapshot.id) { error in XCTAssertNil(error)
                updated.fulfill()
            }
        wait(for: [updated], timeout: 5)
        let (view, controller) = try openOfflineView(originalSnapshot, storage: storage)
        XCTAssertEqual(try fixtureResult(in: view)["level"] as? String, "9")
        try assertOfflineProgressPersists(in: view, storage: storage, level: "10")
        controller.webViewWebContentProcessDidTerminate(view)
        let panel = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? UIStackView }.first)
        let retry = try XCTUnwrap(panel.arrangedSubviews.compactMap { $0 as? UIButton }.first)
        retry.sendActions(for: .touchUpInside)
        var retried: WKWebView?
        try waitUntil("Native retry attaches its offline view") {
            retried = controller.view.subviews.compactMap { $0 as? WKWebView }.first
            guard let current = retried else { return false }
            return !current.isHidden && !current.isLoading && current.url != nil
        }
        XCTAssertEqual(try fixtureResult(in: XCTUnwrap(retried))["level"] as? String, "10")
    }

    private func assertOfflineProgressPersists(
        in view: WKWebView,
        storage: OfflineGameStore,
        level: String
    ) throws {
        try evaluateJavaScript(
            "localStorage.setItem('level','\(level)'); window.__UGamesOfflineCapture();",
            in: view
        )
        try waitUntil("Real offline bridge persists localStorage changes") {
            (try? storage.games().first?.storage["level"]) == level
        }
        XCTAssertEqual(try store().games().first?.storage["level"], level)
    }

    private func assertChildFrameCannotOverwriteProgress(
        in view: WKWebView,
        storage: OfflineGameStore
    ) throws {
        let sent = expectation(description: "Saved child frame attempts to send stale progress")
        view.callAsyncJavaScript("""
        const frame = document.createElement('iframe');
        frame.srcdoc = '<script>const stale=()=>webkit.messageHandlers.ugamesOffline.postMessage(JSON.stringify({version:1,url:parent.__UGamesOfflineConfig.url,title:"Child",resources:[],storage:{level:"1"},ready:true}));addEventListener("load",()=>{stale();setInterval(stale,10);window.reportSent=true;});</script>';
        document.body.appendChild(frame);
        const deadline = Date.now() + 3000;
        while (!frame.contentWindow.reportSent && Date.now() < deadline) { await new Promise(resolve => setTimeout(resolve, 20)); }
        await new Promise(resolve => setTimeout(resolve, 100));
        return frame.contentWindow.reportSent === true;
        """, arguments: [:], in: nil, in: .page) { result in
            switch result {
            case let .success(value): XCTAssertEqual(value as? Bool, true)
            case let .failure(error): XCTFail(String(describing: error))
            }
            sent.fulfill()
        }
        try waitForWebView(sent)
        XCTAssertEqual(OfflineGameReportReceiver.shared.report(for: view)?.storage["level"], "9")
        XCTAssertEqual(try storage.games().first?.storage["level"], "9")
    }

    private func openOfflineView(
        _ saved: SavedOfflineGame,
        storage: OfflineGameStore
    ) throws -> (WKWebView, GameViewController) {
        let ready = expectation(description: "Offline WebView configured")
        var result: Result<WKWebView, Error>?
        ProtectedWebViewFactory
            .make(
                offlineGame: saved,
                offlineStore: storage,
                connectivity: OfflineConnectivity(status: .offline, monitoring: false)
            ) { value in result = value
                ready.fulfill()
            }
        try waitForWebView(ready)
        let view = try XCTUnwrap(result).get()
        let controller = GameViewController(
            preparedView: view,
            offlineGame: saved,
            offlineStore: storage
        )
        controller.loadViewIfNeeded()
        view.load(URLRequest(url: saved.offlineURL))
        return (view, controller)
    }

    private func fixtureResult(in view: WKWebView) throws -> [String: Any] {
        try waitForJavaScript(
            "Boolean(window.fixtureResult && window.fixtureResult.pending !== true)",
            in: view
        )
        let text = try XCTUnwrap(
            evaluateJavaScript("JSON.stringify(window.fixtureResult)", in: view) as? String
        )
        let data = try XCTUnwrap(text.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
