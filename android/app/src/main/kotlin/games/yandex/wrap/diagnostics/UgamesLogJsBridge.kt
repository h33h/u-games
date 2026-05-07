package games.yandex.wrap.diagnostics

import android.webkit.JavascriptInterface
import org.json.JSONObject

/**
 * Bridges `window.__yga_log(tag, msg)` calls in inject scripts to the native
 * [LogStore] and [OrientationStore]. Mirrors the iOS `WKScriptMessageHandler`
 * named "ugamesLog".
 *
 * The JS shim posts a JSON string to `ugamesLog.postMessage(...)`. Wire it on
 * the WebView with:
 *
 *     webView.addJavascriptInterface(UgamesLogJsBridge(), "ugamesLog")
 *
 * and inject the matching shim at document start (see GameWebView).
 */
class UgamesLogJsBridge {

    @JavascriptInterface
    fun postMessage(payload: String?) {
        if (payload.isNullOrEmpty()) return
        val parsed = parsePayload(payload)
        LogStore.log(parsed.tag, parsed.message)
        // Side-channel: when the SDK stub traps screen.orientation.lock() it
        // forwards the requested target with tag="orient". Keep OrientationStore
        // in sync so GameScreen's rotate overlay can react.
        if (parsed.tag == "orient") {
            OrientationStore.setFromString(parsed.rawMessage)
        }
    }

    private data class ParsedMessage(
        val tag: String,
        val rawMessage: String,
        val message: String,
    )

    private fun parsePayload(payload: String): ParsedMessage = try {
        val obj = JSONObject(payload)
        val tag = obj.optString("tag").ifEmpty { "js" }
        val rawMsg = obj.optString("msg")
        val host = obj.optString("host")
        val msg = if (host.isEmpty()) rawMsg else "[$host] $rawMsg"
        ParsedMessage(tag = tag, rawMessage = rawMsg, message = msg)
    } catch (_: Throwable) {
        ParsedMessage(tag = "js", rawMessage = payload, message = payload)
    }
}
