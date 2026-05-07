import SwiftUI

struct ErrorState: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(UGColor.textMuted)
                .padding(.bottom, UGSpace.l)
            Text("Couldn't load")
                .font(UGFont.titleM)
                .foregroundColor(UGColor.textPrimary)
            Text(message)
                .font(UGFont.bodyS)
                .foregroundColor(UGColor.textMuted)
                .multilineTextAlignment(.center)
                .padding(.top, UGSpace.s)
            UGPillButton(title: "Try again", shape: .rounded(UGRadius.m), action: onRetry)
                .padding(.top, UGSpace.l)
        }
        .padding(.horizontal, UGSpace.xxl)
        .padding(.vertical, UGSpace.huge)
    }
}

@available(iOS 17.0, *)
#Preview(traits: .fixedLayout(width: 360, height: 320)) {
    ZStack {
        Color.black.ignoresSafeArea()
        ErrorState(message: "Check your connection and try again.", onRetry: {})
    }
}
