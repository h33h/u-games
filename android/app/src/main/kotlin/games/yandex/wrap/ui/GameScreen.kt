package games.yandex.wrap.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
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

    LaunchedEffect(revision) {
        showBack = true
        delay(2500)
        showBack = false
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
    }
}
