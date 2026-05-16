package games.yandex.wrap.network.dtos

import kotlinx.serialization.Serializable

@Serializable
data class DetailMediaDto(
    val screenshots: Map<String, List<ScreenshotDto>> = emptyMap(),
)
