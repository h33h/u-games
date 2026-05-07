package games.yandex.wrap.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Home
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import games.yandex.wrap.ui.theme.UGColors
import games.yandex.wrap.ui.theme.UGType
import games.yandex.wrap.ui.theme.UGamesTheme

data class UGTab(
    val key: String,
    val label: String,
    val icon: ImageVector,
)

/**
 * Floating glass tab bar — pill-shaped, 24dp horizontal margin, ~62dp tall.
 * Phase 1 uses semi-transparent surface (UGColors.GlassFallback). Real
 * RenderEffect blur lands in Phase 5 polish.
 */
@Composable
fun FloatingTabBar(
    tabs: List<UGTab>,
    selectedKey: String,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 14.dp)
            .shadow(20.dp, RoundedCornerShape(28.dp), clip = false)
            .clip(RoundedCornerShape(28.dp))
            .background(UGColors.GlassFallback)
            .border(1.dp, UGColors.Divider, RoundedCornerShape(28.dp))
            .height(62.dp),
        horizontalArrangement = Arrangement.SpaceEvenly,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        tabs.forEach { tab ->
            val active = tab.key == selectedKey
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier
                    .clickable { onSelect(tab.key) }
                    .padding(horizontal = 12.dp, vertical = 6.dp),
            ) {
                Icon(
                    imageVector = tab.icon,
                    contentDescription = tab.label,
                    tint = if (active) UGColors.Accent else UGColors.TextMuted,
                    modifier = Modifier
                        .padding(bottom = 2.dp)
                        .size(22.dp),
                )
                Text(
                    text = tab.label,
                    color = if (active) UGColors.Accent else UGColors.TextMuted,
                    style = UGType.Caption,
                )
            }
        }
    }
}

@Preview(showBackground = true, backgroundColor = 0xFF000000, widthDp = 400, heightDp = 110)
@Composable
private fun FloatingTabBarPreview() {
    UGamesTheme {
        FloatingTabBar(
            tabs = listOf(
                UGTab("home", "Home", Icons.Filled.Home),
                UGTab("browse", "Browse", Icons.Filled.GridView),
                UGTab("favorites", "Favorites", Icons.Filled.Favorite),
                UGTab("profile", "Profile", Icons.Filled.AccountCircle),
            ),
            selectedKey = "home",
            onSelect = {},
        )
    }
}
