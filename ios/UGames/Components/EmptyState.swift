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
                .foregroundColor(UGColor.Text.muted)
                .padding(.bottom, UGSpace.l)
            Text(title)
                .font(UGFont.titleM)
                .foregroundColor(UGColor.Text.primary)
            if let message, !message.isEmpty {
                Text(message)
                    .font(UGFont.bodyS)
                    .foregroundColor(UGColor.Text.muted)
                    .multilineTextAlignment(.center)
                    .padding(.top, UGSpace.s)
            }
            if let ctaLabel, let onCta {
                UGPillButton(title: ctaLabel, shape: .rounded(UGRadius.m), action: onCta)
                    .padding(.top, UGSpace.l)
            }
        }
        .padding(.horizontal, UGSpace.xxl)
        .padding(.vertical, UGSpace.huge)
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
