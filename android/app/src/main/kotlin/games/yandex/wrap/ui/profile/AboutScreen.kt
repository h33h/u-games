package games.yandex.wrap.ui.profile

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import games.yandex.wrap.BuildConfig
import games.yandex.wrap.ui.theme.UGColors
import games.yandex.wrap.ui.theme.UGType

/**
 * Minimal About screen. App icon, version (`BuildConfig.VERSION_NAME`)
 * and a tappable GitHub link. Push-style: handles back via the system
 * back button.
 */
@Composable
fun AboutScreen(onBack: () -> Unit) {
    BackHandler(onBack = onBack)
    val context = LocalContext.current
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(UGColors.Bg0)
            .windowInsetsPadding(WindowInsets.statusBars),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onBack) {
                Icon(
                    Icons.AutoMirrored.Filled.ArrowBack,
                    contentDescription = "Back",
                    tint = UGColors.TextPrimary,
                )
            }
            Text(text = "About", color = UGColors.TextPrimary, style = UGType.TitleM)
        }
        Column(
            modifier = Modifier.fillMaxSize().padding(horizontal = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Box(
                modifier = Modifier
                    .size(96.dp)
                    .clip(RoundedCornerShape(22.dp))
                    .background(UGColors.Elevated),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Filled.SportsEsports,
                    contentDescription = null,
                    tint = UGColors.Accent,
                    modifier = Modifier.size(48.dp),
                )
            }
            Spacer(Modifier.height(16.dp))
            Text(text = "U-Games", color = UGColors.TextPrimary, style = UGType.TitleL)
            Spacer(Modifier.height(4.dp))
            Text(
                text = "v${BuildConfig.VERSION_NAME}",
                color = UGColors.TextMuted,
                style = UGType.BodyS,
            )
            Spacer(Modifier.height(24.dp))
            Text(
                text = "An unofficial Yandex Games wrapper. Open source under MIT.",
                color = UGColors.TextSecondary,
                style = UGType.BodyS,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(20.dp))
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(14.dp))
                    .background(UGColors.Elevated)
                    .clickable {
                        val intent = Intent(
                            Intent.ACTION_VIEW,
                            Uri.parse("https://github.com/"),
                        )
                        context.startActivity(intent)
                    }
                    .padding(horizontal = 18.dp, vertical = 10.dp),
            ) {
                Text(
                    text = "View on GitHub →",
                    color = UGColors.Accent,
                    style = UGType.BodyS,
                )
            }
        }
    }
}
