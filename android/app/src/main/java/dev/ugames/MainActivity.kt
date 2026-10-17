package dev.ugames

import android.app.AlertDialog
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.text.format.Formatter
import android.view.Gravity
import android.view.View
import android.view.WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.Future

class MainActivity : ComponentActivity() {
    private val windows = mutableListOf<WebView>()
    private val backgrounds = mutableMapOf<WebView, Int>()
    private val captures = mutableMapOf<WebView, OfflineCaptureReport>()
    private val offlineWindows = mutableMapOf<WebView, SavedOfflineGame>()
    private val downloads = Executors.newSingleThreadExecutor()
    private val offlineStore by lazy {
        OfflineGameStore(
            File(filesDir, "offline-games"),
            ProtectedWebViewFactory.resourceFilter(this)
        )
    }
    private var saveJob: Future<*>? = null
    private var saving = false
    private var menuSave: Button? = null
    private var menuStatus: TextView? = null
    private var progressDialog: AlertDialog? = null
    private var lastOfflineId: String? = null
    private lateinit var root: FrameLayout
    private lateinit var content: FrameLayout
    private lateinit var loading: ProgressBar
    private var fullscreen: View? = null
    private var fullscreenCallback: WebChromeClient.CustomViewCallback? = null
    private var lastUrl = HOME
    private val current get() = windows.lastOrNull()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        root = FrameLayout(this)
        root.setBackgroundColor(ProtectedWebViewFactory.defaultBackground)
        window.setBackgroundDrawable(ColorDrawable(ProtectedWebViewFactory.defaultBackground))
        root.setOnApplyWindowInsetsListener { view, insets ->
            val compatible = WindowInsetsCompat.toWindowInsetsCompat(insets, view)
            // Keep game controls clear of cutouts, the keyboard and reserved system gestures.
            val safe = compatible.getInsets(
                WindowInsetsCompat.Type.displayCutout() or WindowInsetsCompat.Type.ime() or
                    WindowInsetsCompat.Type.systemBars() or
                    WindowInsetsCompat.Type.mandatorySystemGestures()
            )
            view.setPadding(safe.left, safe.top, safe.right, safe.bottom)
            insets
        }
        loading =
            ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
                isIndeterminate = true
                indeterminateTintList = ColorStateList.valueOf(getColor(R.color.ugames_mint))
                visibility = View.GONE
            }
        content = FrameLayout(this)
        root.addView(content, FrameLayout.LayoutParams(-1, -1))
        root.addView(loading, FrameLayout.LayoutParams(-1, dp(2), Gravity.TOP))
        root.addView(
            ImageButton(this).apply {
                contentDescription = "Меню UGames"
                setImageResource(R.drawable.ic_more_vert)
                imageTintList = android.content.res.ColorStateList.valueOf(Color.WHITE)
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(Color.argb(225, 35, 32, 48))
                }
                setPadding(dp(12), dp(12), dp(12), dp(12))
                setOnClickListener { showGameMenu() }
            },
            FrameLayout.LayoutParams(dp(48), dp(48), Gravity.TOP or Gravity.END).apply {
                topMargin = dp(8)
                marginEnd = dp(8)
            }
        )
        setContentView(root)
        enterImmersiveMode()
        root.requestApplyInsets()
        lastUrl = savedInstanceState?.getString("lastUrl") ?: HOME
        lastOfflineId = savedInstanceState?.getString("offlineGameId")
        createAndLoad(lastUrl)
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
                layoutInDisplayCutoutMode =
                    LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && ::root.isInitialized) enterImmersiveMode()
    }

    private fun createAndLoad(url: String) {
        try {
            val saved = lastOfflineId?.let { id ->
                offlineStore.listGames().firstOrNull {
                    it.id ==
                        id
                }
            }
            if (lastOfflineId != null && saved == null) lastOfflineId = null
            showWindow(ProtectedWebViewFactory.create(this, offlineGame = saved))
            load(saved?.entryUrl ?: url)
        } catch (_: UnsupportedOperationException) {
            showError(
                "Обнови Android System WebView и перезапусти UGames, чтобы открыть игры без рекламы."
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
        offlineWindows.remove(view)
        content.removeView(view)
        view.stopLoading()
        view.destroy()
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
        current?.let {
            content.removeAllViews()
            content.addView(it, FrameLayout.LayoutParams(-1, -1))
            setPageBackground(it, backgrounds[it] ?: ProtectedWebViewFactory.defaultBackground)
            val saved = offlineWindows[it]
            if (saved !=
                null
            ) {
                ProtectedWebViewFactory.loadOfflineGame(it, saved)
            } else {
                it.loadUrl(url)
            }
        }
    }

    fun setLoading(view: WebView, value: Boolean) {
        if (view !== current) return
        loading.visibility = if (value) View.VISIBLE else View.GONE
        view.url?.takeIf { it.startsWith("https://") }?.let { lastUrl = it }
    }

    fun showError(message: String) {
        current?.let { captures.remove(it) }
        updateMenuStatus()
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
                    if (current == null) {
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
                text = "Сохранённые игры"
                minHeight = dp(48)
                setOnClickListener { showSavedGames() }
            }
        )
        panel.addView(
            Button(this).apply {
                text = "В каталог"
                minHeight = dp(48)
                backgroundTintList = ColorStateList.valueOf(getColor(R.color.ugames_surface))
                setTextColor(getColor(R.color.ugames_mint))
                setOnClickListener {
                    openCatalog()
                }
            }
        )
        content.removeAllViews()
        content.addView(panel, FrameLayout.LayoutParams(-1, -1))
    }

    fun rendererGone(view: WebView) {
        if (view === current) view.url?.takeIf { it.startsWith("https://") }?.let { lastUrl = it }
        // WebViews sharing the crashed renderer cannot be reused.
        content.removeAllViews()
        for (window in windows.toList()) {
            window.destroy()
        }
        windows.clear()
        backgrounds.clear()
        captures.clear()
        offlineWindows.clear()
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

            current in offlineWindows -> showSavedGames()

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
        current?.onPause()
        current?.pauseTimers()
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        current?.resumeTimers()
        current?.onResume()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putString("lastUrl", lastUrl)
        outState.putString("offlineGameId", lastOfflineId)
        super.onSaveInstanceState(outState)
    }

    override fun onDestroy() {
        saveJob?.cancel(true)
        downloads.shutdownNow()
        progressDialog?.dismiss()
        windows.forEach {
            it.stopLoading()
            it.destroy()
        }
        windows.clear()
        backgrounds.clear()
        captures.clear()
        offlineWindows.clear()
        super.onDestroy()
    }

    fun navigationStarted(view: WebView) {
        captures.remove(view)
        updateMenuStatus()
    }

    fun registerOfflineWindow(view: WebView, game: SavedOfflineGame) {
        offlineWindows[view] = game
    }

    fun receiveOfflineReport(view: WebView, data: String, origin: String) {
        if (view !in windows || view in offlineWindows) return
        val report = OfflineCaptureReport.parse(data, origin, view.title)
        if (report == null) captures.remove(view) else captures[view] = report
        updateMenuStatus()
    }

    private fun showGameMenu() {
        current?.evaluateJavascript(
            "if(window.__UGamesOfflineCapture)window.__UGamesOfflineCapture();",
            null
        )
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(8), dp(24), dp(8))
        }
        menuStatus = TextView(this).apply {
            setTextAppearance(android.R.style.TextAppearance_Material_Body1)
            panel.addView(this, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = dp(16) })
        }
        val dialog = AlertDialog.Builder(this).setTitle("UGames").setView(panel)
            .setNegativeButton("Закрыть", null).create()
        menuSave = Button(this).apply {
            text = "Сохранить для игры без сети"
            minHeight = dp(48)
            setOnClickListener {
                dialog.dismiss()
                saveCurrentGame()
            }
            panel.addView(this, LinearLayout.LayoutParams(-1, -2))
        }
        panel.addView(
            Button(this).apply {
                text = "Сохранённые игры"
                minHeight = dp(48)
                setOnClickListener {
                    dialog.dismiss()
                    showSavedGames()
                }
            },
            LinearLayout.LayoutParams(-1, -2)
        )
        panel.addView(
            Button(this).apply {
                text = "В каталог"
                minHeight = dp(48)
                setOnClickListener {
                    dialog.dismiss()
                    openCatalog()
                }
            },
            LinearLayout.LayoutParams(-1, -2)
        )
        dialog.setOnDismissListener {
            menuSave = null
            menuStatus = null
        }
        updateMenuStatus()
        dialog.show()
    }

    private fun updateMenuStatus() {
        val report = captures[current]
        menuSave?.isEnabled = !saving && report?.ready == true && current !in offlineWindows
        menuStatus?.text = when {
            saving -> "Сохраняем файлы игры…"

            current in offlineWindows ->
                "Игра открыта без сети. Прогресс сохраняется на этом устройстве."

            report?.ready == true ->
                "Открытая игра готова к сохранению. " +
                    "Уровни, которые игра ещё не загрузила, могут потребовать подключения."

            else -> "Запусти игру в каталоге и дождись её загрузки. Затем её можно сохранить здесь."
        }
    }

    private fun saveCurrentGame() {
        val report = captures[current]?.takeIf { it.ready } ?: return
        if (saving || current in offlineWindows) return
        saving = true
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(16), dp(24), dp(8))
        }
        val status = TextView(this).apply { text = "Подготовка файлов…" }
        val progress = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal)
        panel.addView(status, LinearLayout.LayoutParams(-1, -2))
        panel.addView(progress, LinearLayout.LayoutParams(-1, dp(16)).apply { topMargin = dp(12) })
        val dialog = AlertDialog.Builder(this).setTitle("Сохранение игры").setView(panel)
            .setNegativeButton("Отмена") { _, _ -> saveJob?.cancel(true) }.create()
        dialog.setOnCancelListener { saveJob?.cancel(true) }
        progressDialog = dialog
        dialog.show()
        saveJob = downloads.submit {
            try {
                val game = offlineStore.save(report) { completed, count, bytes ->
                    runOnUiThread {
                        if (!isDestroyed && dialog.isShowing) {
                            progress.max = count
                            progress.progress = completed
                            status.text =
                                "$completed из $count файлов · ${Formatter.formatShortFileSize(
                                    this,
                                    bytes
                                )}"
                        }
                    }
                }
                runOnUiThread {
                    if (!isDestroyed) {
                        Toast.makeText(
                            this,
                            "«${game.title}» доступна в сохранённых играх",
                            Toast.LENGTH_LONG
                        ).show()
                    }
                }
            } catch (error: Exception) {
                val cancelled = Thread.currentThread().isInterrupted
                runOnUiThread {
                    if (!isDestroyed) {
                        if (cancelled) {
                            Toast.makeText(this, "Сохранение отменено", Toast.LENGTH_SHORT).show()
                        } else {
                            AlertDialog.Builder(this).setTitle("Игра не сохранена")
                                .setMessage(
                                    "${error.message ?: "Не удалось скачать файлы"}. Проверь подключение и свободное место, затем попробуй ещё раз."
                                )
                                .setPositiveButton("Понятно", null).show()
                        }
                    }
                }
            } finally {
                runOnUiThread {
                    saving = false
                    if (!isDestroyed) dialog.dismiss()
                    if (progressDialog === dialog) progressDialog = null
                    updateMenuStatus()
                }
            }
        }
    }

    private fun showSavedGames() {
        val waiting = AlertDialog.Builder(
            this
        ).setMessage("Открываем сохранённые игры…").setCancelable(false).create()
        waiting.show()
        downloads.execute {
            val games = offlineStore.listGames()
            runOnUiThread {
                waiting.dismiss()
                if (isDestroyed) return@runOnUiThread
                val builder = AlertDialog.Builder(this).setTitle("Сохранённые игры")
                    .setNegativeButton("Закрыть", null)
                if (games.isEmpty()) {
                    builder.setMessage(
                        "Пока нет сохранённых игр. Запусти игру в каталоге и выбери «Сохранить для игры без сети» в меню UGames."
                    )
                        .setPositiveButton("В каталог") { _, _ -> openCatalog() }
                } else {
                    builder.setItems(
                        games.map {
                            "${it.title}\n${Formatter.formatShortFileSize(
                                this,
                                it.totalBytes
                            )} · без сети"
                        }.toTypedArray()
                    ) { _, index ->
                        showSavedGame(games[index])
                    }
                }
                builder.show()
            }
        }
    }

    private fun showSavedGame(game: SavedOfflineGame) {
        AlertDialog.Builder(this).setTitle(game.title)
            .setItems(arrayOf("Играть без сети", "Удалить с устройства")) { _, index ->
                if (index == 0) {
                    openOfflineGame(game)
                } else {
                    if (offlineWindows[current]?.id == game.id) openCatalog()
                    downloads.execute {
                        try {
                            offlineStore.delete(game.id)
                            runOnUiThread { if (!isDestroyed) showSavedGames() }
                        } catch (_: Exception) {
                            runOnUiThread {
                                if (!isDestroyed) {
                                    Toast.makeText(
                                        this,
                                        "Не удалось удалить игру",
                                        Toast.LENGTH_LONG
                                    ).show()
                                }
                            }
                        }
                    }
                }
            }.setNegativeButton("Назад") { _, _ -> showSavedGames() }.show()
    }

    private fun closeAllWindows() {
        hideFullscreen()
        while (windows.isNotEmpty()) current?.let(::closeWindow)
    }

    fun openOfflineGame(game: SavedOfflineGame) {
        closeAllWindows()
        lastOfflineId = game.id
        lastUrl = game.entryUrl
        try {
            showWindow(ProtectedWebViewFactory.create(this, offlineGame = game))
            load(game.entryUrl)
        } catch (_: Exception) {
            showError(
                "Не удалось открыть сохранённую игру. Обнови Android System WebView и попробуй снова."
            )
        }
    }

    private fun openCatalog() {
        closeAllWindows()
        lastOfflineId = null
        createAndLoad(HOME)
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
    companion object {
        const val HOME = "https://yandex.ru/games/"
    }
}
