package dev.ugames

import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
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

class MainActivity : ComponentActivity() {
    private val windows = mutableListOf<WebView>()
    private lateinit var root: FrameLayout
    private lateinit var content: FrameLayout
    private lateinit var loading: ProgressBar
    private var fullscreen: View? = null
    private var fullscreenCallback: WebChromeClient.CustomViewCallback? = null
    private var lastUrl = HOME
    private val current get() = windows.lastOrNull()

    override fun onCreate(savedInstanceState: Bundle?) {
        val dark =
            resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK ==
                Configuration.UI_MODE_NIGHT_YES
        setTheme(
            if (dark) {
                android.R.style.Theme_DeviceDefault_NoActionBar
            } else {
                android.R.style.Theme_DeviceDefault_Light_NoActionBar
            }
        )
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        root = FrameLayout(this)
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
                visibility = View.GONE
            }
        content = FrameLayout(this)
        root.addView(content, FrameLayout.LayoutParams(-1, -1))
        root.addView(loading, FrameLayout.LayoutParams(-1, dp(2), Gravity.TOP))
        setContentView(root)
        enterImmersiveMode()
        root.requestApplyInsets()
        lastUrl = savedInstanceState?.getString("lastUrl") ?: HOME
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
            showWindow(ProtectedWebViewFactory.create(this))
            load(url)
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
        view.onResume()
    }

    fun closeWindow(view: WebView) {
        if (!windows.remove(view)) return
        content.removeView(view)
        view.stopLoading()
        view.destroy()
        current?.let {
            content.removeAllViews()
            content.addView(it, FrameLayout.LayoutParams(-1, -1))
            it.onResume()
        }
    }

    private fun load(url: String) {
        lastUrl = url
        hideFullscreen()
        current?.let {
            content.removeAllViews()
            content.addView(it, FrameLayout.LayoutParams(-1, -1))
            it.loadUrl(url)
        }
    }

    fun setLoading(view: WebView, value: Boolean) {
        if (view !== current) return
        loading.visibility = if (value) View.VISIBLE else View.GONE
        view.url?.takeIf { it.startsWith("https://") }?.let { lastUrl = it }
    }

    fun showError(message: String) {
        hideFullscreen()
        loading.visibility = View.GONE
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
            }
        )
        panel.addView(
            Button(this).apply {
                text = "Попробовать снова"
                minHeight = dp(48)
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
                text = "В каталог"
                minHeight = dp(48)
                setOnClickListener {
                    while (windows.size > 1) current?.let(::closeWindow)
                    if (current == null) createAndLoad(HOME) else load(HOME)
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
        super.onSaveInstanceState(outState)
    }

    override fun onDestroy() {
        windows.forEach {
            it.stopLoading()
            it.destroy()
        }
        windows.clear()
        super.onDestroy()
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
    companion object {
        const val HOME = "https://yandex.ru/games/"
    }
}
