package games.yandex.wrap.network.dtos

import kotlinx.serialization.Serializable

@Serializable
data class NamedDto(
    val name: String? = null,
)
