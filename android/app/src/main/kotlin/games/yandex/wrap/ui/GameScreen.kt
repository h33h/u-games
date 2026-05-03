package games.yandex.wrap.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import games.yandex.wrap.webview.BlockList
import games.yandex.wrap.webview.GameWebView
import games.yandex.wrap.webview.InjectedScripts

@Composable
fun GameScreen(
    appId: Long,
    title: String,
    scripts: InjectedScripts,
    blockList: BlockList,
    onBack: () -> Unit,
) {
    BackHandler(onBack = onBack)
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black),
    ) {
        GameWebView(
            url = "https://yandex.com/games/app/$appId",
            scripts = scripts,
            blockList = blockList,
            modifier = Modifier.fillMaxSize(),
        )
    }
}
