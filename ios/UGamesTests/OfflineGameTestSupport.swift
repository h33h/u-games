@testable import UGames
import WebKit
import XCTest

final class OfflineFixtureProtocol: URLProtocol {
    static let lock = NSLock()
    struct Response {
        let mime: String
        let data: Data
        let status: Int
        var held = false
    }

    static var responses: [String: Response] = [:]
    static var requests: [URLRequest] = []
    static var pending: [String: [() -> Void]] = [:]
    private let deliveryLock = NSLock()
    private var stopped = false

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let fixture = Self.responses[request.url!.absoluteString]
        Self.lock.unlock()
        guard let fixture = fixture else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        let deliver = {
            self.deliveryLock.lock()
            let stopped = self.stopped
            self.deliveryLock.unlock()
            guard !stopped else { return }
            let response = HTTPURLResponse(
                url: self.request.url!,
                statusCode: fixture.status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": fixture.mime]
            )!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: fixture.data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        if fixture.held {
            Self.lock.lock()
            Self.pending[request.url!.absoluteString, default: []].append(deliver)
            Self.lock.unlock()
        } else {
            deliver()
        }
    }

    override func stopLoading() {
        deliveryLock.lock()
        stopped = true
        deliveryLock.unlock()
    }

    static func resume(_ url: String) {
        lock.lock()
        let deliveries = pending.removeValue(forKey: url) ?? []
        lock.unlock()
        deliveries.forEach { $0() }
    }
}

final class OfflineTaskProbe: NSObject, WKURLSchemeTask {
    let request: URLRequest
    var response: HTTPURLResponse?
    var data = Data()
    var error: Error?
    var onEvent: (() -> Void)?
    var onFinish: (() -> Void)?

    init(request: URLRequest) {
        self.request = request
    }

    func didReceive(_ response: URLResponse) {
        self.response = response as? HTTPURLResponse
        onEvent?()
    }

    func didReceive(_ data: Data) {
        self.data.append(data)
        onEvent?()
    }

    func didFinish() {
        onEvent?()
        onFinish?()
    }

    func didFailWithError(_ error: Error) {
        self.error = error
        onEvent?()
        onFinish?()
    }
}

@MainActor
class OfflineGameTestCase: WebViewTestCase {
    let entry = "https://app-123.games.s3.yandex.net/game/index.html?lang=ru"
    var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        OfflineFixtureProtocol.lock.lock()
        OfflineFixtureProtocol.responses = [:]
        OfflineFixtureProtocol.requests = []
        OfflineFixtureProtocol.pending = [:]
        OfflineFixtureProtocol.lock.unlock()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func report(
        resources: [String] = [],
        title: String = "Тестовая игра",
        storage: [String: String] = ["level": "7"],
        entryURL: String? = nil
    ) throws -> OfflineGameReport {
        let json = try JSONSerialization.data(withJSONObject: [
            "version": 1, "url": entryURL ?? entry, "title": title, "resources": resources,
            "storage": storage, "environment": ["i18n": ["lang": "ru"]], "ready": true,
        ])
        return try OfflineGameReport.parse(
            decoded(json),
            origin: OfflineReportOrigin(
                scheme: "https",
                host: "app-123.games.s3.yandex.net",
                port: 443
            )
        )
    }

    func store(
        maximumBytes: Int64 = OfflineGameStore.maximumCacheBytes,
        now: @escaping () -> Date = Date.init
    ) throws -> OfflineGameStore {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineFixtureProtocol.self]
        return OfflineGameStore(
            rootURL: directory,
            maximumCacheBytes: maximumBytes,
            sessionConfiguration: configuration,
            now: now
        )
    }

    func save(
        _ report: OfflineGameReport,
        to store: OfflineGameStore,
        visitID: UUID? = nil,
        playedAt: Date? = nil
    ) throws -> SavedOfflineGame {
        let done = expectation(description: "Offline game snapshot completes")
        var result: Result<SavedOfflineGame, Error>?
        store.save(report, visitID: visitID, playedAt: playedAt) { value in
            result = value
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        return try XCTUnwrap(result).get()
    }

    func respond(_ url: String, mime: String, _ data: Data, status: Int = 200, held: Bool = false) {
        OfflineFixtureProtocol.lock.lock()
        OfflineFixtureProtocol.responses[url] = .init(
            mime: mime,
            data: data,
            status: status,
            held: held
        )
        OfflineFixtureProtocol.lock.unlock()
    }

    func decoded(_ data: Data) throws -> String {
        try XCTUnwrap(String(data: data, encoding: .utf8))
    }
}
