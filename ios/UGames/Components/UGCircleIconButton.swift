import SwiftUI

struct UGCircleIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    var tint: Color = UGColor.textPrimary

    var diameter: CGFloat = UGSize.buttonL

    var iconSize: CGFloat = 16
    var iconWeight: Font.Weight = .semibold
    var background: Color = UGColor.overlayBg
    let action: () -> Void

    var body: some View {
        Button {
            UGHaptics.tap()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: iconWeight))
                .foregroundColor(tint)
                .frame(width: diameter, height: diameter)
                .background(background)
                .clipShape(Circle())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(accessibilityLabel)
    }
}

@available(iOS 17.0, *)
#Preview(traits: .fixedLayout(width: 240, height: 80)) {
    ZStack {
        Color.gray.ignoresSafeArea()
        HStack(spacing: 12) {
            UGCircleIconButton(systemName: "chevron.left", accessibilityLabel: "Back", action: {})
            UGCircleIconButton(systemName: "heart.fill", accessibilityLabel: "Remove from favorites", tint: UGColor.danger, action: {})
            UGCircleIconButton(systemName: "square.and.arrow.up", accessibilityLabel: "Share", action: {})
            UGCircleIconButton(systemName: "xmark", accessibilityLabel: "Close", action: {})
        }
    }
}
