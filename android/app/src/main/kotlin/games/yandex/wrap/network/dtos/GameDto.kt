package games.yandex.wrap.network.dtos

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
)
