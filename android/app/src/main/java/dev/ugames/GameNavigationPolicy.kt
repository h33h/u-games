package dev.ugames

import java.net.URI

object GameNavigationPolicy {
    fun blocksDocumentRequest(
        value: String,
        mainFrame: Boolean,
        headers: Map<String, String>
    ): Boolean {
        // Inline documents created by loadDataWithBaseURL do not make outbound requests.
        if (!value.startsWith("https://", ignoreCase = true) &&
            !value.startsWith("http://", ignoreCase = true)
        ) {
            return false
        }
        fun header(name: String) =
            headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value
        val destination = header("Sec-Fetch-Dest")
        val document = mainFrame || destination in listOf("document", "iframe", "frame") ||
            (
                destination != "empty" && (
                    header("Upgrade-Insecure-Requests") == "1" ||
                        header("Accept")?.contains("text/html") == true
                    )
                )
        return document && if (mainFrame) !allows(value) else !allowsFrame(value, header("Referer"))
    }

    fun allowsFrame(value: String, source: String?): Boolean = try {
        val url = URI(value)
        val host = url.host?.lowercase().orEmpty()
        if (allows(value) || value == "about:srcdoc") {
            true
        } else if (url.scheme != "https" || url.userInfo != null || url.port !in listOf(-1, 443)) {
            false
        } else if (host.endsWith(".games.yandex.net") || host.endsWith(".games.s3.yandex.net")) {
            true
        } else {
            val origin = source?.let(::URI)
            origin != null && origin.scheme == url.scheme && origin.host?.lowercase() == host &&
                (if (origin.port == -1) 443 else origin.port) ==
                (if (url.port == -1) 443 else url.port) &&
                host !in
                listOf(
                    "yandex.ru",
                    "www.yandex.ru",
                    "yandex.com",
                    "www.yandex.com",
                    "passport.yandex.ru",
                    "passport.yandex.com",
                    "sso.passport.yandex.ru",
                    "sso.passport.yandex.com",
                    "sso.ya.ru"
                )
        }
    } catch (_: Exception) {
        false
    }

    fun allows(value: String): Boolean = try {
        val url = URI(value)
        val host = url.host?.lowercase()
        val path = url.path.orEmpty()
        value == "about:blank" || (
            url.scheme == "https" && url.userInfo == null && (url.port == -1 || url.port == 443) &&
                (
                    (
                        host in listOf(
                            "yandex.ru",
                            "www.yandex.ru",
                            "yandex.com",
                            "www.yandex.com"
                        ) &&
                            (path == "/games" || path.startsWith("/games/"))
                        ) ||
                        (
                            host in listOf("passport.yandex.ru", "passport.yandex.com") &&
                                listOf("/auth", "/registration", "/pwl-yandex").any {
                                    path == it ||
                                        path.startsWith("$it/")
                                }
                            ) ||
                        (
                            host in listOf("sso.passport.yandex.ru", "sso.passport.yandex.com") &&
                                path in listOf("/prepare", "/prepare/")
                            ) ||
                        (host == "sso.ya.ru" && path in listOf("/sync", "/sync/"))
                    )
            )
    } catch (_: Exception) {
        false
    }
}
