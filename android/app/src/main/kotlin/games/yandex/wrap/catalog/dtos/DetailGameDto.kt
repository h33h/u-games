package games.yandex.wrap.catalog.dtos

import kotlinx.serialization.Serializable

@Serializable
data class DetailGameDto(
    val description: String? = null,
    val media: DetailMediaDto? = null,
    val datePublished: String? = null,
    val categoriesNames: List<String> = emptyList(),
    val inLanguage: List<String> = emptyList(),
    val developer: NamedDto? = null,
)
