package games.yandex.wrap.network

import java.io.IOException

val Throwable.isTransientNetworkError: Boolean
    get() = this is IOException
