import SwiftUI

/// Minimal About screen. Push-style: receives `onBack` from the caller.
struct AboutView: View {
    let onBack: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            UGColor.bg0.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                UGTopBar(title: "About", onBack: onBack)
                Spacer()
                VStack(spacing: UGSpace.l) {
                    ZStack {
                        RoundedRectangle(cornerRadius: UGRadius.xl).fill(UGColor.elevated)
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 48))
                            .foregroundColor(UGColor.accent)
                    }
                    .frame(width: UGSize.avatarL, height: UGSize.avatarL)
                    Text("U-Games").font(UGFont.titleL).foregroundColor(UGColor.textPrimary)
                    Text("v\(version)")
                        .font(UGFont.bodyS)
                        .foregroundColor(UGColor.textMuted)
                    Text("An unofficial Yandex Games wrapper. Open source under MIT.")
                        .font(UGFont.bodyS)
                        .foregroundColor(UGColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, UGSpace.xxxl)
                    Link(destination: URL(string: "https://github.com/")!) {
                        Text("View on GitHub →")
                            .font(UGFont.bodyS)
                            .foregroundColor(UGColor.accent)
                            .padding(.horizontal, UGSpace.l)
                            .padding(.vertical, UGSpace.s)
                            .background(UGColor.elevated)
                            .clipShape(RoundedRectangle(cornerRadius: UGRadius.m))
                    }
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
        }
    }

    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
    }
}
