package games.yandex.wrap.catalog

import games.yandex.wrap.catalog.models.AppDetail
import games.yandex.wrap.catalog.models.FeedBlock
import games.yandex.wrap.catalog.models.FeedPage
import games.yandex.wrap.catalog.models.FeedWithBlocks
import games.yandex.wrap.catalog.models.Game
import games.yandex.wrap.catalog.models.GameCategory
import games.yandex.wrap.catalog.models.UserProfile
import games.yandex.wrap.network.dtos.FeedBlockDto
import games.yandex.wrap.network.dtos.FeedResponseDto
import games.yandex.wrap.network.dtos.GameDto
import games.yandex.wrap.network.dtos.GetGameResponseDto
import games.yandex.wrap.network.dtos.ProfileResponseDto
import games.yandex.wrap.network.dtos.SimilarGamesResponseDto
import games.yandex.wrap.network.dtos.TagsResponseDto

internal fun FeedResponseDto.toFeedWithBlocks(): FeedWithBlocks {
    val blocks = feed.map { it.toDomain() }
    return FeedWithBlocks(
        blocks = blocks,
        flatGames = blocks.flatMap { it.items },
        recentGames = recentGames.map { it.toDomain() },
        genres = emptyList(),
        nextPageId = pageInfo?.nextPageId,
        hasNext = pageInfo?.hasNextPage ?: (pageInfo?.nextPageId != null),
    )
}

internal fun FeedResponseDto.toFeedPage(): FeedPage = FeedPage(
    games = feed.flatMap { it.items.map(GameDto::toDomain) },
    nextPageId = pageInfo?.nextPageId,
    hasNext = pageInfo?.hasNextPage ?: (pageInfo?.nextPageId != null),
)

internal fun SimilarGamesResponseDto.toGames(): List<Game> =
    games?.map { it.toDomain() } ?: feed.flatMap { it.items.map(GameDto::toDomain) }

internal fun GetGameResponseDto.toAppDetail(): AppDetail? {
    val game = game ?: return null
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

internal fun TagsResponseDto.toCategories(): List<GameCategory> = tags.mapNotNull { tag ->
    val slug = tag.slug.takeIf { it.isNotBlank() } ?: return@mapNotNull null
    val title = tag.title.takeIf { it.isNotBlank() } ?: return@mapNotNull null
    GameCategory(
        name = slug,
        title = title,
        gamesCount = tag.info?.gamesCount ?: 0,
    )
}

internal fun ProfileResponseDto.toUserProfile(): UserProfile? {
    val userData = userData ?: return null
    if (userData.uid.isBlank()) return null
    return UserProfile(
        isAuthorized = true,
        displayName = userData.displayName,
        login = userData.login,
        avatarUrl = userData.avatarUrl,
        hasYaPlus = userData.yaplusEnabled,
    )
}

internal fun FeedBlockDto.toDomain(): FeedBlock = FeedBlock(
    type = type,
    size = size,
    title = title,
    items = items.map(GameDto::toDomain),
)

internal fun GameDto.toDomain(): Game {
    val coverPrefix = media?.cover?.prefixUrl
    val iconPrefix = media?.icon?.prefixUrl
    return Game(
        appId = appID,
        title = title,
        rating = rating,
        ratingCount = ratingCount,
        coverUrl = coverPrefix.orEmpty(),
        iconUrl = iconPrefix ?: coverPrefix.orEmpty(),
        categories = categoriesNames,
        developer = developer?.name.orEmpty(),
        mainColor = media?.cover?.mainColor,
        iconMainColor = media?.icon?.mainColor,
        videoUrl = media?.videos?.firstOrNull()?.mp4StreamUrl,
        coverPrefixUrl = coverPrefix,
        ageRating = features?.ageRating,
    )
}
