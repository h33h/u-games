import SwiftUI

struct EmptyState: View {
    let systemIcon: String
    let title: String
    var message: String? = nil
    var ctaLabel: String? = nil
    var onCta: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: systemIcon)
                .font(.system(size: 48, weight: .light))
                .foregroundColor(UGColor.textMuted)
                .padding(.bottom, 14)
            Text(title)
                .font(UGFont.titleM)
                .foregroundColor(UGColor.textPrimary)
            if let message, !message.isEmpty {
                Text(message)
                    .font(UGFont.bodyS)
                    .foregroundColor(UGColor.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
            if let ctaLabel, let onCta {
                Button(action: onCta) {
                    Text(ctaLabel)
                        .font(UGFont.bodyS)
                        .foregroundColor(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(LinearGradient.ugAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.top, 16)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
    }
}

@available(iOS 17.0, *)
#Preview(traits: .fixedLayout(width: 360, height: 320)) {
    ZStack {
        Color.black.ignoresSafeArea()
        EmptyState(
            systemIcon: "heart",
            title: "No favorites yet",
            message: "Tap ♥ on any game to save it.",
            ctaLabel: "Browse games",
            onCta: {}
        )
    }
}
