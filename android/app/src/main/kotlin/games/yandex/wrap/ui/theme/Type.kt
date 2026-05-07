package games.yandex.wrap.ui.theme

import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/**
 * U-Games typography tokens. Names match the spec table.
 * Uses the system font (no custom font asset).
 */
object UGType {
    val DisplayXL = TextStyle(
        fontSize = 34.sp, fontWeight = FontWeight.Black, letterSpacing = (-1.0).sp,
    )
    val Display = TextStyle(
        fontSize = 30.sp, fontWeight = FontWeight.Black, letterSpacing = (-0.8).sp,
    )
    val TitleL = TextStyle(
        fontSize = 24.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = (-0.5).sp,
    )
    val TitleM = TextStyle(
        fontSize = 18.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = (-0.3).sp,
    )
    val Body = TextStyle(
        fontSize = 15.sp, fontWeight = FontWeight.Normal,
    )
    val BodyS = TextStyle(
        fontSize = 13.sp, fontWeight = FontWeight.Medium,
    )
    val Label = TextStyle(
        fontSize = 11.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 1.2.sp,
    )
    val Caption = TextStyle(
        fontSize = 10.sp, fontWeight = FontWeight.Bold,
    )
}
