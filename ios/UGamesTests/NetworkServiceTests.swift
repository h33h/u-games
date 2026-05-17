import XCTest
@testable import UGames

final class NetworkServiceTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.response = nil
        StubURLProtocol.data = Data()
        super.tearDown()
    }

    func testExecuteThrowsNetworkErrorBeforeDecodingNonSuccessStatus() async throws {
        StubURLProtocol.response = HTTPURLResponse(
            url: URL(string: "https://yandex.ru/games/api/catalogue/v2/tags/")!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        )
        StubURLProtocol.data = Data("Not Found".utf8)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let service = NetworkService(session: URLSession(configuration: config))

        do {
            _ = try await service.execute(TagsRequest())
            XCTFail("Expected HTTP status error")
        } catch NetworkError.httpStatus(let statusCode, let bodySnippet) {
            XCTAssertEqual(statusCode, 404)
            XCTAssertEqual(bodySnippet, "Not Found")
        } catch {
            XCTFail("Expected NetworkError.httpStatus, got \(error)")
        }
    }
}

private final class StubURLProtocol: URLProtocol {
    static var response: HTTPURLResponse?
    static var data = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let response = Self.response else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
