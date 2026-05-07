import SwiftUI

/// Pill text label. Replaces the half-dozen ad-hoc `Text + .padding +
/// .background + .clipShape(Capsule)` blobs scattered through the
/// catalog views.
struct UGChip: View {
    let text: String
    var style: Style = .neutral

    enum Style {
        /// Soft monochrome chip on dark surfaces (rating · count, age,
        /// hero meta facts).
        case neutral
        /// Brand-tinted soft chip ("✦ FEATURED TODAY", "YANDEX PLUS").
        case accentSoft
        /// Black overlay chip used on top of imagery, foreground accent
        /// (Tile rating "★ 4.9").
        case overlayRating
        /// Black overlay chip for neutral overlay text (page counter).
        case overlay
    }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundColor(foreground)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(background)
            .clipShape(Capsule())
    }

    private var font: Font {
        switch style {
        case .neutral, .overlay, .overlayRating: UGFont.caption
        case .accentSoft: UGFont.caption
        }
    }

    private var foreground: Color {
        switch style {
        case .neutral: UGColor.textSecondary
        case .accentSoft, .overlayRating: UGColor.accent
        case .overlay: UGColor.textSecondary
        }
    }

    private var background: Color {
        switch style {
        case .neutral: Color.white.opacity(0.08)
        case .accentSoft: UGColor.accent.opacity(0.18)
        case .overlayRating, .overlay: Color.black.opacity(0.55)
        }
    }

    // Component-internal paddings: tied to the chip's visual identity,
    // not the site-level spacing rhythm — kept as raw CGFloats so the
    // chip's geometry is independent of `UGSpace`.
    private var horizontalPadding: CGFloat {
        switch style {
        case .neutral: 9
        case .accentSoft: 10
        case .overlayRating, .overlay: 8
        }
    }

    private var verticalPadding: CGFloat {
        switch style {
        case .neutral, .accentSoft: 5
        case .overlayRating, .overlay: 3
        }
    }
}

@available(iOS 17.0, *)
#Preview(traits: .fixedLayout(width: 360, height: 80)) {
    ZStack {
        Color.black.ignoresSafeArea()
        HStack(spacing: 6) {
            UGChip(text: "★ 4.9", style: .neutral)
            UGChip(text: "✦ FEATURED", style: .accentSoft)
            UGChip(text: "★ 4.9", style: .overlayRating)
            UGChip(text: "1 / 4", style: .overlay)
        }
    }
}
