package games.yandex.wrap.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import games.yandex.wrap.ui.theme.UGColors
import games.yandex.wrap.ui.theme.UGType
import games.yandex.wrap.ui.theme.UGamesTheme

/**
 * Empty-state placard: 48dp icon, title, body, optional CTA.
 *
 * Used for "No favorites yet", "No games match search", "Coming soon" tabs.
 */
@Composable
fun EmptyState(
    icon: ImageVector,
    title: String,
    body: String? = null,
    ctaLabel: String? = null,
    onCta: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = UGColors.TextMuted,
            modifier = Modifier.size(48.dp),
        )
        Spacer(Modifier.height(14.dp))
        Text(text = title, color = UGColors.TextPrimary, style = UGType.TitleM)
        if (!body.isNullOrEmpty()) {
            Spacer(Modifier.height(6.dp))
            Text(
                text = body,
                color = UGColors.TextMuted,
                style = UGType.BodyS,
                textAlign = TextAlign.Center,
            )
        }
        if (ctaLabel != null && onCta != null) {
            Spacer(Modifier.height(16.dp))
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(14.dp))
                    .background(UGColors.AccentGradient)
                    .clickable(onClick = onCta)
                    .padding(horizontal = 18.dp, vertical = 10.dp),
            ) {
                Text(text = ctaLabel, color = Color.Black, style = UGType.BodyS)
            }
        }
    }
}

@Preview(showBackground = true, backgroundColor = 0xFF000000, widthDp = 360, heightDp = 320)
@Composable
private fun EmptyStatePreview() {
    UGamesTheme {
        EmptyState(
            icon = Icons.Filled.FavoriteBorder,
            title = "No favorites yet",
            body = "Tap ♥ on any game to save it.",
            ctaLabel = "Browse games",
            onCta = {},
        )
    }
}
