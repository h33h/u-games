package dev.ugames

import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import org.json.JSONObject

class MainActivity : ComponentActivity() {
    private data class CaptureVisit(val entry: String, val token: String)
    private val windows = mutableListOf<WebView>()
    private val backgrounds = mutableMapOf<WebView, Int>()
    private val captures = mutableMapOf<WebView, OfflineCaptureReport>()
    private val visits = mutableMapOf<WebView, CaptureVisit>()
    private val offlineWindows = mutableMapOf<WebView, OfflineReplayLease>()
    private val offlineCatalogs = mutableSetOf<WebView>()
    private val downloads = Executors.newSingleThreadExecutor()
    private val indexIO = Executors.newSingleThreadExecutor()
    private val offlineStore by lazy {
        OfflineGameStore(
            File(filesDir, "offline-games"),
            ProtectedWebViewFactory.resourceFilter(this)
        )
    }
    private val autoCache by lazy {
        AutomaticOfflineCache(offlineStore, downloads, onSaved = {
            if (!isDestroyed && !indexIO.isShutdown) refreshIndex()
        })
    }
    private lateinit var connectivity: ValidatedInternetMonitor

    @Volatile var isInternetAvailable = true
        private set
    private var foreground = false
    private var cachedGames = emptyList<SavedOfflineGame>()
    private lateinit var root: FrameLayout
    private lateinit var content: FrameLayout
    private lateinit var loading: ProgressBar
    private var fullscreen: View? = null
    private var fullscreenCallback: WebChromeClient.CustomViewCallback? = null
    private var lastUrl = HOME
    private var selectionGeneration = 0L
    private val current get() = windows.lastOrNull()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        root = FrameLayout(this)
        root.setBackgroundColor(ProtectedWebViewFactory.defaultBackground)
        window.setBackgroundDrawable(ColorDrawable(ProtectedWebViewFactory.defaultBackground))
        root.setOnApplyWindowInsetsListener { view, insets ->
            val compatible = WindowInsetsCompat.toWindowInsetsCompat(insets, view)
            val safe = compatible.getInsets(
                WindowInsetsCompat.Type.displayCutout() or WindowInsetsCompat.Type.ime() or
                    WindowInsetsCompat.Type.systemBars() or
                    WindowInsetsCompat.Type.mandatorySystemGestures()
            )
            view.setPadding(safe.left, safe.top, safe.right, safe.bottom)
            insets
        }
        loading = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            isIndeterminate = true
            indeterminateTintList = ColorStateList.valueOf(getColor(R.color.ugames_mint))
            visibility = View.GONE
        }
        content = FrameLayout(this)
        root.addView(content, FrameLayout.LayoutParams(-1, -1))
        root.addView(loading, FrameLayout.LayoutParams(-1, dp(2), Gravity.TOP))
        setContentView(root)
        enterImmersiveMode()
        root.requestApplyInsets()
        connectivity = ValidatedInternetMonitor(this, ::connectivityChanged)
        isInternetAvailable = connectivity.available
        connectivity.start()
        lastUrl =
            OfflineRoutingPolicy.startupUrl(
                isInternetAvailable,
                savedInstanceState?.getString("lastUrl") ?: HOME
            )
        if (isInternetAvailable) createAndLoad(lastUrl)
        refreshIndex {
            // An offline launch always starts at the ordinary catalogue, even after process death.
            if (current ==
                null
            ) {
                createAndLoad(OfflineRoutingPolicy.startupUrl(isInternetAvailable, lastUrl))
            }
        }
        onBackPressedDispatcher.addCallback(
            this,
            object : OnBackPressedCallback(true) {
                override fun handleOnBackPressed() {
                    goBack()
                }
            }
        )
    }

    private fun enterImmersiveMode() {
        WindowCompat.getInsetsController(window, root).apply {
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            hide(WindowInsetsCompat.Type.systemBars())
        }
        if (Build.VERSION.SDK_INT >= 28) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode = LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && ::root.isInitialized) enterImmersiveMode()
    }

    private fun createAndLoad(url: String) {
        if (!isInternetAvailable) {
            openOfflineCatalog()
            return
        }
        try {
            showWindow(
                ProtectedWebViewFactory.create(
                    this,
                    onlineGameEntry = url.takeIf(OfflineResourcePolicy::isGameUrl)
                )
            )
            load(url)
        } catch (_: UnsupportedOperationException) {
            showError(
                "Обнови Android System WebView и перезапусти UGames, " +
                    "чтобы открыть игры без рекламы."
            )
        } catch (_: Exception) {
            showError("Не удалось подготовить приложение. Попробуй перезапустить UGames.")
        }
    }

    fun showWindow(view: WebView) {
        current?.onPause()
        windows.add(view)
        content.removeAllViews()
        content.addView(view, FrameLayout.LayoutParams(-1, -1))
        setPageBackground(view, backgrounds[view] ?: ProtectedWebViewFactory.defaultBackground)
        view.onResume()
    }

    fun setPageBackground(view: WebView, color: Int) {
        if (view !in windows) return
        backgrounds[view] = color
        view.setBackgroundColor(color)
        if (view === current && view.parent === content) {
            root.setBackgroundColor(color)
            window.setBackgroundDrawable(ColorDrawable(color))
        }
    }

    fun closeWindow(view: WebView) {
        if (!windows.remove(view)) return
        backgrounds.remove(view)
        captures.remove(view)
        visits.remove(view)
        val replayLease = offlineWindows.remove(view)
        offlineCatalogs.remove(view)
        content.removeView(view)
        view.stopLoading()
        view.destroy()
        replayLease?.close()
        current?.let {
            content.removeAllViews()
            content.addView(it, FrameLayout.LayoutParams(-1, -1))
            setPageBackground(it, backgrounds[it] ?: ProtectedWebViewFactory.defaultBackground)
            it.onResume()
        }
    }

    private fun load(url: String) {
        lastUrl = url
        hideFullscreen()
        if (!isInternetAvailable) {
            val saved = OfflineRoutingPolicy.cachedGame(url, false, cachedGames)
            if (saved == null) openOfflineCatalog() else openOfflineGame(saved)
            return
        }
        if (current in offlineWindows || current in offlineCatalogs) {
            openOnline(url)
            return
        }
        current?.let {
            loadCurrentSurface()
            it.loadUrl(url)
        }
    }

    fun setLoading(view: WebView, value: Boolean) {
        if (view !== current) return
        loading.visibility = if (value) View.VISIBLE else View.GONE
        if (view !in offlineWindows &&
            view !in offlineCatalogs
        ) {
            view.url?.takeIf { it.startsWith("https://") }?.let {
                lastUrl =
                    it
            }
        }
    }

    fun showError(message: String) {
        current?.let { captures.remove(it) }
        hideFullscreen()
        loading.visibility = View.GONE
        val background = getColor(R.color.ugames_background)
        root.setBackgroundColor(background)
        window.setBackgroundDrawable(ColorDrawable(background))
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(24), dp(24), dp(24), dp(24))
        }
        panel.addView(
            TextView(this).apply {
                text = message
                gravity = Gravity.CENTER
                setTextAppearance(android.R.style.TextAppearance_Material_Body1)
                setTextColor(getColor(R.color.ugames_text))
            }
        )
        panel.addView(
            Button(this).apply {
                text = "Попробовать снова"
                minHeight = dp(48)
                backgroundTintList = ColorStateList.valueOf(getColor(R.color.ugames_accent))
                setTextColor(getColor(R.color.ugames_on_accent))
                setOnClickListener {
                    if (current ==
                        null
                    ) {
                        createAndLoad(lastUrl)
                    } else {
                        load(lastUrl)
                    }
                }
            },
            LinearLayout.LayoutParams(-2, -2).apply { topMargin = dp(16) }
        )
        panel.addView(
            Button(this).apply {
                text = "В каталог"
                minHeight = dp(48)
                backgroundTintList = ColorStateList.valueOf(getColor(R.color.ugames_surface))
                setTextColor(getColor(R.color.ugames_mint))
                setOnClickListener { openCatalog() }
            }
        )
        content.removeAllViews()
        content.addView(panel, FrameLayout.LayoutParams(-1, -1))
    }

    fun pageLoadFailed(view: WebView, message: String) {
        if (view !== current) return
        if (!isInternetAvailable && view !in offlineWindows &&
            view !in offlineCatalogs
        ) {
            openOfflineCatalog()
        } else {
            showError(message)
        }
    }

    fun pageHttpFailed(view: WebView, message: String) {
        if (view === current) showError(message)
    }

    fun rendererGone(view: WebView) {
        selectionGeneration++
        if (view === current && view !in offlineWindows &&
            view !in offlineCatalogs
        ) {
            view.url?.takeIf { it.startsWith("https://") }?.let {
                lastUrl =
                    it
            }
        }
        content.removeAllViews()
        windows.forEach { it.destroy() }
        windows.clear()
        backgrounds.clear()
        captures.clear()
        visits.clear()
        offlineWindows.values.forEach(OfflineReplayLease::close)
        offlineWindows.clear()
        offlineCatalogs.clear()
        showError("Игра закрылась. Можно открыть её снова.")
    }

    fun showFullscreen(view: View, callback: WebChromeClient.CustomViewCallback) {
        if (fullscreen != null) {
            callback.onCustomViewHidden()
            return
        }
        fullscreen = view
        fullscreenCallback = callback
        content.addView(view, FrameLayout.LayoutParams(-1, -1))
    }

    fun hideFullscreen() {
        fullscreen?.let { content.removeView(it) }
        fullscreen = null
        fullscreenCallback?.onCustomViewHidden()
        fullscreenCallback = null
    }

    private fun goBack() {
        when {
            fullscreen != null -> hideFullscreen()

            windows.size > 1 -> current?.let(::closeWindow)

            current in offlineWindows -> openCatalog()

            current in offlineCatalogs -> finish()

            current?.canGoBack() == true -> {
                loadCurrentSurface()
                current?.goBack()
            }

            current?.url != HOME && current != null -> load(HOME)

            else -> finish()
        }
    }

    private fun loadCurrentSurface() {
        current?.let {
            content.removeAllViews()
            content.addView(it, FrameLayout.LayoutParams(-1, -1))
            setPageBackground(it, backgrounds[it] ?: ProtectedWebViewFactory.defaultBackground)
        }
    }

    override fun onPause() {
        selectionGeneration++
        foreground = false
        autoCache.setEnabled(false)
        current?.onPause()
        current?.pauseTimers()
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        foreground = true
        autoCache.setEnabled(isInternetAvailable)
        current?.resumeTimers()
        current?.onResume()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putString("lastUrl", lastUrl)
        super.onSaveInstanceState(outState)
    }

    override fun onDestroy() {
        selectionGeneration++
        connectivity.stop()
        autoCache.setEnabled(false)
        downloads.shutdownNow()
        indexIO.shutdownNow()
        windows.forEach {
            it.stopLoading()
            it.destroy()
        }
        windows.clear()
        backgrounds.clear()
        captures.clear()
        visits.clear()
        offlineWindows.values.forEach(OfflineReplayLease::close)
        offlineWindows.clear()
        offlineCatalogs.clear()
        super.onDestroy()
    }

    fun navigationStarted(view: WebView) {
        captures.remove(view)
        visits.remove(view)
    }

    fun registerOfflineWindow(view: WebView, lease: OfflineReplayLease) {
        offlineWindows.put(view, lease)?.close()
    }

    fun registerOfflineCatalog(view: WebView) {
        offlineCatalogs.add(view)
    }

    fun receiveOfflineReport(
        view: WebView,
        data: String,
        origin: String,
        mainFrame: Boolean = false
    ) {
        if (view !in windows || view in offlineWindows || view in offlineCatalogs) return
        val metadata = OfflineCatalogMetadata.parse(data, origin, view.url, mainFrame)
        if (metadata != null) {
            if (foreground &&
                isInternetAvailable
            ) {
                indexIO.execute {
                    runCatching {
                        if (offlineStore.rememberCatalog(
                                metadata
                            )
                        ) {
                            autoCache.catalogChanged(metadata.gameId)
                        }
                    }
                }
            }
            return
        }
        if (data.length <= 16384) {
            runCatching {
                val packet = JSONObject(data)
                val entry = OfflineResourcePolicy.normalize(packet.optString("url"))
                if (packet.optInt("version") == 1 && packet.optString("type") == "visit" &&
                    entry != null &&
                    OfflineResourcePolicy.isGameUrl(entry) &&
                    OfflineResourcePolicy.origin(entry) == OfflineResourcePolicy.origin(origin)
                ) {
                    visits[view] =
                        CaptureVisit(entry.substringBefore('?'), UUID.randomUUID().toString())
                    captures.remove(view)
                    return
                }
            }
        }
        val report = OfflineCaptureReport.parse(data, origin, view.title) ?: return
        captures[view] = report
        val key = requireNotNull(
            OfflineResourcePolicy.normalize(report.entryUrl)
        ).substringBefore('?')
        val visit =
            visits[view]?.takeIf { it.entry == key }
                ?: CaptureVisit(key, UUID.randomUUID().toString()).also { visits[view] = it }
        if (foreground && isInternetAvailable &&
            view === current && report.ready
        ) {
            val playedAt = System.currentTimeMillis()
            autoCache.offer(report, visit.token, playedAt)
            indexIO.execute { runCatching { offlineStore.touch(report.entryUrl, playedAt) } }
        }
    }

    /** Invoked only from the validated network monitor (and deterministic device tests). */
    fun connectivityChanged(available: Boolean) {
        if (isDestroyed || available == isInternetAvailable) return
        isInternetAvailable = available
        selectionGeneration++
        autoCache.setEnabled(foreground && available)
        if (available) {
            val target =
                offlineWindows[current]?.game?.entryUrl
                    ?: if (current in offlineCatalogs) HOME else null
            if (target != null) openOnline(target)
        } else {
            val entry = captures[current]?.entryUrl
            val game = entry?.let { OfflineRoutingPolicy.cachedGame(it, false, cachedGames) }
            openOfflineCatalog()
            if (game != null) openOfflineGame(game)
            val previous = current
            val generation = selectionGeneration
            refreshIndex {
                if (!isInternetAvailable && selectionGeneration == generation &&
                    current === previous && current in offlineCatalogs
                ) {
                    openOfflineCatalog()
                }
            }
        }
    }

    fun openCachedUrl(view: WebView, url: String): Boolean {
        if (view !in offlineCatalogs || isInternetAvailable) return false
        OfflineRoutingPolicy.cachedGame(url, false, cachedGames)?.let(::openOfflineGame)
        return true
    }

    private fun refreshIndex(completed: () -> Unit = {}) {
        indexIO.execute {
            val games = runCatching { offlineStore.listGames() }.getOrDefault(emptyList())
            runOnUiThread {
                if (!isDestroyed) {
                    cachedGames = games
                    completed()
                }
            }
        }
    }

    private fun closeAllWindows() {
        hideFullscreen()
        while (windows.isNotEmpty()) current?.let(::closeWindow)
        CookieManager.getInstance().flush()
    }

    fun openOfflineGame(game: SavedOfflineGame) {
        if (isInternetAvailable) {
            openOnline(game.entryUrl)
            return
        }
        val generation = ++selectionGeneration
        val playedAt = System.currentTimeMillis()
        indexIO.execute {
            val lease = runCatching { offlineStore.acquire(game.id, playedAt) }.getOrNull()
            runOnUiThread {
                if (isDestroyed || isInternetAvailable || selectionGeneration != generation) {
                    lease?.close()
                    return@runOnUiThread
                }
                if (lease == null) {
                    cachedGames = cachedGames.filterNot { it.id == game.id }
                    openOfflineCatalog()
                    return@runOnUiThread
                }
                closeAllWindows()
                lastUrl = lease.game.entryUrl
                try {
                    val view = ProtectedWebViewFactory.create(this, offlineLease = lease)
                    showWindow(view)
                    ProtectedWebViewFactory.loadOfflineGame(view, lease.game)
                } catch (_: Exception) {
                    lease.close()
                    showError("Не удалось открыть игру. Попробуй открыть её ещё раз из каталога.")
                }
            }
        }
    }

    private fun openOfflineCatalog() {
        selectionGeneration++
        if (isInternetAvailable) {
            openOnline(HOME)
            return
        }
        closeAllWindows()
        lastUrl = HOME
        try {
            val view = ProtectedWebViewFactory.create(this, cachedCatalog = cachedGames)
            showWindow(view)
            ProtectedWebViewFactory.loadOfflineCatalog(view)
        } catch (_: Exception) {
            showError("Не удалось открыть каталог. Попробуй ещё раз.")
        }
    }

    private fun openOnline(url: String) {
        selectionGeneration++
        closeAllWindows()
        createAndLoad(url)
    }

    private fun openCatalog() {
        if (isInternetAvailable) openOnline(HOME) else openOfflineCatalog()
    }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
    companion object {
        const val HOME = OfflineRoutingPolicy.HOME
    }
}
