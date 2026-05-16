package games.yandex.wrap.catalog

import games.yandex.wrap.catalog.dtos.FeedBlockDto
import games.yandex.wrap.catalog.dtos.FeedResponseDto
import games.yandex.wrap.catalog.dtos.GameDto
import games.yandex.wrap.catalog.dtos.GetGameResponseDto
import games.yandex.wrap.catalog.dtos.ProfileResponseDto
import games.yandex.wrap.catalog.dtos.SimilarGamesResponseDto
import games.yandex.wrap.catalog.dtos.TagsResponseDto
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
        val decoded = decodeOrNull<FeedResponseDto>(response) ?: return FeedWithBlocks(
            blocks = emptyList(),
            flatGames = emptyList(),
            recentGames = emptyList(),
            genres = emptyList(),
            nextPageId = null,
            hasNext = false,
        )
        val blocks = decoded.feed.map { it.toDomain() }
        return FeedWithBlocks(
            blocks = blocks,
            flatGames = blocks.flatMap { it.items },
            recentGames = decoded.recentGames.map { it.toDomain() },
            genres = emptyList(),
            nextPageId = decoded.pageInfo?.nextPageId,
            hasNext = decoded.pageInfo?.hasNextPage ?: (decoded.pageInfo?.nextPageId != null),
        )
    }

    override fun feedPage(response: JsonObject): FeedPage {
        val decoded = decodeOrNull<FeedResponseDto>(response)
        return FeedPage(
            games = decoded?.feed.orEmpty().flatMap { it.items.map(GameDto::toDomain) },
            nextPageId = decoded?.pageInfo?.nextPageId,
            hasNext = decoded?.pageInfo?.hasNextPage ?: (decoded?.pageInfo?.nextPageId != null),
        )
    }

    override fun similarGames(response: JsonObject): List<Game> {
        val decoded = decodeOrNull<SimilarGamesResponseDto>(response) ?: return emptyList()
        return decoded.games?.map { it.toDomain() }
            ?: decoded.feed.flatMap { it.items.map(GameDto::toDomain) }
    }

    override fun parseFeedItems(blocks: JsonArray): List<Game> =
        decodeOrNull<List<FeedBlockDto>>(blocks).orEmpty()
            .flatMap { it.items.map(GameDto::toDomain) }

    override fun appDetail(response: JsonObject): AppDetail? {
        val game = decodeOrNull<GetGameResponseDto>(response)?.game ?: return null
        return AppDetail(
            description = game.description,
            screenshots = game.media?.screenshots.orEmpty()
                .values
                .flatten()
                .mapNotNull { it.prefixUrl ?: it.url },
            datePublished = game.datePublished,
            genres = game.categoriesNames,
            languages = game.inLanguage,
            author = game.developer?.name,
        )
    }

    override fun categoriesFromTags(response: JsonObject): List<GameCategory> =
        decodeOrNull<TagsResponseDto>(response)?.tags.orEmpty().mapNotNull { tag ->
            val slug = tag.slug.takeIf { it.isNotBlank() } ?: return@mapNotNull null
            val title = tag.title.takeIf { it.isNotBlank() } ?: return@mapNotNull null
            GameCategory(
                name = slug,
                title = title,
                gamesCount = tag.info?.gamesCount ?: 0,
            )
        }

    override fun profile(response: JsonObject): UserProfile? {
        val userData = decodeOrNull<ProfileResponseDto>(response)?.userData ?: return null
        if (userData.uid.isBlank()) return null
        return UserProfile(
            isAuthorized = true,
            displayName = userData.displayName,
            login = userData.login,
            avatarUrl = userData.avatarUrl,
            hasYaPlus = userData.yaplusEnabled,
        )
    }

    private inline fun <reified T> decodeOrNull(element: JsonObject): T? =
        runCatching { json.decodeFromJsonElement<T>(element) }.getOrNull()

    private inline fun <reified T> decodeOrNull(element: JsonArray): T? =
        runCatching { json.decodeFromJsonElement<T>(element) }.getOrNull()
}
