package games.yandex.wrap.network

import games.yandex.wrap.network.dtos.ProfileResponseDto

class UserInfoEndpointService(
    private val networkService: NetworkService? = null,
) {
    suspend fun profile(): ProfileResponseDto =
        requireNetworkService().execute(UserInfoRequest())

    private fun requireNetworkService(): NetworkService =
        requireNotNull(networkService) { "NetworkService is required to execute user info requests." }
}

class UserInfoRequest : Request<ProfileResponseDto> {
    override val path = "/games/api/user/passport"
    override val serializer = ProfileResponseDto.serializer()
}
