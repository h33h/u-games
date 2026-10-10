package dev.ugames

import java.net.URI

class AdResourceFilter(private val blockedHosts: List<String>, patterns: List<String>) {
    private val blockedPatterns = patterns.map { Regex(it, RegexOption.IGNORE_CASE) }
    fun shouldBlock(url: String): Boolean {
        val uri = try {
            URI(url)
        } catch (_: Exception) {
            return false
        }
        if (uri.scheme != "https" && uri.scheme != "http") return false
        val host = uri.host?.lowercase() ?: return false
        return blockedHosts.any { host == it || host.endsWith(".$it") } ||
            blockedPatterns.any { it.containsMatchIn(url) }
    }
}
