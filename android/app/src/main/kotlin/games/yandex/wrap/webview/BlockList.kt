package games.yandex.wrap.webview

import android.content.Context

class BlockList(private val patterns: List<String>) {

    fun isBlocked(url: String): Boolean {
        for (p in patterns) {
            if (url.contains(p)) return true
        }
        return false
    }

    companion object {
        fun load(context: Context): BlockList {
            val raw = context.assets.open("ad-domains.txt")
                .bufferedReader(Charsets.UTF_8)
                .use { it.readText() }
            val patterns = raw.lineSequence()
                .map { it.trim() }
                .filter { it.isNotEmpty() && !it.startsWith("#") }
                .toList()
            return BlockList(patterns)
        }
    }
}
