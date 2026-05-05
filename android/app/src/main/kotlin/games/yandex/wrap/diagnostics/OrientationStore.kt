package games.yandex.wrap.diagnostics

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Tracks the orientation a running game has requested via
 * `screen.orientation.lock()`. The SDK stub traps that call inside the game
 * iframe and forwards the requested target to native via the `ugamesLog` JS
 * bridge with tag="orient". GameScreen observes this store to decide whether
 * to show the "rotate device" overlay.
 */
object OrientationStore {

    enum class Required { Landscape, Portrait }

    private val _required = MutableStateFlow<Required?>(null)
    val required: StateFlow<Required?> = _required.asStateFlow()

    /** Reset before opening a new game. */
    fun reset() { _required.value = null }

    /**
     * Parse the body of an "orient" log message. Yandex SDK calls usually pass
     * strings like "landscape", "landscape-primary", or "portrait".
     */
    fun setFromString(s: String?) {
        if (s.isNullOrEmpty()) return
        val lower = s.lowercase()
        when {
            lower.contains("landscape") -> _required.value = Required.Landscape
            lower.contains("portrait") -> _required.value = Required.Portrait
        }
    }
}
