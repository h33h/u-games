@testable import UGames
import XCTest

final class GameNavigationPolicyTests: XCTestCase {
    func testYandexIdCanFinishSSOAndSynchronizeCookies() throws {
        for value in [
            "https://sso.passport.yandex.ru/prepare?uuid=fixture&goal=https%3A%2F%2Fya.ru%2F&finish=https%3A%2F%2Fyandex.ru%2Fgames%2F",
            "https://sso.passport.yandex.com/prepare?uuid=fixture",
            "https://sso.ya.ru/sync?uuid=fixture",
        ] {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertTrue(GameNavigationPolicy.allows(url), value)
            XCTAssertTrue(GameNavigationPolicy.allowsFrame(
                url,
                source: URL(string: "https://passport.yandex.ru/pwl-yandex/auth/finished")
            ), value)
        }
        for value in [
            "https://sso.passport.yandex.ru/profile",
            "https://sso.passport.yandex.ru/prepare-evil",
            "https://sso.passport.yandex.ru.evil.test/prepare",
            "https://sso.ya.ru/profile",
            "https://sso.ya.ru/sync-evil",
            "https://sso.ya.ru.evil.test/sync",
            "http://sso.ya.ru/sync",
            "https://sso.ya.ru:444/sync",
        ] {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertFalse(GameNavigationPolicy.allows(url), value)
            XCTAssertFalse(GameNavigationPolicy.allowsFrame(
                url,
                source: URL(string: "https://sso.passport.yandex.ru/prepare")
            ), value)
        }
    }

    func testCurrentYandexIdLoginAndVerificationCanOpen() throws {
        for value in [
            "https://passport.yandex.ru/pwl-yandex/auth/add?retpath=https%3A%2F%2Fyandex.ru%2Fgames%2F",
            "https://passport.yandex.com/pwl-yandex/auth/verify",
        ] {
            XCTAssertTrue(try GameNavigationPolicy.allows(XCTUnwrap(URL(string: value))), value)
        }
        for value in [
            "https://passport.yandex.ru/pwl-yandex-evil/auth",
            "https://passport.yandex.ru.evil.test/pwl-yandex/auth",
        ] {
            XCTAssertFalse(try GameNavigationPolicy.allows(XCTUnwrap(URL(string: value))), value)
        }
    }

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
