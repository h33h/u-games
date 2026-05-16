package games.yandex.wrap.catalog.dtos

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class GameFeaturesDto(
    @SerialName("age_rating") val ageRating: String? = null,
)
