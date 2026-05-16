package games.yandex.wrap.catalog

import games.yandex.wrap.network.dtos.FeedBlockDto
import games.yandex.wrap.network.dtos.FeedResponseDto
import games.yandex.wrap.network.dtos.GameDto
import games.yandex.wrap.network.dtos.GetGameResponseDto
import games.yandex.wrap.network.dtos.ProfileResponseDto
import games.yandex.wrap.network.dtos.SimilarGamesResponseDto
import games.yandex.wrap.network.dtos.TagsResponseDto
import games.yandex.wrap.catalog.models.AppDetail
import games.yandex.wrap.catalog.models.FeedPage
import games.yandex.wrap.catalog.models.FeedWithBlocks
import games.yandex.wrap.catalog.models.Game
import games.yandex.wrap.catalog.models.GameCategory
import games.yandex.wrap.catalog.models.UserProfile
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.decodeFromJsonElement

interface CatalogParser {
    fun feedWithBlocks(response: JsonObject): FeedWithBlocks
    fun feedPage(response: JsonObject): FeedPage
    fun similarGames(response: JsonObject): List<Game>
    fun parseFeedItems(blocks: JsonArray): List<Game>
    fun appDetail(response: JsonObject): AppDetail?
    fun categoriesFromTags(response: JsonObject): List<GameCategory>
    fun profile(response: JsonObject): UserProfile?
}

class YandexCatalogJsonParser(
    private val json: Json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        coerceInputValues = true
    },
) : CatalogParser {
    override fun feedWithBlocks(response: JsonObject): FeedWithBlocks {
        return decodeOrNull<FeedResponseDto>(response)?.toFeedWithBlocks() ?: FeedWithBlocks(
            blocks = emptyList(),
            flatGames = emptyList(),
            recentGames = emptyList(),
            genres = emptyList(),
            nextPageId = null,
            hasNext = false,
        )
    }

    override fun feedPage(response: JsonObject): FeedPage {
        return decodeOrNull<FeedResponseDto>(response)?.toFeedPage()
            ?: FeedPage(games = emptyList(), nextPageId = null, hasNext = false)
    }

    override fun similarGames(response: JsonObject): List<Game> {
        return decodeOrNull<SimilarGamesResponseDto>(response)?.toGames().orEmpty()
    }

    override fun parseFeedItems(blocks: JsonArray): List<Game> =
        decodeOrNull<List<FeedBlockDto>>(blocks).orEmpty()
            .flatMap { it.items.map(GameDto::toDomain) }

    override fun appDetail(response: JsonObject): AppDetail? {
        return decodeOrNull<GetGameResponseDto>(response)?.toAppDetail()
    }

    override fun categoriesFromTags(response: JsonObject): List<GameCategory> =
        decodeOrNull<TagsResponseDto>(response)?.toCategories().orEmpty()

    override fun profile(response: JsonObject): UserProfile? {
        return decodeOrNull<ProfileResponseDto>(response)?.toUserProfile()
    }

    private inline fun <reified T> decodeOrNull(element: JsonObject): T? =
        runCatching { json.decodeFromJsonElement<T>(element) }.getOrNull()

    private inline fun <reified T> decodeOrNull(element: JsonArray): T? =
        runCatching { json.decodeFromJsonElement<T>(element) }.getOrNull()
}
