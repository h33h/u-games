package games.yandex.wrap.catalog.dtos

import kotlinx.serialization.Serializable

@Serializable
data class UserDataDto(
    val uid: String,
    val displayName: String = "",
    val login: String = "",
    val avatarUrl: String = "",
    val yaplusEnabled: Boolean = false,
)
