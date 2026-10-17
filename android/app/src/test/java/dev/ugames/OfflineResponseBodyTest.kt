package dev.ugames

import java.io.ByteArrayOutputStream
import java.util.zip.DeflaterOutputStream
import java.util.zip.GZIPOutputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
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
}
