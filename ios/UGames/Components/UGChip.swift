import SwiftUI

struct UGChip: View {
    let text: String
    var style: Style = .neutral

    enum Style {
        case neutral
        case accentSoft
        case overlayRating
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
        case .neutral: UGColor.Text.secondary
        case .accentSoft, .overlayRating: UGColor.Accent.primary
        case .overlay: UGColor.Text.secondary
        }
    }

    private var background: Color {
        switch style {
        case .neutral: Color.white.opacity(0.08)
        case .accentSoft: UGColor.Accent.primary.opacity(0.18)
        case .overlayRating, .overlay: UGColor.Surface.overlay
        }
    }

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
