import SwiftUI

struct UGTopBar<Trailing: View>: View {
    let title: String
    let onBack: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack {
            Button {
                UGHaptics.tap()
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(UGColor.Text.primary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Back")
            Text(title)
                .font(UGFont.titleM)
                .foregroundColor(UGColor.Text.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing()
        }
        .padding(.horizontal, UGSpace.s)
    }
}

extension UGTopBar where Trailing == EmptyView {
    init(title: String, onBack: @escaping () -> Void) {
        self.title = title
        self.onBack = onBack
        self.trailing = { EmptyView() }
    }
}
