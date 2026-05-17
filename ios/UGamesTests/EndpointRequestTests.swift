import XCTest
@testable import UGames

final class EndpointRequestTests: XCTestCase {
    func testSearchRequestUsesCurrentV3EndpointAndLayoutParams() {
        let request = SearchRequest(query: "arcade", pageId: "next", gamesPerPage: 18)
        let components = URLComponents(url: request.url, resolvingAgainstBaseURL: false)
        let query = Dictionary(uniqueKeysWithValues: components?.queryItems?.map { ($0.name, $0.value ?? "") } ?? [])

        XCTAssertEqual(request.url.scheme, "https")
        XCTAssertEqual(request.url.host, "yandex.ru")
        XCTAssertEqual(request.url.path, "/games/api/catalogue/v3/search")
        XCTAssertEqual(query["query"], "arcade")
        XCTAssertEqual(query["page_id"], "next")
        XCTAssertEqual(query["games_count"], "18")
        XCTAssertEqual(query["platform"], "ios")
        XCTAssertEqual(query["with_promos"], "true")
        XCTAssertNotNil(query["client_width"])
        XCTAssertNotNil(query["client_height"])
        XCTAssertNotNil(query["found_width"])
        XCTAssertNil(query["lang"])
    }

    func testFeedRequestPreservesCategoryTab() {
        let request = FeedRequest(gamesPerPage: 12, pageId: "page-2", tab: "puzzles")
        let components = URLComponents(url: request.url, resolvingAgainstBaseURL: false)
        let query = Dictionary(uniqueKeysWithValues: components?.queryItems?.map { ($0.name, $0.value ?? "") } ?? [])

        XCTAssertEqual(request.url.path, "/games/api/catalogue/v2/feed")
        XCTAssertEqual(query["page_id"], "page-2")
        XCTAssertEqual(query["tab"], "puzzles")
    }

    func testUserInfoRequestUsesPassportProfileEndpoint() {
        let request = UserInfoRequest()

        XCTAssertEqual(request.url.scheme, "https")
        XCTAssertEqual(request.url.host, "yandex.ru")
        XCTAssertEqual(request.url.path, "/games/api/user/passport")
    }
}
