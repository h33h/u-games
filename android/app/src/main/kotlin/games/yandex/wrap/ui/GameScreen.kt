package games.yandex.wrap.ui

import android.content.res.Configuration
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.Column
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.ScreenRotation
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import games.yandex.wrap.diagnostics.OrientationStore
import games.yandex.wrap.webview.BlockList
import games.yandex.wrap.webview.GameWebView
import games.yandex.wrap.webview.InjectedScripts
import kotlinx.coroutines.delay

@Composable
fun GameScreen(
    appId: Long,
    title: String,
    scripts: InjectedScripts,
    blockList: BlockList,
    onBack: () -> Unit,
) {
    BackHandler(onBack = onBack)
    var showBack by remember { mutableStateOf(true) }
    var revision by remember { mutableStateOf(0) }
    val required by OrientationStore.required.collectAsState()
    val configuration = LocalConfiguration.current
    val deviceIsLandscape = configuration.orientation == Configuration.ORIENTATION_LANDSCAPE

    DisposableEffect(appId) {
        OrientationStore.reset()
        onDispose { OrientationStore.reset() }
    }

    LaunchedEffect(revision) {
        showBack = true
        delay(2500)
        showBack = false
    }

    val rotateOverlayVisible = when (required) {
        OrientationStore.Required.Landscape -> !deviceIsLandscape
        OrientationStore.Required.Portrait -> deviceIsLandscape
        null -> false
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .windowInsetsPadding(WindowInsets.statusBars),
    ) {
        GameWebView(
            url = "https://yandex.com/games/app/$appId",
            scripts = scripts,
            blockList = blockList,
            modifier = Modifier.fillMaxSize(),
        )

        // Tap-to-reveal hot zone in the top-left corner — small enough to not
        // steal touches from the game itself.
        Box(
            modifier = Modifier
                .align(Alignment.TopStart)
                .size(64.dp)
                .pointerInput(Unit) {
                    detectTapGestures(onTap = { revision++ })
                }
        )

        AnimatedVisibility(
            visible = showBack,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.align(Alignment.TopStart),
        ) {
            IconButton(
                onClick = onBack,
                modifier = Modifier
                    .padding(8.dp)
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(Color(0xCC000000)),
            ) {
                Icon(
                    imageVector = Icons.Default.ArrowBack,
                    contentDescription = "Back",
                    tint = Color.White,
                )
            }
        }

        AnimatedVisibility(
            visible = rotateOverlayVisible,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.fillMaxSize(),
        ) {
            RotateDeviceOverlay(
                target = required ?: OrientationStore.Required.Landscape,
                onBack = onBack,
            )
        }
    }
}

/**
 * Full-screen overlay shown when the running game requested an orientation
 * that the device is not currently in. Triggered by `screen.orientation.lock()`
 * calls trapped by the SDK stub and forwarded via the `ugamesLog` JS bridge
 * (tag="orient"). Mirrors iOS GameView's RotateDeviceOverlay.
 */
@Composable
private fun RotateDeviceOverlay(
    target: OrientationStore.Required,
    onBack: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xF5000000)),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(
                imageVector = Icons.Default.ScreenRotation,
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier
                    .size(96.dp)
                    .rotate(if (target == OrientationStore.Required.Portrait) 90f else 0f),
            )
            Spacer(Modifier.height(28.dp))
            Text(
                text = if (target == OrientationStore.Required.Landscape)
                    "Поверните устройство"
                else
                    "Поверните в портрет",
                color = Color.White,
                fontSize = 22.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(Modifier.height(12.dp))
            Text(
                text = if (target == OrientationStore.Required.Landscape)
                    "Эта игра работает в горизонтальной ориентации."
                else
                    "Эта игра работает в вертикальной ориентации.",
                color = Color(0xFFAAAAAA),
                fontSize = 14.sp,
                modifier = Modifier.padding(horizontal = 32.dp),
            )
            Spacer(Modifier.height(28.dp))
            OutlinedButton(
                onClick = onBack,
                shape = RoundedCornerShape(22.dp),
            ) {
                Text("Назад в каталог", color = Color.White)
            }
        }
    }
}
