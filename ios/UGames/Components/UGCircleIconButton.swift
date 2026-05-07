import SwiftUI

/// Round translucent-black icon button used for hero overlays
/// (back / heart / share / close) on top of imagery. Replaces the
/// repeated `Button { Image .frame .background(.black 0.55) .clipShape(Circle) }`
/// blocks across Hero, GameDetail, GameCard heart, and the screenshots
/// fullscreen viewer.
struct UGCircleIconButton: View {
    let systemName: String
    var tint: Color = UGColor.textPrimary
    /// Diameter of the tappable disc.
    var diameter: CGFloat = UGSize.buttonL
    /// Glyph weight + size.
    var iconSize: CGFloat = 16
    var iconWeight: Font.Weight = .semibold
    var background: Color = Color.black.opacity(0.55)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: iconWeight))
                .foregroundColor(tint)
                .frame(width: diameter, height: diameter)
                .background(background)
                .clipShape(Circle())
        }
        .buttonStyle(.borderless)
    }
}

@available(iOS 17.0, *)
#Preview(traits: .fixedLayout(width: 240, height: 80)) {
    ZStack {
        Color.gray.ignoresSafeArea()
        HStack(spacing: 12) {
            UGCircleIconButton(systemName: "chevron.left", action: {})
            UGCircleIconButton(systemName: "heart.fill", tint: UGColor.danger, action: {})
            UGCircleIconButton(systemName: "square.and.arrow.up", action: {})
            UGCircleIconButton(systemName: "xmark", action: {})
        }
    }
}
