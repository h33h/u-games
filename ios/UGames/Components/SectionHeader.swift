import SwiftUI

struct SectionHeader: View {
    let title: String
    var seeAllAction: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(UGFont.titleM)
                .foregroundColor(UGColor.Text.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let seeAllAction {
                Button {
                    UGHaptics.tap()
                    seeAllAction()
                } label: {
                    HStack(spacing: UGSpace.xs) {
                        Text("See all")
                            .font(UGFont.bodyS)
                            .foregroundColor(UGColor.Text.secondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(UGColor.Text.secondary)
                    }
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("See all \(title)")
            }
        }
        .padding(.horizontal, UGSpace.l)
    }
}

struct UGEyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(UGFont.label)
            .tracking(1.2)
            .foregroundColor(UGColor.Text.muted)
            .accessibilityAddTraits(.isHeader)
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
