package games.yandex.wrap.network

import games.yandex.wrap.network.dtos.SimilarGamesResponseDto

class SimilarGamesEndpointService(
    private val networkService: NetworkService? = null,
) {
    suspend fun similar(appId: Long): SimilarGamesResponseDto =
        requireNetworkService().execute(SimilarGamesRequest(appId))

    private fun requireNetworkService(): NetworkService =
        requireNotNull(networkService) { "NetworkService is required to execute similar game requests." }
}

data class SimilarGamesRequest(
    private val appId: Long,
) : Request<SimilarGamesResponseDto> {
    override val path = "/games/api/catalogue/v2/similar_games/"
    override val serializer = SimilarGamesResponseDto.serializer()
    override val query: Map<String, String>
        get() = query(
            "app_id" to appId.toString(),
            "games_count" to "16",
            "int" to "true",
            "page_type" to "game",
            "platform" to "android_other",
            "standalone" to "false",
        )
}
