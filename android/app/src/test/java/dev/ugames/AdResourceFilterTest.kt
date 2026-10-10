package dev.ugames

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AdResourceFilterTest {
    private val filter = AdResourceFilter(
        listOf("an.yandex.ru"),
        listOf("^https?://yandex\\.ru/ads/")
    )

    @Test fun blocksOnlyAdvertisingResources() {
        assertTrue(filter.shouldBlock("https://an.yandex.ru/mapuid/test"))
        assertTrue(filter.shouldBlock("https://child.an.yandex.ru/ad"))
        assertTrue(filter.shouldBlock("https://yandex.ru/ads/system/context.js"))
        assertFalse(filter.shouldBlock("https://an.yandex.ru.evil.test/ad"))
        assertFalse(filter.shouldBlock("https://not-an.yandex.ru/ad"))
        assertFalse(filter.shouldBlock("https://yandex.ru/games/"))
        assertFalse(
            filter.shouldBlock("https://passport.yandex.ru/auth?retpath=https://an.yandex.ru/")
        )
        assertFalse(filter.shouldBlock("https://app-263344.cdn.games.yandex.net/game.js"))
        assertFalse(filter.shouldBlock("not a URL"))
    }
}
