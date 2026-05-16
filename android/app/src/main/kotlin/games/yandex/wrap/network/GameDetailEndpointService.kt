package games.yandex.wrap.network

import games.yandex.wrap.network.dtos.GetGameResponseDto

class GameDetailEndpointService(
    private val networkService: NetworkService? = null,
) {
    suspend fun detail(appId: Long): GetGameResponseDto = requireNetworkService().execute(GameDetailRequest(appId))

    private fun requireNetworkService(): NetworkService =
        requireNotNull(networkService) { "NetworkService is required to execute game detail requests." }
}

data class GameDetailRequest(
    private val appId: Long,
) : Request<GetGameResponseDto> {
    override val method = HttpMethod.Post
    override val path = "/games/api/catalogue/v2/get_game"
    override val serializer = GetGameResponseDto.serializer()
    override val jsonBody = json("appID" to appId, "format" to "app")
}
