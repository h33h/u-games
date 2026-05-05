import SwiftUI

/// Animated shimmer placeholder. Replaces ProgressView spinners. Animates a
/// left-to-right gradient sweep at 1.4s on infinite repeat.
struct Skeleton: View {
    var cornerRadius: CGFloat = 12

    @State private var phase: CGFloat = -0.3

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: UGColor.elevated, location: 0),
                        .init(color: Color(red: 0x22 / 255.0, green: 0x22 / 255.0, blue: 0x2A / 255.0), location: max(0, min(1, phase + 0.3))),
                        .init(color: UGColor.elevated, location: max(0, min(1, phase + 0.6))),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.0
                }
            }
    }
}

@available(iOS 17.0, *)
#Preview(traits: .fixedLayout(width: 360, height: 120)) {
    ZStack {
        Color.black.ignoresSafeArea()
        Skeleton()
            .padding()
            .frame(height: 120)
    }
}
