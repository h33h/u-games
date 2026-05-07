package games.yandex.wrap.ui.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import games.yandex.wrap.ui.theme.UGColors
import games.yandex.wrap.ui.theme.UGamesTheme

/**
 * Animated shimmer placeholder. Use for any "loading game tile / hero" hole
 * that used to show CircularProgressIndicator. Color sweeps Elevated → lighter
 * shade → Elevated to imply ongoing activity without spinner-fatigue.
 */
@Composable
fun Skeleton(
    modifier: Modifier = Modifier,
    cornerRadius: Dp = 12.dp,
) {
    val transition = rememberInfiniteTransition(label = "skeleton")
    val phase by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1400, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "phase",
    )
    val brush = Brush.linearGradient(
        colors = listOf(
            UGColors.Elevated,
            Color(0xFF22222A),
            UGColors.Elevated,
        ),
        start = Offset(phase * 600f - 300f, 0f),
        end = Offset(phase * 600f, 0f),
    )
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(cornerRadius))
            .background(brush),
    )
}

@Preview(showBackground = true, backgroundColor = 0xFF000000)
@Composable
private fun SkeletonPreview() {
    UGamesTheme {
        Skeleton(
            modifier = Modifier
                .padding(16.dp)
                .height(120.dp)
                .fillMaxWidth(),
        )
    }
}
