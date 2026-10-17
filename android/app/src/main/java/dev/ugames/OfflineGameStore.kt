package dev.ugames

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import org.json.JSONObject

data class OfflineDownloadMetadata(
    val mimeType: String,
    val encoding: String?,
    val headers: Map<String, String>
)

fun interface OfflineDownloader {
    fun download(url: String, target: File, maxBytes: Long): OfflineDownloadMetadata
}

data class SavedOfflineResource(
    val file: File,
    val mimeType: String,
    val encoding: String?,
    val headers: Map<String, String>,
    val size: Long
)

data class SavedOfflineGame(
    val id: String,
    val entryUrl: String,
    val title: String,
    val savedAt: Long,
    val totalBytes: Long,
    val storage: Map<String, String>,
    val environment: String,
    private val resources: Map<String, SavedOfflineResource>,
    val lastPlayedAt: Long = savedAt,
    internal val visitId: String? = null,
    val cover: SavedOfflineResource? = null,
    internal val coverUrl: String? = null
) {
    val resourceCount get() = resources.size
    internal val resourceUrls get() = resources.keys
    internal val directory get() = resources.values.firstOrNull()?.file?.parentFile
    val coverLocalUrl get() = cover?.let { "https://yandex.ru/games/.ugames-cache-cover/$id" }

    fun resource(url: String): SavedOfflineResource? =
        OfflineResourcePolicy.normalize(url)?.let(resources::get)

    fun configurationScript(): String = "window.__UGamesOfflineConfig=" + JSONObject()
        .put("gameId", id).put("url", entryUrl).put("storage", JSONObject(storage))
        .put("environment", JSONObject(environment)).toString() + ";"
}

/** Owns the exact immutable snapshot used by one replay window. */
class OfflineReplayLease internal constructor(
    val game: SavedOfflineGame,
    private val release: () -> Unit
) : AutoCloseable {
    private val closed = java.util.concurrent.atomic.AtomicBoolean(false)
    override fun close() {
        if (closed.compareAndSet(false, true)) release()
    }
}

/** Network work never holds [lock]. Only completed manifests become visible to readers. */
class OfflineGameStore(
    private val root: File,
    private val filter: AdResourceFilter,
    private val downloader: OfflineDownloader? = null,
    private val maxCacheBytes: Long = 2L * 1024 * 1024 * 1024,
    private val clock: () -> Long = System::currentTimeMillis
) {
    private val lock = Any()
    private val saveLock = Any()
    private val leases = ConcurrentHashMap<String, AtomicInteger>()
    private val recency = ConcurrentHashMap<String, Long>()
    private val catalog = linkedMapOf<String, OfflineCatalogMetadata>()
    private var initialized = false
    private var sequence = 0L
    private var reservation: Pair<File, Long>? = null

    fun save(
        report: OfflineCaptureReport,
        visitId: String? = null,
        playedAt: Long = playTime(),
        isActive: () -> Boolean = { true },
        progress: (Int, Int, Long) -> Unit = { _, _, _ -> }
    ): SavedOfflineGame = synchronized(saveLock) {
        val entry =
            OfflineResourcePolicy.normalize(report.entryUrl)
                ?: throw IOException("Некорректный адрес игры")
        if (!report.ready ||
            !OfflineResourcePolicy.isGameUrl(entry)
        ) {
            throw IOException("Игра ещё не готова к сохранению")
        }
        val id = gameId(entry)
        val previous = synchronized(lock) {
            initialize()
            if (isPinned(id)) throw IOException("Игра открыта без сети")
            games().firstOrNull { it.id == id }
        }
        val extending = visitId != null && previous?.visitId == visitId
        touch(entry, playedAt)
        // A fresh visit may discard its old, unpinned snapshot only after older games.
        val protected = if (extending) setOf(id) else emptySet()
        val urls = (
            (if (extending) previous!!.resourceUrls.toList() else emptyList()) +
                listOf(entry) +
                report.resources
            )
            .mapNotNull(OfflineResourcePolicy::normalize).distinct()
            .filter { !filter.shouldBlock(it) && OfflineResourcePolicy.canSave(entry, it) }
        if (entry !in urls ||
            urls.size > OfflineResourcePolicy.MAX_RESOURCES
        ) {
            throw IOException("Слишком много файлов игры")
        }
        val metadata = synchronized(lock) { catalog[OfflineCatalogMetadata.gameId(entry)] }
        val temporary = synchronized(lock) {
            File(root, ".partial-${UUID.randomUUID()}").also {
                if (!it.mkdir()) throw IOException("Не удалось подготовить сохранение")
            }
        }
        val destination = if (extending) requireNotNull(previous!!.directory) else temporary
        val moved = mutableListOf<File>()
        var published = false
        var publishedDirectory = destination
        try {
            val resources = JSONObject()
            var total = 0L
            val transport =
                downloader
                    ?: HttpOfflineDownloader(entry, filter, maxCacheBytes, isActive = isActive)
            urls.forEachIndexed { index, url ->
                checkCancelled(isActive)
                val old = if (extending) previous!!.resource(url) else null
                val resource = old ?: run {
                    val file = File(temporary, digest(url))
                    val response = download(transport, url, file, protected, isActive = isActive)
                    if (url == entry &&
                        (file.length() == 0L || response.mimeType.lowercase() !in HTML_TYPES)
                    ) {
                        throw IOException("Сервис не вернул страницу игры")
                    }
                    SavedOfflineResource(
                        file,
                        response.mimeType,
                        response.encoding,
                        response.headers,
                        file.length()
                    )
                }
                total += resource.size
                if (total > maxCacheBytes) throw IOException("Игра больше доступного кэша")
                resources.put(url, resourceJson(resource))
                progress(index + 1, urls.size, total)
            }
            val coverUrl = metadata?.cover ?: if (extending) previous?.coverUrl else null
            var cover = if (extending && previous?.coverUrl == coverUrl) previous?.cover else null
            if (cover == null && coverUrl != null) {
                val file = File(temporary, "cover-${digest(coverUrl)}")
                try {
                    val response = download(
                        downloader
                            ?: HttpOfflineDownloader(
                                entry,
                                filter,
                                maxCacheBytes,
                                coverOnly = true,
                                isActive = isActive
                            ),
                        coverUrl,
                        file,
                        setOf(id),
                        cover = true,
                        isActive = isActive
                    )
                    if (!isRaster(
                            file,
                            response.mimeType
                        )
                    ) {
                        throw IOException("Некорректная обложка")
                    }
                    cover =
                        SavedOfflineResource(
                            file,
                            response.mimeType,
                            response.encoding,
                            emptyMap(),
                            file.length()
                        )
                } catch (error: Exception) {
                    synchronized(lock) { file.delete() }
                    checkCancelled(isActive)
                    // Artwork is optional: a broken cover must not discard a playable package.
                }
            }
            val played = synchronized(lock) {
                maxOf(
                    playedAt,
                    recency[id] ?: 0,
                    previous?.lastPlayedAt ?: 0
                )
            }
            val manifest = JSONObject().put("version", 1).put("id", id)
                .put("entryUrl", OfflineResourcePolicy.navigationUrl(report.entryUrl))
                .put("title", (metadata?.title ?: report.title).take(200)).put("savedAt", clock())
                .put("lastPlayedAt", played).put("visitId", visitId ?: JSONObject.NULL)
                .put(
                    "totalBytes",
                    total + (cover?.size ?: 0)
                ).put("storage", JSONObject(report.storage))
                .put("environment", JSONObject(report.environment)).put("resources", resources)
            cover?.let { manifest.put("cover", resourceJson(it).put("url", coverUrl)) }
            var bytes = manifest.toString().toByteArray(Charsets.UTF_8)
            if (bytes.size >
                OfflineResourcePolicy.MAX_METADATA_BYTES
            ) {
                throw IOException("Слишком много данных игры")
            }
            synchronized(lock) {
                checkCancelled(isActive)
                try {
                    ensureCapacity(bytes.size.toLong() + 8, protected)
                } catch (error: IOException) {
                    if (cover?.file?.parentFile != temporary) throw error
                    cover.file.delete()
                    manifest.remove("cover")
                    manifest.put("totalBytes", total)
                    bytes = manifest.toString().toByteArray(Charsets.UTF_8)
                    ensureCapacity(bytes.size.toLong() + 8, protected)
                }
                if (!acquireMutation(id)) throw IOException("Игра открыта без сети")
                try {
                    val stagedManifest = File(temporary, MANIFEST)
                    FileOutputStream(stagedManifest).use {
                        it.write(bytes)
                        it.fd.sync()
                    }
                    if (extending) {
                        temporary.listFiles().orEmpty().filter {
                            it != stagedManifest
                        }.forEach { file ->
                            val target = File(destination, file.name)
                            if (target.exists() ||
                                !file.renameTo(target)
                            ) {
                                throw IOException("Не удалось обновить файлы игры")
                            }
                            moved += target
                        }
                        // Existing resources stay immutable; failed updates keep the old manifest.
                        if (!stagedManifest.renameTo(
                                File(destination, MANIFEST)
                            )
                        ) {
                            throw IOException("Не удалось обновить игру")
                        }
                        published = true
                    } else {
                        if (readGame(temporary) ==
                            null
                        ) {
                            throw IOException("Не удалось проверить файлы игры")
                        }
                        val target = File(root, "$id-${UUID.randomUUID()}")
                        if (!temporary.renameTo(
                                target
                            )
                        ) {
                            throw IOException("Не удалось завершить сохранение")
                        }
                        published = true
                        publishedDirectory = target
                    }
                    recency.merge(id, played) { a, b -> maxOf(a, b) }
                    persistPlayTime(id, requireNotNull(recency[id]))
                    val game = readGame(publishedDirectory)
                        ?: throw IOException("Сохранённые файлы повреждены")
                    cleanupResources(game)
                    root.listFiles().orEmpty().filter {
                        it != game.directory &&
                            it.name.startsWith("$id-")
                    }
                        .forEach { it.deleteRecursively() }
                    temporary.deleteRecursively()
                    return@synchronized game
                } finally {
                    releaseMutation(id)
                }
            }
        } catch (error: Exception) {
            synchronized(lock) {
                if (!published) temporary.deleteRecursively()
                if (!published) moved.forEach(File::delete)
            }
            throw error
        }
    }

    fun listGames(): List<SavedOfflineGame> = synchronized(lock) {
        initialize()
        games()
    }

    /** Report delivery records recency without waiting for file work or network transport. */
    fun notePlayed(entryUrl: String, playedAt: Long) {
        recency.merge(gameId(entryUrl), playedAt) { a, b -> maxOf(a, b) }
    }

    /** Persistence runs on the index worker; saving completion never creates a newer play time. */
    fun touch(entryUrl: String, playedAt: Long = playTime()) = synchronized(lock) {
        initialize()
        val id = gameId(entryUrl)
        val value = recency.merge(id, playedAt) { a, b -> maxOf(a, b) }!!
        if (root.listFiles().orEmpty().any {
                it.name.startsWith("$id-")
            }
        ) {
            persistPlayTime(id, value)
        }
    }

    private fun persistPlayTime(id: String, playedAt: Long) {
        val file = File(root, ".played-$id")
        if (maxOf(0, 8 - file.length()) <= availableBytes()) {
            FileOutputStream(file).use {
                java.io.DataOutputStream(it).writeLong(playedAt)
                it.fd.sync()
            }
        }
    }

    /** Runs on the index worker: pin first, then resolve the current manifest under the store lock. */
    fun acquire(id: String, playedAt: Long = playTime()): OfflineReplayLease? = synchronized(lock) {
        initialize()
        if (!id.matches(ID) || !pin(id)) return@synchronized null
        try {
            val game = games().firstOrNull { it.id == id }
            if (game == null) {
                unpin(id)
                null
            } else {
                notePlayed(game.entryUrl, playedAt)
                val currentTime = requireNotNull(recency[id])
                runCatching { persistPlayTime(id, currentTime) }
                OfflineReplayLease(game.copy(lastPlayedAt = currentTime)) { unpin(id) }
            }
        } catch (error: Exception) {
            unpin(id)
            throw error
        }
    }

    /** Acquiring a replay lease never waits on disk work or a download lock. */
    fun pin(id: String): Boolean {
        val state = leases.computeIfAbsent(id) { AtomicInteger(0) }
        while (true) {
            val count = state.get()
            if (count < 0) return false
            if (state.compareAndSet(count, count + 1)) return true
        }
    }
    fun unpin(id: String) {
        leases[id]?.let { state ->
            while (true) {
                val count = state.get()
                if (count <=
                    0 ||
                    state.compareAndSet(count, count - 1)
                ) {
                    break
                }
            }
        }
    }
    private fun isPinned(id: String) = (leases[id]?.get() ?: 0) > 0
    private fun acquireMutation(id: String) = leases.computeIfAbsent(id) {
        AtomicInteger(0)
    }.compareAndSet(0, -1)
    private fun releaseMutation(id: String) {
        leases[id]?.set(0)
    }

    fun rememberCatalog(metadata: OfflineCatalogMetadata): Boolean = synchronized(lock) {
        initialize()
        if (!metadata.isValid() || catalog[metadata.gameId] == metadata) return@synchronized false
        catalog.remove(metadata.gameId)
        catalog[metadata.gameId] = metadata
        while (catalog.size > 128) catalog.remove(catalog.keys.first())
        val bytes = JSONObject().also { json ->
            catalog.forEach { (id, item) -> json.put(id, item.json()) }
        }
            .toString().toByteArray(Charsets.UTF_8)
        val target = File(root, CATALOG)
        if (bytes.size <= MAX_CATALOG_BYTES && bytes.size <= availableBytes()) {
            val staging = File(root, ".catalog-new")
            try {
                FileOutputStream(staging).use {
                    it.write(bytes)
                    it.fd.sync()
                }
                if (!staging.renameTo(target)) staging.delete()
            } finally {
                staging.delete()
            }
        }
        true
    }

    fun delete(id: String) = synchronized(lock) {
        initialize()
        if (!id.matches(ID) || isPinned(id)) return@synchronized
        if (acquireMutation(id)) {
            try {
                removeGame(id)
            } finally {
                releaseMutation(id)
            }
        }
    }

    private fun download(
        transport: OfflineDownloader,
        url: String,
        target: File,
        protected: Set<String>,
        cover: Boolean = false,
        isActive: () -> Boolean
    ): OfflineDownloadMetadata {
        while (true) {
            val allowance = synchronized(lock) {
                checkCancelled(isActive)
                if (!cover) ensureCapacity(1, protected)
                val bytes = minOf(availableBytes(), if (cover) MAX_COVER_BYTES else maxCacheBytes)
                if (bytes <= 0) throw IOException("Кэш заполнен")
                reservation = target to bytes
                bytes
            }
            try {
                val response = transport.download(url, target, allowance)
                checkCancelled(isActive)
                if (!target.isFile) throw IOException("Файл не скачан")
                if (target.length() > allowance) throw OfflineCacheCapacityException()
                return response
            } catch (error: Exception) {
                synchronized(lock) {
                    target.delete()
                    reservation = null
                    if (error !is OfflineCacheCapacityException || cover ||
                        !evictOne(protected)
                    ) {
                        throw error
                    }
                }
            } finally {
                synchronized(lock) { reservation = null }
            }
        }
    }

    private fun initialize() {
        if (initialized) return
        if (!root.isDirectory && !root.mkdirs()) throw IOException("Не удалось создать папку игр")
        root.listFiles().orEmpty().filter {
            it.name.startsWith(".partial-") ||
                it.name == ".catalog-new"
        }
            .forEach { it.deleteRecursively() }
        root.listFiles().orEmpty().filter {
            it.name.startsWith(".played-") && it.length() == 8L
        }.forEach { file ->
            val id = file.name.removePrefix(".played-")
            if (id.matches(ID)) {
                runCatching {
                    val value = file.inputStream().use { java.io.DataInputStream(it).readLong() }
                    recency.merge(id, value) { a, b -> maxOf(a, b) }
                }
            }
        }
        val metadata = File(root, CATALOG)
        if (metadata.isFile && metadata.length() <= MAX_CATALOG_BYTES) {
            runCatching {
                val json = JSONObject(metadata.readText())
                json.keys().asSequence().take(128).forEach { key ->
                    val item = json.getJSONObject(key)
                    val record =
                        OfflineCatalogMetadata(
                            key,
                            item.getString("url"),
                            item.getString("title"),
                            item.optString("cover").takeIf {
                                it.isNotEmpty()
                            }
                        )
                    if (record.isValid()) catalog[key] = record
                }
            }
        }
        root.listFiles().orEmpty().filter { it.isDirectory && !it.name.startsWith('.') }.forEach {
            val game = readGame(it)
            if (game == null) it.deleteRecursively() else cleanupResources(game)
        }
        initialized = true
        while (availableBytes() < 0 &&
            evictOne(emptySet())
        ) { /* Enforce the shared budget for legacy snapshots too. */ }
    }

    private fun games() = root.listFiles().orEmpty().filter {
        it.isDirectory &&
            !it.name.startsWith('.')
    }
        .mapNotNull(::readGame).sortedWith(
            compareByDescending<SavedOfflineGame> {
                it.lastPlayedAt
            }.thenByDescending { it.savedAt }
        )
        .distinctBy { it.id }

    private fun readGame(directory: File): SavedOfflineGame? {
        return try {
            val manifestFile = File(directory, MANIFEST)
            if (!manifestFile.isFile ||
                manifestFile.length() > OfflineResourcePolicy.MAX_METADATA_BYTES
            ) {
                null
            } else {
                val manifest = JSONObject(manifestFile.readText())
                val id = manifest.getString("id")
                val entry = manifest.getString("entryUrl")
                if (manifest.getInt("version") != 1 || !id.matches(ID) ||
                    !OfflineResourcePolicy.isGameUrl(entry) ||
                    id != gameId(entry)
                ) {
                    return null
                }
                val resources = manifest.getJSONObject("resources")
                if (resources.length() !in 1..OfflineResourcePolicy.MAX_RESOURCES) return null
                val mapped = resources.keys().asSequence().associateWith { url ->
                    if (!OfflineResourcePolicy.canSave(entry, url) ||
                        filter.shouldBlock(url)
                    ) {
                        return null
                    }
                    val data = resources.getJSONObject(url)
                    if (data.getString("file") != digest(url)) return null
                    readResource(directory, data) ?: return null
                }
                val coverData = manifest.optJSONObject("cover")
                val coverUrl = coverData?.optString("url")
                val cover = if (coverData == null) {
                    null
                } else {
                    if (!OfflineCatalogMetadata.isCoverUrl(coverUrl.orEmpty()) ||
                        coverData.getString("file") != "cover-${digest(coverUrl!!)}"
                    ) {
                        return null
                    }
                    (readResource(directory, coverData) ?: return null).also {
                        if (it.size > MAX_COVER_BYTES ||
                            !isRaster(it.file, it.mimeType)
                        ) {
                            return null
                        }
                    }
                }
                val total = mapped.values.sumOf { it.size } + (cover?.size ?: 0)
                val entryKey = OfflineResourcePolicy.normalize(entry)
                if (mapped[entryKey]?.size == 0L || entryKey !in mapped ||
                    total != manifest.getLong("totalBytes") ||
                    total > maxCacheBytes
                ) {
                    return null
                }
                val storage = manifest.getJSONObject("storage")
                SavedOfflineGame(
                    id, entry, manifest.getString("title"), manifest.getLong("savedAt"), total,
                    storage.keys().asSequence().associateWith(
                        storage::getString
                    ),
                    manifest.getJSONObject("environment").toString(), mapped,
                    maxOf(
                        manifest.optLong("lastPlayedAt", manifest.getLong("savedAt")),
                        recency[id] ?: 0
                    ),
                    manifest.optString("visitId").takeUnless {
                        it.isEmpty() || it == "null"
                    },
                    cover, coverUrl
                )
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun readResource(directory: File, data: JSONObject): SavedOfflineResource? {
        val name = data.getString("file")
        if (!name.matches(Regex("(cover-)?[a-f0-9]{64}"))) return null
        val file = File(directory, name)
        val size = data.getLong("size")
        if (!file.isFile || size < 0 || size != file.length()) return null
        return SavedOfflineResource(
            file,
            data.getString("mime"),
            data.optString("encoding").takeUnless {
                it.isEmpty() ||
                    it == "null"
            },
            data.getJSONObject("headers").let { headers ->
                headers.keys().asSequence().associateWith(headers::getString)
            },
            size
        )
    }

    private fun cleanupResources(game: SavedOfflineGame) {
        val names = game.resourceUrls.mapNotNull { game.resource(it)?.file?.name }.toMutableSet()
        names.add(MANIFEST)
        game.cover?.let { names.add(it.file.name) }
        game.directory?.listFiles().orEmpty().filter { it.name !in names }.forEach { it.delete() }
    }

    private fun resourceJson(resource: SavedOfflineResource) =
        JSONObject().put("file", resource.file.name)
            .put("mime", resource.mimeType).put("encoding", resource.encoding ?: JSONObject.NULL)
            .put("headers", JSONObject(resource.headers)).put("size", resource.size)

    private fun availableBytes(): Long {
        val actual = root.walkTopDown().filter { it.isFile }.sumOf { it.length() }
        val reserved = reservation?.let { (file, limit) -> maxOf(0, limit - file.length()) } ?: 0
        return maxCacheBytes - actual - reserved
    }

    private fun ensureCapacity(extra: Long, protected: Set<String>) {
        while (extra > availableBytes()) {
            if (!evictOne(protected)) throw IOException("Кэш заполнен")
        }
    }

    private fun evictOne(protected: Set<String>): Boolean {
        for (candidate in games().asReversed()) {
            if (candidate.id in protected || !acquireMutation(candidate.id)) continue
            try {
                removeGame(candidate.id)
            } finally {
                releaseMutation(candidate.id)
            }
            return true
        }
        return false
    }

    private fun removeGame(id: String) {
        root.listFiles().orEmpty().filter { it.name.startsWith("$id-") || it.name == ".played-$id" }
            .forEach {
                if (!it.deleteRecursively()) throw IOException("Не удалось удалить файлы игры")
            }
    }

    private fun playTime(): Long = synchronized(lock) {
        maxOf(clock(), sequence + 1).also {
            sequence =
                it
        }
    }
    private fun checkCancelled(isActive: () -> Boolean = { true }) {
        if (Thread.currentThread().isInterrupted ||
            !isActive()
        ) {
            throw IOException("Сохранение прервано")
        }
    }

    companion object {
        private const val MANIFEST = "manifest.json"
        private const val CATALOG = ".catalog.json"
        private const val MAX_CATALOG_BYTES = 128 * 1024
        private const val MAX_COVER_BYTES = 1024L * 1024
        private val ID = Regex("[a-f0-9]{64}")
        private val HTML_TYPES = setOf("text/html", "application/xhtml+xml")
        fun gameId(entry: String): String =
            digest(requireNotNull(OfflineResourcePolicy.normalize(entry)).substringBefore('?'))
        private fun digest(value: String): String = MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
        private fun isRaster(file: File, mime: String): Boolean {
            val head = ByteArray(32)
            val count = file.inputStream().use { it.read(head) }
            if (count < 12) return false
            return when (mime.lowercase()) {
                "image/png" -> head.take(8) ==
                    listOf(137, 80, 78, 71, 13, 10, 26, 10).map(Int::toByte)

                "image/jpeg" -> head[0] == 0xff.toByte() && head[1] == 0xd8.toByte() &&
                    head[2] == 0xff.toByte()

                "image/gif" -> String(head, 0, 6, Charsets.US_ASCII) in setOf("GIF87a", "GIF89a")

                "image/webp" -> String(head, 0, 4, Charsets.US_ASCII) == "RIFF" &&
                    String(head, 8, 4, Charsets.US_ASCII) == "WEBP"

                "image/avif" -> String(head, 4, 4, Charsets.US_ASCII) == "ftyp" &&
                    String(head, 8, count - 8, Charsets.US_ASCII).contains("avif")

                else -> false
            }
        }
    }
}

private class OfflineCacheCapacityException : IOException("Недостаточно места в кэше")

/** Public assets only. No WebView cookies, authorization headers or WebView cache are read. */
private class HttpOfflineDownloader(
    private val entry: String,
    private val filter: AdResourceFilter,
    private val totalBudget: Long,
    private val coverOnly: Boolean = false,
    private val isActive: () -> Boolean = { true }
) : OfflineDownloader {
    override fun download(url: String, target: File, maxBytes: Long): OfflineDownloadMetadata {
        var current = url
        repeat(6) {
            if (Thread.currentThread().isInterrupted ||
                !isActive()
            ) {
                throw IOException("Сохранение прервано")
            }
            val allowed = if (coverOnly) {
                OfflineCatalogMetadata.isCoverUrl(
                    current
                )
            } else {
                OfflineResourcePolicy.canSave(entry, current)
            }
            if (!allowed ||
                filter.shouldBlock(current)
            ) {
                throw IOException("Сервис перенаправил файл за пределы игры")
            }
            val connection = URL(current).openConnection() as HttpURLConnection
            try {
                connection.instanceFollowRedirects = false
                connection.useCaches = false
                connection.connectTimeout = 20000
                connection.readTimeout = 30000
                connection.setRequestProperty("Accept-Encoding", "identity")
                val status = connection.responseCode
                if (status in 300..399) {
                    current =
                        OfflineResourcePolicy.normalize(
                            URI(current).resolve(
                                connection.getHeaderField("Location")
                                    ?: throw IOException("Пустое перенаправление")
                            ).toString()
                        )
                            ?: throw IOException("Небезопасное перенаправление")
                    return@repeat
                }
                if (status !in 200..299 || status == 204 ||
                    status == 206
                ) {
                    throw IOException("Не удалось скачать файл (HTTP $status)")
                }
                val expected = connection.contentLengthLong
                if (expected > totalBudget) throw IOException("Игра больше доступного кэша")
                if (expected > maxBytes) throw OfflineCacheCapacityException()
                var size = 0L
                connection.inputStream.use { input ->
                    FileOutputStream(target).use { output ->
                        val buffer = ByteArray(32 * 1024)
                        while (true) {
                            if (Thread.currentThread().isInterrupted ||
                                !isActive()
                            ) {
                                throw IOException("Сохранение прервано")
                            }
                            val count = input.read(buffer)
                            if (count < 0) break
                            if (!isActive()) throw IOException("Сохранение прервано")
                            size += count
                            if (size > maxBytes) throw OfflineCacheCapacityException()
                            output.write(buffer, 0, count)
                        }
                        output.fd.sync()
                    }
                }
                if (expected >= 0 && expected != size) throw IOException("Файл скачан не полностью")
                val contentType = connection.contentType.orEmpty()
                val mime = contentType.substringBefore(';').trim().ifEmpty {
                    "application/octet-stream"
                }
                val charset = Regex(
                    "charset\\s*=\\s*[\"']?([^;\"'\\s]+)",
                    RegexOption.IGNORE_CASE
                ).find(contentType)?.groupValues?.get(1)
                val allowedHeaders =
                    setOf(
                        "content-type",
                        "content-encoding",
                        "access-control-allow-origin",
                        "access-control-allow-credentials",
                        "cross-origin-resource-policy",
                        "cross-origin-opener-policy",
                        "cross-origin-embedder-policy",
                        "content-security-policy"
                    )
                val headers = connection.headerFields.entries.filter {
                    it.key?.lowercase() in
                        allowedHeaders &&
                        !it.value.isNullOrEmpty()
                }.associate { it.key!! to it.value.joinToString(", ") }
                return OfflineDownloadMetadata(mime, charset, headers)
            } finally {
                connection.disconnect()
            }
        }
        throw IOException("Слишком много перенаправлений")
    }
}
