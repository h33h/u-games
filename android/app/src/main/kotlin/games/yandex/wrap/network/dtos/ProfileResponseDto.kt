package games.yandex.wrap.network.dtos

import kotlinx.serialization.Serializable

@Serializable
data class ProfileResponseDto(
    val userData: UserDataDto? = null,
)
