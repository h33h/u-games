import SwiftUI

struct ErrorState: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(UGColor.textMuted)
                .padding(.bottom, 14)
            Text("Couldn't load")
                .font(UGFont.titleM)
                .foregroundColor(UGColor.textPrimary)
            Text(message)
                .font(UGFont.bodyS)
                .foregroundColor(UGColor.textMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
            Button(action: onRetry) {
                Text("Try again")
                    .font(UGFont.bodyS)
                    .foregroundColor(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(LinearGradient.ugAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
    }
}

@available(iOS 17.0, *)
#Preview(traits: .fixedLayout(width: 360, height: 320)) {
    ZStack {
        Color.black.ignoresSafeArea()
        ErrorState(message: "Check your connection and try again.", onRetry: {})
    }
}
