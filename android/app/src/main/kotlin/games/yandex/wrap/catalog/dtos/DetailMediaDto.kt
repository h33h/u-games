package games.yandex.wrap.catalog.dtos

import kotlinx.serialization.Serializable

@Serializable
data class DetailMediaDto(
    val screenshots: Map<String, List<ScreenshotDto>> = emptyMap(),
)
