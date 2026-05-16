package games.yandex.wrap.network

import games.yandex.wrap.network.dtos.FeedResponseDto
import games.yandex.wrap.utils.Constants

class FeedEndpointService(
    private val networkService: NetworkService? = null,
) {
    suspend fun feed(
        gamesPerPage: Int = 24,
        pageId: String? = null,
    ): FeedResponseDto = requireNetworkService().execute(
        FeedRequest(
            gamesPerPage = gamesPerPage,
            pageId = pageId,
        )
    )

    private fun requireNetworkService(): NetworkService =
        requireNotNull(networkService) { "NetworkService is required to execute feed requests." }
}

data class FeedRequest(
    private val gamesPerPage: Int,
    private val pageId: String?,
) : Request<FeedResponseDto> {
    override val path = "/games/api/catalogue/v2/feed/"
    override val serializer = FeedResponseDto.serializer()
    override val query: Map<String, String>
        get() {
            val screenSize = Constants.UI.screenSize
            return query(
                "with_promos" to "true",
                "games_count" to gamesPerPage.toString(),
                "categorized_size" to "5",
                "with_recent_games" to "true",
                "platform" to "android_other",
                "client_width" to screenSize.width.toString(),
                "client_height" to screenSize.height.toString(),
                "page_id" to pageId,
            )
        }
}
