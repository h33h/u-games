@testable import UGames
import XCTest

final class GameNavigationPolicyTests: XCTestCase {
    func testSupportsS3GameHosting() throws {
        XCTAssertTrue(try GameNavigationPolicy.allowsFrame(
            XCTUnwrap(URL(string: "https://app-374241.games.s3.yandex.net/helpers/fake-page")),
            source: URL(string: "https://yandex.ru/games/")
        ))
    }

    func testFramesCannotLeaveTheGameOriginEvenForScriptedNavigation() throws {
        let source =
            try XCTUnwrap(URL(string: "https://app-388224.cdn.games.yandex.net/game/index.html"))
        XCTAssertTrue(try GameNavigationPolicy.allowsFrame(
            XCTUnwrap(URL(string: "https://app-388224.cdn.games.yandex.net/game/level2")),
            source: source
        ))
        XCTAssertTrue(GameNavigationPolicy.allowsFrame(
            source,
            source: URL(string: "https://yandex.ru/games/app/388224")
        ))
        XCTAssertTrue(try GameNavigationPolicy.allowsFrame(
            XCTUnwrap(URL(string: "https://game.example/level2")),
            source: URL(string: "https://game.example/play")
        ))
        for value in [
            "https://external.example",
            "https://game.example:444/",
            "https://games.yandex.net.evil.test/",
            "intent://open",
        ] {
            XCTAssertFalse(
                try GameNavigationPolicy.allowsFrame(XCTUnwrap(URL(string: value)), source: source),
                value
            )
        }
    }

    func testOnlyGamePortalCanReplaceTheMainWindow() throws {
        for value in [
            "https://yandex.ru/games/",
            "https://yandex.com/games/app/123",
            "https://passport.yandex.ru/auth",
            "about:blank",
        ] {
            XCTAssertTrue(try GameNavigationPolicy.allows(XCTUnwrap(URL(string: value))), value)
        }
        for value in [
            "https://example.com",
            "https://yandex.ru.evil.test/games/",
            "https://yandex.ru/games-evil",
            "https://yandex.ru/support/games/",
            "https://passport.yandex.ru/profile",
            "intent://game",
            "data:text/html,hello",
            "https://yandex.ru:444/games/",
        ] {
            XCTAssertFalse(try GameNavigationPolicy.allows(XCTUnwrap(URL(string: value))), value)
        }
    }
}
