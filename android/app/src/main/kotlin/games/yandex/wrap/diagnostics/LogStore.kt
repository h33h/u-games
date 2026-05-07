package games.yandex.wrap.diagnostics

import android.util.Log
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Diagnostic log buffer. In-memory ring of the last [MAX_ENTRIES] events
 * emitted by the inject scripts (via the `ugamesLog` JavascriptInterface) and
 * by native code (auth watcher, profile fetch, cookie state). LogsScreen
 * displays them; long-press the catalog topbar to open it.
 *
 * Useful for debugging on real devices without a USB cable.
 */
data class LogEntry(
    val id: Long,
    val timestampMs: Long,
    val tag: String,
    val message: String,
)

object LogStore {

    private const val MAX_ENTRIES = 500

    private var nextId = 0L

    private val _entries = MutableStateFlow<List<LogEntry>>(emptyList())
    val entries: StateFlow<List<LogEntry>> = _entries.asStateFlow()

    @Synchronized
    fun log(tag: String, message: String) {
        val entry = LogEntry(
            id = nextId++,
            timestampMs = System.currentTimeMillis(),
            tag = tag,
            message = message,
        )
        _entries.update { current ->
            if (current.size >= MAX_ENTRIES) {
                current.subList(current.size - MAX_ENTRIES + 1, current.size) + entry
            } else {
                current + entry
            }
        }
        Log.d("ugames/$tag", message)
    }

    fun clear() {
        _entries.value = emptyList()
    }

    fun dump(): String {
        val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US)
        return _entries.value.joinToString("\n") { e ->
            "${fmt.format(Date(e.timestampMs))} [${e.tag}] ${e.message}"
        }
    }
}
