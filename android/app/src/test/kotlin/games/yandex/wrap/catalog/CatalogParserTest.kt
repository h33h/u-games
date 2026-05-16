package games.yandex.wrap.catalog

import games.yandex.wrap.catalog.models.GameCategory
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CatalogParserTest {
    private val json = Json { ignoreUnknownKeys = true; isLenient = true; coerceInputValues = true }

    @Test
    fun feedWithBlocksDecodesWireShapeWithoutTransformingGames() {
        val root = json.parseToJsonElement(
            """
            {
              "feed": [
                {
                  "type": "suggested",
                  "size": "l",
                  "title": "Top",
                  "items": [
                    {
                      "appID": 1,
                      "title": "Alpha",
                      "rating": 4.5,
                      "ratingCount": 10,
                      "categoriesNames": ["arcade"],
                      "developer": {"name": "Studio A"},
                      "media": {
                        "cover": {"prefix-url": "https://img/alpha/", "mainColor": "#111111"},
                        "icon": {"prefix-url": "https://img/alpha-icon/", "mainColor": "#222222"},
                        "videos": [{"mp4StreamUrl": "https://video/alpha.mp4"}]
                      },
                      "features": {"age_rating": "12+"}
                    }
                  ]
                },
                {
                  "type": "categorized",
                  "size": "s",
                  "title": "More",
                  "items": [
                    {
                      "appID": 1,
                      "title": "Alpha duplicate",
                      "rating": 4.1,
                      "ratingCount": 1,
                      "media": {"cover": {"prefix-url": "https://img/dup/"}}
                    },
                    {
                      "appID": 2,
                      "title": "Beta",
                      "rating": 4.8,
                      "ratingCount": 20,
                      "media": {"cover": {"prefix-url": "https://img/beta/"}}
                    }
                  ]
                }
              ],
              "recentGames": [
                {
                  "appID": 3,
                  "title": "Recent",
                  "media": {"cover": {"prefix-url": "https://img/recent/"}}
                }
              ],
              "pageInfo": {"nextPageId": "next-1", "hasNextPage": true}
            }
            """.trimIndent(),
        ).jsonObject

        val parsed = YandexCatalogJsonParser().feedWithBlocks(root)

        assertEquals(listOf("Top", "More"), parsed.blocks.map { it.title })
        assertEquals(listOf(1L, 1L, 2L), parsed.flatGames.map { it.appId })
        assertEquals(listOf(3L), parsed.recentGames.map { it.appId })
        assertEquals("next-1", parsed.nextPageId)
        assertTrue(parsed.hasNext)
        assertEquals("https://img/alpha/", parsed.blocks.first().items.first().coverUrl)
        assertEquals("https://img/alpha-icon/", parsed.blocks.first().items.first().iconUrl)
        assertEquals("#111111", parsed.blocks.first().items.first().mainColor)
        assertEquals("https://video/alpha.mp4", parsed.blocks.first().items.first().videoUrl)
        assertEquals("12+", parsed.blocks.first().items.first().ageRating)
    }

    @Test
    fun jsonParserDecodesTagsProfileAndDetailWithoutFallbacksOrRewrites() {
        val parser = YandexCatalogJsonParser(json)
        val tagsRoot = json.parseToJsonElement(
            """
            {
              "tags": [
                {"slug": "puzzles_12", "title": "Puzzles", "info": {"games_count": 42}, "isService": false},
                {"slug": "", "title": "Hidden", "info": {"games_count": 1}, "isService": false}
              ]
            }
            """.trimIndent(),
        ).jsonObject
        val profileRoot = json.parseToJsonElement(
            """
            {
              "userData": {
                "uid": "u1",
                "login": "player",
                "displayName": "Player One",
                "avatarUrl": "https://avatars.example/raw.png",
                "yaplusEnabled": true
              }
            }
            """.trimIndent(),
        ).jsonObject
        val detailRoot = json.parseToJsonElement(
            """
            {
              "game": {
                "description": "A &amp; B",
                "categoriesNames": ["Arcade", "Puzzle"],
                "developer": {"name": "Dev &amp; Co"},
                "media": {
                  "screenshots": {
                    "mobile": [{"prefix-url": "https://img/mobile/"}],
                    "desktop": [{"prefix-url": "https://img/desktop/"}]
                  }
                }
              }
            }
            """.trimIndent(),
        ).jsonObject

        val categories = parser.categoriesFromTags(tagsRoot)
        val profile = assertNotNull(parser.profile(profileRoot))
        val detail = assertNotNull(parser.appDetail(detailRoot))

        assertEquals(GameCategory("puzzles_12", "Puzzles", 42), categories.single())
        assertTrue(profile.isAuthorized)
        assertEquals("Player One", profile.displayName)
        assertEquals("player", profile.login)
        assertEquals("https://avatars.example/raw.png", profile.avatarUrl)
        assertTrue(profile.hasYaPlus)
        assertEquals("A &amp; B", detail.description)
        assertEquals(listOf("https://img/mobile/", "https://img/desktop/"), detail.screenshots)
        assertNull(detail.datePublished)
        assertEquals(listOf("Arcade", "Puzzle"), detail.genres)
        assertEquals(emptyList(), detail.languages)
        assertEquals("Dev &amp; Co", detail.author)

        val anonymous = json.parseToJsonElement("""{"userData":{"uid":""}}""").jsonObject
        assertNull(parser.profile(anonymous))
    }
}
