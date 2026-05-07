import SwiftUI

/// Plain push-style top bar: leading chevron back-button + centered-ish
/// title. Used by Profile and About. GameDetail still rolls its own
/// because it sits over imagery and uses circular icon buttons instead.
struct UGTopBar: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(UGColor.textPrimary)
                    .padding(UGSpace.s)
            }
            Text(title)
                .font(UGFont.titleM)
                .foregroundColor(UGColor.textPrimary)
            Spacer()
        }
        .padding(.horizontal, UGSpace.s)
    }
}
