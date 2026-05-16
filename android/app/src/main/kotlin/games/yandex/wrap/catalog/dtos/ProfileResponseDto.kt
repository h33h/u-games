package games.yandex.wrap.catalog.dtos

import kotlinx.serialization.Serializable

@Serializable
data class ProfileResponseDto(
    val userData: UserDataDto? = null,
)
