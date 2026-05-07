import SwiftUI

/// Minimal About screen. Push-style: receives `onBack` from the caller.
struct AboutView: View {
    let onBack: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            UGColor.bg0.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(UGColor.textPrimary)
                            .padding(8)
                    }
                    Text("About").font(UGFont.titleM).foregroundColor(UGColor.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                Spacer()
                VStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22).fill(UGColor.elevated)
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 48))
                            .foregroundColor(UGColor.accent)
                    }
                    .frame(width: 96, height: 96)
                    Text("U-Games").font(UGFont.titleL).foregroundColor(UGColor.textPrimary)
                    Text("v\(version)")
                        .font(UGFont.bodyS)
                        .foregroundColor(UGColor.textMuted)
                    Text("An unofficial Yandex Games wrapper. Open source under MIT.")
                        .font(UGFont.bodyS)
                        .foregroundColor(UGColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                    Link(destination: URL(string: "https://github.com/")!) {
                        Text("View on GitHub →")
                            .font(UGFont.bodyS)
                            .foregroundColor(UGColor.accent)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(UGColor.elevated)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
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
