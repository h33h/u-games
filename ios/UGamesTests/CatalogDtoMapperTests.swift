import XCTest
@testable import UGames

final class CatalogDtoMapperTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { codingPath in
            AnyCodingKey(stringValue: (codingPath.last?.stringValue ?? "").normalizedJSONKey)
        }
        return decoder
    }()

    func testFeedPageFallsBackToTopLevelItemsAndPageId() throws {
        let data = """
        {
          "items": [
            {
              "appID": 10,
              "title": "Fallback Game",
              "rating": 4.2,
              "ratingCount": 7,
              "categoriesNames": ["runner"],
              "media": {"cover": {"prefix-url": "https://img/fallback/"}}
            }
          ],
          "pageID": "top-level-next",
          "totalPages": 3
        }
        """.data(using: .utf8)!

        let page = try decoder.decode(FeedResponseDTO.self, from: data).feedPage

        XCTAssertEqual(page.games.map(\.appId), [10])
        XCTAssertEqual(page.nextPageId, "top-level-next")
        XCTAssertTrue(page.hasNext)
    }

    func testPassportProfileMapsTopLevelFieldsAndAvatarUrl() throws {
        let data = """
        {
          "uid": "u1",
          "login": "player",
          "displayName": "Player One",
          "avatarId": "avatar-1",
          "avatarsOrigin": "https://avatars.example",
          "yaplusEnabled": true
        }
        """.data(using: .utf8)!

        let profile = try XCTUnwrap(decoder.decode(ProfileResponseDTO.self, from: data).userProfile)

        XCTAssertTrue(profile.isAuthorized)
        XCTAssertEqual(profile.displayName, "Player One")
        XCTAssertEqual(profile.login, "player")
        XCTAssertEqual(profile.avatarUrl, "https://avatars.example/get-yapic/avatar-1/islands-200")
        XCTAssertTrue(profile.hasYaPlus)
    }

    func testPassportProfileWithEmptyUidIsAnonymous() throws {
        let data = """
        {
          "uid": "",
          "avatarId": "0/0-0",
          "avatarsOrigin": "https://avatars.example",
          "yaplusEnabled": false
        }
        """.data(using: .utf8)!

        XCTAssertNil(try decoder.decode(ProfileResponseDTO.self, from: data).userProfile)
    }
}
