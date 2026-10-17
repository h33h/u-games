package dev.ugames

import java.io.FilterInputStream
import java.io.IOException
import java.io.InputStream
import java.io.InterruptedIOException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.zip.GZIPInputStream
import java.util.zip.InflaterInputStream
import org.brotli.dec.BrotliInputStream

/** WebResourceResponse treats its stream as decoded bytes, even with Content-Encoding present. */
object OfflineResponseBody {
    fun open(
        source: InputStream,
        headers: Map<String, String>,
        readFailure: () -> Unit = {}
    ): InputStream {
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
            }.let { ReadGuard(it, readFailure) }
        } catch (error: Exception) {
            source.close()
            throw error
        }
    }

    private class ReadGuard(private val decoded: InputStream, private val failed: () -> Unit) :
        FilterInputStream(decoded) {
        private val closed = AtomicBoolean(false)
        private val reported = AtomicBoolean(false)

        override fun read(): Int = reading { decoded.read() }
        override fun read(buffer: ByteArray, offset: Int, length: Int): Int =
            reading { decoded.read(buffer, offset, length) }
        override fun skip(count: Long): Long = reading { decoded.skip(count) }

        override fun close() {
            closed.set(true)
            super.close()
        }

        private inline fun <T> reading(action: () -> T): T = try {
            action()
        } catch (error: IOException) {
            if (!closed.get() && !Thread.currentThread().isInterrupted &&
                error !is InterruptedIOException && reported.compareAndSet(false, true)
            ) {
                failed()
            }
            throw error
        }
    }

    fun headers(original: Map<String, String>): Map<String, String> = original.filterKeys {
        !it.equals("Content-Encoding", true) && !it.equals("Content-Length", true)
    }
}
