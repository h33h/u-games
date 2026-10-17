package dev.ugames

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.InterruptedIOException
import java.util.zip.DeflaterOutputStream
import java.util.zip.GZIPOutputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class OfflineResponseBodyTest {
    @Test fun gzipAndDeflateBodiesAreDecodedBeforeChromiumReceivesInterceptedData() {
        val original = "window.gameStarted = true;".toByteArray()
        for (encoding in listOf("gzip", "deflate")) {
            val bytes = ByteArrayOutputStream()
            (
                if (encoding ==
                    "gzip"
                ) {
                    GZIPOutputStream(bytes)
                } else {
                    DeflaterOutputStream(bytes)
                }
                ).use { it.write(original) }
            val body = OfflineResponseBody.open(
                bytes.toByteArray().inputStream(),
                mapOf("Content-Encoding" to encoding)
            )
            assertArrayEquals(original, body.readBytes())
        }
        assertEquals(
            mapOf("Access-Control-Allow-Origin" to "*"),
            OfflineResponseBody.headers(
                mapOf(
                    "Content-Encoding" to "gzip",
                    "content-length" to "25",
                    "Access-Control-Allow-Origin" to "*"
                )
            )
        )
    }

    @Test fun brotliPrecompressedGameScriptsAreDecodedForInterceptedResponses() {
        val compressed = "1b1f00a8a444769a90420c91448a5c4e55688286a805".chunked(2).map {
            it.toInt(16).toByte()
        }.toByteArray()
        val body = OfflineResponseBody.open(
            compressed.inputStream(),
            mapOf("content-encoding" to "br")
        )
        assertEquals("window.dynamicResource=\"loaded\";", body.bufferedReader().readText())
    }

    @Test fun corruptGzipTrailerIsReportedOnceOnlyWhenTheBodyIsRead() {
        val bytes = gzip("window.cachedResource=true;".toByteArray())
        bytes[bytes.size - 8] = (bytes[bytes.size - 8].toInt() xor 1).toByte()
        var failures = 0
        val body = OfflineResponseBody.open(
            bytes.inputStream(),
            mapOf("Content-Encoding" to "gzip")
        ) {
            failures++
        }
        assertEquals(0, failures)
        assertThrows(java.util.zip.ZipException::class.java) { body.readBytes() }
        assertEquals(1, failures)
        runCatching { body.readBytes() }
        assertEquals(1, failures)
    }

    @Test fun closedAndCancelledReadsDoNotReportCacheCorruption() {
        var failures = 0
        val closed = OfflineResponseBody.open(
            gzip(byteArrayOf(1)).inputStream(),
            mapOf("Content-Encoding" to "gzip")
        ) {
            failures++
        }
        closed.close()
        assertThrows(IOException::class.java) { closed.read() }
        val cancelled = OfflineResponseBody.open(
            object : InputStream() {
                override fun read(): Int = throw InterruptedIOException("cancelled")
            },
            emptyMap()
        ) { failures++ }
        assertThrows(InterruptedIOException::class.java) { cancelled.read() }
        val interrupted = OfflineResponseBody.open(
            object : InputStream() {
                override fun read(): Int = throw IOException("interrupted")
            },
            emptyMap()
        ) { failures++ }
        Thread.currentThread().interrupt()
        try {
            assertThrows(IOException::class.java) { interrupted.read() }
        } finally {
            Thread.interrupted()
        }
        assertEquals(0, failures)
    }

    private fun gzip(bytes: ByteArray): ByteArray = ByteArrayOutputStream().also { output ->
        GZIPOutputStream(output).use { it.write(bytes) }
    }.toByteArray()
}
