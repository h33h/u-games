import SwiftUI

struct UGPillButton: View {
    let title: String
    var shape: Shape = .capsule
    var size: Size = .regular
    var glow: Bool = false
    let action: () -> Void

    enum Shape {
        case capsule
        case rounded(CGFloat)

        @ViewBuilder
        func clip<Content: View>(_ content: Content) -> some View {
            switch self {
            case .capsule:
                content.clipShape(Capsule())
            case .rounded(let r):
                content.clipShape(RoundedRectangle(cornerRadius: r))
            }
        }
    }

    enum Size {
        case regular
        case large

        var horizontalPadding: CGFloat {
            switch self { case .regular: 22; case .large: 28 }
        }

        var verticalPadding: CGFloat {
            switch self { case .regular: 11; case .large: 14 }
        }
    }

    var body: some View {
        Button {
            UGHaptics.cta()
            action()
        } label: {
            shape.clip(
                Text(title)
                    .font(UGFont.bodyS.weight(.heavy))
                    .foregroundColor(.black)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, size.verticalPadding)
                    .background(LinearGradient.ugAccent)
            )
            .modifier(OptionalGlow(enabled: glow))
        }
        .buttonStyle(.borderless)
    }

    private var horizontalPadding: CGFloat {
        switch shape {
        case .capsule: size.horizontalPadding
        case .rounded: 18
        }
    }
}

private struct OptionalGlow: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.ugShadow(.cta(UGColor.accent))
        } else {
            content
        }
    }
}

@available(iOS 17.0, *)
#Preview(traits: .fixedLayout(width: 360, height: 200)) {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 20) {
            UGPillButton(title: "▶ Play now", glow: true, action: {})
            UGPillButton(title: "Try again", shape: .rounded(14), action: {})
        }
    }
}
