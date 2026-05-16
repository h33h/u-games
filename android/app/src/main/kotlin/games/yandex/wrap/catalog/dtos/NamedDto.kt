package games.yandex.wrap.catalog.dtos

import kotlinx.serialization.Serializable

@Serializable
data class NamedDto(
    val name: String? = null,
)
