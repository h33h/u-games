package dev.ugames

import java.io.IOException
import java.io.InputStream
import java.util.zip.GZIPInputStream
import java.util.zip.InflaterInputStream
import org.brotli.dec.BrotliInputStream

/** WebResourceResponse treats its stream as decoded bytes, even with Content-Encoding present. */
object OfflineResponseBody {
    fun open(source: InputStream, headers: Map<String, String>): InputStream {
        val encoding = headers.entries.firstOrNull {
            it.key.equals("Content-Encoding", true)
        }?.value
        return try {
            encoding.orEmpty().split(',').map {
                it.trim().lowercase()
            }.reversed().fold(source) { input, codec ->
                when (codec) {
                    "", "identity" -> input
                    "gzip", "x-gzip" -> GZIPInputStream(input)
                    "deflate" -> InflaterInputStream(input)
                    "br" -> BrotliInputStream(input)
                    else -> throw IOException("Неподдерживаемое сжатие файла")
                }
            }
        } catch (error: Exception) {
            source.close()
            throw error
        }
    }

    fun headers(original: Map<String, String>): Map<String, String> = original.filterKeys {
        !it.equals("Content-Encoding", true) && !it.equals("Content-Length", true)
    }
}
