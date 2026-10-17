package dev.ugames

import java.util.concurrent.ExecutorService
import java.util.concurrent.Future

/** One foreground worker coalesces reports; recurring captures never repeatedly refresh a visit. */
class AutomaticOfflineCache(
    private val store: OfflineGameStore,
    private val executor: ExecutorService,
    private val onSaved: (List<SavedOfflineGame>) -> Unit = {},
    private val clock: () -> Long = System::currentTimeMillis
) {
    private data class Capture(
        val report: OfflineCaptureReport,
        val visit: String,
        val playedAt: Long
    )
    private val lock = Any()
    private val pending = linkedMapOf<String, Capture>()
    private val completed = mutableMapOf<String, OfflineCaptureReport>()
    private val retryAfter = mutableMapOf<String, Long>()
    private val catalogVersions = mutableMapOf<String, Long>()
    private var enabled = false
    private var generation = 0
    private var worker: Future<*>? = null

    fun setEnabled(value: Boolean) = synchronized(lock) {
        if (enabled == value) return@synchronized
        enabled = value
        generation++
        if (!value) {
            pending.clear()
            worker?.cancel(true)
            worker = null
        }
    }

    fun offer(report: OfflineCaptureReport, visitId: String, playedAt: Long) = synchronized(lock) {
        if (!enabled || !report.ready) return@synchronized
        store.notePlayed(report.entryUrl, playedAt)
        val normalized = report.copy(resources = report.resources.distinct().sorted())
        pending[OfflineGameStore.gameId(report.entryUrl)] = Capture(normalized, visitId, playedAt)
        if (worker == null) {
            val token = generation
            worker = executor.submit { drain(token) }
        }
    }

    fun catalogChanged(gameId: String) = synchronized(lock) {
        catalogVersions[gameId] = (catalogVersions[gameId] ?: 0) + 1
        while (catalogVersions.size > 128) catalogVersions.remove(catalogVersions.keys.first())
        completed.entries.removeAll { OfflineCatalogMetadata.gameId(it.value.entryUrl) == gameId }
    }

    private fun drain(token: Int) {
        while (true) {
            val capture = synchronized(lock) {
                if (!enabled || generation != token) return
                val entry = pending.entries.firstOrNull()
                if (entry == null) {
                    worker = null
                    return
                }
                pending.remove(entry.key)
                entry.value
            }
            val key = capture.visit + ":" + OfflineGameStore.gameId(capture.report.entryUrl)
            val gameId = OfflineCatalogMetadata.gameId(capture.report.entryUrl)
            val catalogVersion = synchronized(lock) { catalogVersions[gameId] ?: 0 }
            try {
                store.touch(capture.report.entryUrl, capture.playedAt)
                val skip = synchronized(lock) {
                    completed[key] == capture.report ||
                        (retryAfter[key] ?: 0) > clock()
                }
                if (skip) continue
                store.save(capture.report, capture.visit, capture.playedAt, isActive = {
                    synchronized(lock) {
                        enabled &&
                            generation == token
                    }
                })
                synchronized(lock) {
                    if (!enabled || generation != token) return
                    if ((catalogVersions[gameId] ?: 0) == catalogVersion) {
                        completed[key] = capture.report
                    } else {
                        completed.remove(key)
                    }
                    retryAfter.remove(key)
                    while (completed.size > 128) completed.remove(completed.keys.first())
                }
                onSaved(store.listGames())
            } catch (_: Exception) {
                synchronized(lock) {
                    if (!enabled || generation != token) return
                    retryAfter[key] = clock() + 60_000
                }
            }
        }
    }
}
