package games.yandex.wrap.catalog.dtos

import games.yandex.wrap.catalog.models.Game
import kotlinx.serialization.Serializable

@Serializable
data class GameDto(
    val appID: Long,
    val title: String,
    val rating: Float = 0f,
    val ratingCount: Int = 0,
    val media: GameMediaDto? = null,
    val categoriesNames: List<String> = emptyList(),
    val developer: NamedDto? = null,
    val features: GameFeaturesDto? = null,
) {
    fun toDomain(): Game {
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
}
