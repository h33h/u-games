package games.yandex.wrap.webview

import android.content.Context

class InjectedScripts(
    val honestPath: String,
    val pwaModeJs: String,
    val pwaModeCss: String,
    val sdkStub: String,
) {
    val mainFrameScript: String by lazy {
        buildString {
            append(honestPath)
            append(";\n")
            append("(function(){var s=document.createElement('style');s.textContent=")
            append(jsString(pwaModeCss))
            append(";document.documentElement.appendChild(s);})();\n")
            append(pwaModeJs)
        }
    }

    companion object {
        fun load(context: Context): InjectedScripts = InjectedScripts(
            honestPath = readAsset(context, "honest-path.js"),
            pwaModeJs = readAsset(context, "pwa-mode.js"),
            pwaModeCss = readAsset(context, "pwa-mode.css"),
            sdkStub = readAsset(context, "ya-sdk-stub.js"),
        )

        private fun readAsset(context: Context, name: String): String =
            context.assets.open(name).bufferedReader(Charsets.UTF_8).use { it.readText() }

        private fun jsString(value: String): String {
            val sb = StringBuilder("\"")
            for (c in value) {
                when (c.code) {
                    0x5C -> sb.append("\\\\")
                    0x22 -> sb.append("\\\"")
                    0x0A -> sb.append("\\n")
                    0x0D -> sb.append("\\r")
                    0x09 -> sb.append("\\t")
                    0x2028 -> sb.append("\\u2028")
                    0x2029 -> sb.append("\\u2029")
                    else -> sb.append(c)
                }
            }
            sb.append("\"")
            return sb.toString()
        }
    }
}
