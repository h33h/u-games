package games.yandex.wrap.network.dtos

import kotlinx.serialization.Serializable

@Serializable
data class ProfileResponseDto(
    val uid: String = "",
    val displayName: String = "",
    val login: String = "",
    val avatarId: String = "",
    val avatarsOrigin: String = "",
    val yaplusEnabled: Boolean = false,
)
