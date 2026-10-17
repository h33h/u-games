package dev.ugames

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.security.MessageDigest
import java.util.UUID
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
    private val resources: Map<String, SavedOfflineResource>
) {
    val resourceCount get() = resources.size
    fun resource(url: String): SavedOfflineResource? =
        OfflineResourcePolicy.normalize(url)?.let(resources::get)

    fun configurationScript(): String = "window.__UGamesOfflineConfig=" + JSONObject()
        .put("gameId", id).put("url", entryUrl).put("storage", JSONObject(storage))
        .put("environment", JSONObject(environment)).toString() + ";"
}

/** Immutable directories are published by one rename only after every response and manifest is valid. */
class OfflineGameStore(
    private val root: File,
    private val filter: AdResourceFilter,
    private val downloader: OfflineDownloader? = null,
    private val maxGameBytes: Long = 512L * 1024 * 1024
) {
    @Synchronized
    fun save(
        report: OfflineCaptureReport,
        progress: (Int, Int, Long) -> Unit = { _, _, _ -> }
    ): SavedOfflineGame {
        val entry = OfflineResourcePolicy.normalize(report.entryUrl)
            ?: throw IOException("Некорректный адрес игры")
        if (!report.ready || !OfflineResourcePolicy.isGameUrl(entry)) {
            throw IOException("Игра ещё не готова к сохранению")
        }
        val urls = (listOf(entry) + report.resources).mapNotNull(OfflineResourcePolicy::normalize)
            .distinct().filter {
                !filter.shouldBlock(it) && OfflineResourcePolicy.canSave(entry, it)
            }
        if (entry !in urls || urls.size > OfflineResourcePolicy.MAX_RESOURCES) {
            throw IOException("Слишком много файлов игры")
        }
        if (!root.isDirectory && !root.mkdirs()) throw IOException("Не удалось создать папку игр")
        val id = digest(entry.substringBefore('?'))
        val temporary = File(root, ".partial-${UUID.randomUUID()}")
        if (!temporary.mkdir()) throw IOException("Не удалось подготовить сохранение")
        try {
            val resources = JSONObject()
            var total = 0L
            val transport = downloader ?: HttpOfflineDownloader(entry, filter)
            urls.forEachIndexed { index, url ->
                if (Thread.currentThread().isInterrupted) throw IOException("Сохранение прервано")
                val name = digest(url)
                val file = File(temporary, name)
                val response = transport.download(url, file, maxGameBytes - total)
                if (!file.isFile ||
                    file.length() > maxGameBytes - total
                ) {
                    throw IOException("Игра больше 512 МБ")
                }
                if (url == entry &&
                    (
                        file.length() == 0L || response.mimeType.lowercase() !in
                            setOf("text/html", "application/xhtml+xml")
                        )
                ) {
                    throw IOException("Сервис не вернул страницу игры")
                }
                total += file.length()
                resources.put(
                    url,
                    JSONObject().put("file", name).put("mime", response.mimeType)
                        .put("encoding", response.encoding ?: JSONObject.NULL)
                        .put("headers", JSONObject(response.headers)).put("size", file.length())
                )
                progress(index + 1, urls.size, total)
            }
            val manifest = JSONObject().put("version", 1).put("id", id)
                .put("entryUrl", OfflineResourcePolicy.navigationUrl(report.entryUrl))
                .put("title", report.title.take(200)).put("savedAt", System.currentTimeMillis())
                .put("totalBytes", total).put("storage", JSONObject(report.storage))
                .put("environment", JSONObject(report.environment)).put("resources", resources)
                .toString().toByteArray(Charsets.UTF_8)
            if (manifest.size >
                OfflineResourcePolicy.MAX_METADATA_BYTES
            ) {
                throw IOException("Слишком много данных игры")
            }
            FileOutputStream(File(temporary, MANIFEST)).use {
                it.write(manifest)
                it.fd.sync()
            }
            if (readGame(temporary) == null) throw IOException("Не удалось проверить файлы игры")
            if (Thread.currentThread().isInterrupted) throw IOException("Сохранение прервано")
            val published = File(root, "$id-${UUID.randomUUID()}")
            if (!temporary.renameTo(published)) throw IOException("Не удалось завершить сохранение")
            val game = readGame(published) ?: throw IOException("Сохранённые файлы повреждены")
            root.listFiles()?.filter {
                it != published && it.name.startsWith("$id-")
            }?.forEach { it.deleteRecursively() }
            return game
        } catch (error: Exception) {
            temporary.deleteRecursively()
            throw error
        }
    }

    @Synchronized
    fun listGames(): List<SavedOfflineGame> = root.listFiles().orEmpty()
        .filter { it.isDirectory && !it.name.startsWith('.') }.mapNotNull(::readGame)
        .sortedByDescending { it.savedAt }.distinctBy { it.id }

    @Synchronized
    fun delete(id: String) {
        if (!id.matches(Regex("[a-f0-9]{64}"))) return
        root.listFiles()?.filter { it.name.startsWith("$id-") }?.forEach {
            if (!it.deleteRecursively()) throw IOException("Не удалось удалить файлы игры")
        }
    }

    private fun readGame(directory: File): SavedOfflineGame? {
        return try {
            val manifestFile = File(directory, MANIFEST)
            if (!manifestFile.isFile ||
                manifestFile.length() > OfflineResourcePolicy.MAX_METADATA_BYTES
            ) {
                return null
            }
            val manifest = JSONObject(manifestFile.readText())
            val id = manifest.getString("id")
            val entry = manifest.getString("entryUrl")
            if (manifest.getInt("version") != 1 || !id.matches(Regex("[a-f0-9]{64}")) ||
                !OfflineResourcePolicy.isGameUrl(entry) ||
                id !=
                digest(requireNotNull(OfflineResourcePolicy.normalize(entry)).substringBefore('?'))
            ) {
                return null
            }
            val resources = manifest.getJSONObject("resources")
            if (resources.length() !in 1..OfflineResourcePolicy.MAX_RESOURCES) return null
            val mapped = resources.keys().asSequence().associateWith { url ->
                val data = resources.getJSONObject(url)
                val name = data.getString("file")
                if (name != digest(url) || !OfflineResourcePolicy.canSave(entry, url) ||
                    filter.shouldBlock(url)
                ) {
                    return null
                }
                val file = File(directory, name)
                val size = data.getLong("size")
                if (!file.isFile || file.length() != size || size < 0) return null
                SavedOfflineResource(
                    file,
                    data.getString("mime"),
                    data.optString("encoding").takeUnless {
                        it ==
                            "null" ||
                            it.isEmpty()
                    },
                    data.getJSONObject("headers").let { headers ->
                        headers.keys().asSequence().associateWith(headers::getString)
                    },
                    size
                )
            }
            val total = mapped.values.sumOf { it.size }
            val entryKey = OfflineResourcePolicy.normalize(entry)
            if (mapped[entryKey]?.size == 0L || entryKey !in mapped ||
                total != manifest.getLong("totalBytes") ||
                total > maxGameBytes
            ) {
                return null
            }
            val storage = manifest.getJSONObject("storage")
            SavedOfflineGame(
                id,
                entry,
                manifest.getString("title"),
                manifest.getLong("savedAt"),
                total,
                storage.keys().asSequence().associateWith(storage::getString),
                manifest.getJSONObject("environment").toString(),
                mapped
            )
        } catch (_: Exception) {
            null
        }
    }

    companion object {
        private const val MANIFEST = "manifest.json"
        private fun digest(value: String): String = MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
    }
}

/** No WebView cookies, authorization headers, or WebView cache are used by the download transport. */
private class HttpOfflineDownloader(
    private val entry: String,
    private val filter: AdResourceFilter
) : OfflineDownloader {
    override fun download(url: String, target: File, maxBytes: Long): OfflineDownloadMetadata {
        var current = url
        repeat(6) {
            if (!OfflineResourcePolicy.canSave(entry, current) || filter.shouldBlock(current)) {
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
                    val location =
                        connection.getHeaderField("Location")
                            ?: throw IOException("Пустое перенаправление")
                    current =
                        OfflineResourcePolicy.normalize(URI(current).resolve(location).toString())
                            ?: throw IOException("Небезопасное перенаправление")
                    return@repeat
                }
                if (status !in 200..299 || status == 204 ||
                    status == 206
                ) {
                    throw IOException("Не удалось скачать файл (HTTP $status)")
                }
                val expected = connection.contentLengthLong
                if (expected > maxBytes) throw IOException("Игра больше 512 МБ")
                var size = 0L
                connection.inputStream.use { input ->
                    FileOutputStream(target).use { output ->
                        val buffer = ByteArray(32 * 1024)
                        while (true) {
                            if (Thread.currentThread().isInterrupted) {
                                throw IOException(
                                    "Сохранение прервано"
                                )
                            }
                            val count = input.read(buffer)
                            if (count < 0) break
                            size += count
                            if (size > maxBytes) throw IOException("Игра больше 512 МБ")
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
                val charset = Regex("charset\\s*=\\s*[\"']?([^;\"'\\s]+)", RegexOption.IGNORE_CASE)
                    .find(contentType)?.groupValues?.get(1)
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
                    it.key?.lowercase() in allowedHeaders && !it.value.isNullOrEmpty()
                }.associate { it.key!! to it.value.joinToString(", ") }
                return OfflineDownloadMetadata(mime, charset, headers)
            } finally {
                connection.disconnect()
            }
        }
        throw IOException("Слишком много перенаправлений")
    }
}
