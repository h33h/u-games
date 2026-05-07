package games.yandex.wrap.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable

/**
 * Wraps content in MaterialTheme(darkColorScheme()) plus a black Surface so
 * legacy MaterialTheme.* lookups still work, but new code reads UGColors /
 * UGType directly.
 */
@Composable
fun UGamesTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = darkColorScheme()) {
        Surface(color = UGColors.Bg0, content = content)
    }
}
