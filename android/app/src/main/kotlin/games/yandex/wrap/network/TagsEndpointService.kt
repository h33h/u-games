package games.yandex.wrap.network

import games.yandex.wrap.network.dtos.TagsResponseDto

class TagsEndpointService(
    private val networkService: NetworkService? = null,
) {
    suspend fun tags(): TagsResponseDto = requireNetworkService().execute(TagsRequest())

    private fun requireNetworkService(): NetworkService =
        requireNotNull(networkService) { "NetworkService is required to execute tags requests." }
}

data class TagsRequest : Request<TagsResponseDto> {
    override val path = "/games/api/catalogue/v2/tags/"
    override val serializer = TagsResponseDto.serializer()
}
