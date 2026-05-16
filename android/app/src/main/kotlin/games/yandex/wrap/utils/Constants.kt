package games.yandex.wrap.utils

import android.content.res.Resources
import android.util.Size
import kotlin.math.roundToInt

object Constants {
    object Network {
        const val host = "yandex.ru"
    }

    object UI {
        val screenSize: Size
            get() {
                val metrics = Resources.getSystem().displayMetrics
                return Size(
                    (metrics.widthPixels / metrics.density).roundToInt(),
                    (metrics.heightPixels / metrics.density).roundToInt(),
                )
            }
    }
}
