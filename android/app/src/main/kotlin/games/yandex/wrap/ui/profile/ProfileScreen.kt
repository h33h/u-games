package games.yandex.wrap.ui.profile

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ExitToApp
import androidx.compose.material.icons.automirrored.filled.Login
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Info
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import games.yandex.wrap.catalog.models.UserProfile
import games.yandex.wrap.ui.theme.UGColors
import games.yandex.wrap.ui.theme.UGType

/**
 * Profile tab. Replaces the old `ProfileSheet` modal — full-screen layout
 * with a hero-section (avatar, name, optional Plus pill) and a list of
 * "Settings" rows. Long-press on the avatar still opens diagnostic logs
 * (kept as a debug shortcut).
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ProfileScreen(
    viewModel: ProfileViewModel,
    onBack: () -> Unit,
    onLoginClick: () -> Unit,
    onLogsClick: () -> Unit,
    onAboutClick: () -> Unit,
) {
    BackHandler(onBack = onBack)
    val profile by viewModel.profile.collectAsState()
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
            Text(text = "Profile", color = UGColors.TextPrimary, style = UGType.TitleM)
        }
        Column(modifier = Modifier.padding(horizontal = 18.dp)) {
        Spacer(Modifier.height(8.dp))
        ProfileHero(profile = profile, onAvatarLongPress = onLogsClick)
        Spacer(Modifier.height(28.dp))
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(16.dp))
                .background(UGColors.Elevated),
        ) {
            if (profile?.isAuthorized == true) {
                SettingsRow(
                    icon = Icons.AutoMirrored.Filled.ExitToApp,
                    label = "Sign out",
                    danger = true,
                    onClick = { viewModel.signOut() },
                )
            } else {
                SettingsRow(
                    icon = Icons.AutoMirrored.Filled.Login,
                    label = "Sign in",
                    onClick = onLoginClick,
                )
            }
            Divider()
            SettingsRow(
                icon = Icons.Filled.Description,
                label = "Diagnostic logs",
                onClick = onLogsClick,
            )
            Divider()
            SettingsRow(
                icon = Icons.Filled.Info,
                label = "About",
                onClick = onAboutClick,
            )
        }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ProfileHero(profile: UserProfile?, onAvatarLongPress: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        val p = profile
        if (p?.isAuthorized == true && p.avatarUrl.isNotEmpty()) {
            Box(
                modifier = Modifier
                    .size(96.dp)
                    .clip(CircleShape)
                    .border(
                        width = if (p.hasYaPlus) 3.dp else 0.dp,
                        brush = UGColors.AccentGradient,
                        shape = CircleShape,
                    )
                    .combinedClickable(onClick = {}, onLongClick = onAvatarLongPress),
                contentAlignment = Alignment.Center,
            ) {
                AsyncImage(
                    model = p.avatarUrl,
                    contentDescription = p.displayName.ifEmpty { p.login },
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize().clip(CircleShape),
                )
            }
        } else {
            Box(
                modifier = Modifier
                    .size(96.dp)
                    .clip(CircleShape)
                    .background(UGColors.Elevated)
                    .combinedClickable(onClick = {}, onLongClick = onAvatarLongPress),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Filled.AccountCircle,
                    contentDescription = null,
                    tint = UGColors.TextMuted,
                    modifier = Modifier.size(56.dp),
                )
            }
        }
        Spacer(Modifier.size(16.dp))
        Column {
            val displayName = profile
                ?.let { it.displayName.ifEmpty { it.login }.ifEmpty { "Guest" } }
                ?: "Guest"
            Text(text = displayName, color = UGColors.TextPrimary, style = UGType.TitleL)
            if (p?.login?.isNotEmpty() == true && p.login != displayName) {
                Spacer(Modifier.height(2.dp))
                Text(text = p.login, color = UGColors.TextMuted, style = UGType.BodyS)
            }
            if (p?.hasYaPlus == true) {
                Spacer(Modifier.height(8.dp))
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(999.dp))
                        .background(UGColors.Accent.copy(alpha = 0.18f))
                        .padding(horizontal = 10.dp, vertical = 4.dp),
                ) {
                    Text(
                        text = "YANDEX PLUS",
                        color = UGColors.Accent,
                        style = UGType.Caption,
                    )
                }
            }
        }
    }
}

@Composable
private fun SettingsRow(
    icon: ImageVector,
    label: String,
    danger: Boolean = false,
    onClick: () -> Unit,
) {
    val tint = if (danger) UGColors.Danger else UGColors.TextPrimary
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(20.dp))
        Spacer(Modifier.size(14.dp))
        Text(text = label, color = tint, style = UGType.BodyS)
        Spacer(Modifier.weight(1f))
        if (!danger) {
            Icon(
                Icons.Filled.ChevronRight,
                contentDescription = null,
                tint = UGColors.TextMuted,
                modifier = Modifier.size(20.dp),
            )
        }
    }
}

@Composable
private fun Divider() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(1.dp)
            .padding(horizontal = 16.dp)
            .background(Color.Transparent), // visual divider via the surrounding cards' bg
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(UGColors.Divider),
        )
    }
}
