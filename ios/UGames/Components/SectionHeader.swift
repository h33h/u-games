import SwiftUI

/// Title strip used to introduce a horizontal row or content block.
/// Optionally renders a "See all →" trailing button when `seeAllAction`
/// is non-nil.
struct SectionHeader: View {
    let title: String
    var seeAllAction: (() -> Void)? = nil
    var horizontalPadding: CGFloat = UGSpace.l

    var body: some View {
        HStack {
            Text(title)
                .font(UGFont.titleM)
                .foregroundColor(UGColor.textPrimary)
            Spacer()
            if let seeAllAction {
                Button(action: seeAllAction) {
                    HStack(spacing: UGSpace.xs) {
                        Text("See all")
                            .font(UGFont.bodyS)
                            .foregroundColor(UGColor.textSecondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(UGColor.textSecondary)
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, horizontalPadding)
    }
}

/// Uppercase, letter-spaced "eyebrow" label (ABOUT / SCREENSHOTS /
/// INFORMATION / SPOTLIGHT). The text is uppercased here so callers
/// can pass mixed-case strings without having to remember.
struct UGEyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(UGFont.label)
            .tracking(1.2)
            .foregroundColor(UGColor.textMuted)
    }
}

@available(iOS 17.0, *)
#Preview(traits: .fixedLayout(width: 360, height: 200)) {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(title: "Trending now", seeAllAction: {})
            SectionHeader(title: "More like this")
            UGEyebrow(text: "About")
        }
    }
}
