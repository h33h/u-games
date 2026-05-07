import SwiftUI

struct AboutView: View {
    let onBack: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            UGColor.Surface.base.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                UGTopBar(title: "About", onBack: onBack)
                Spacer()
                VStack(spacing: UGSpace.l) {
                    ZStack {
                        RoundedRectangle(cornerRadius: UGRadius.xl).fill(UGColor.Surface.raised)
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 48))
                            .foregroundColor(UGColor.Accent.primary)
                    }
                    .frame(width: UGSize.avatarL, height: UGSize.avatarL)
                    Text("U-Games").font(UGFont.titleL).foregroundColor(UGColor.Text.primary)
                    Text("v\(version)")
                        .font(UGFont.bodyS)
                        .foregroundColor(UGColor.Text.muted)
                    Text("An unofficial Yandex Games wrapper. Open source under MIT.")
                        .font(UGFont.bodyS)
                        .foregroundColor(UGColor.Text.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, UGSpace.xxxl)
                    Link(destination: URL(string: "https://github.com/")!) {
                        Text("View on GitHub →")
                            .font(UGFont.bodyS)
                            .foregroundColor(UGColor.Accent.primary)
                            .padding(.horizontal, UGSpace.l)
                            .padding(.vertical, UGSpace.s)
                            .background(UGColor.Surface.raised)
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
