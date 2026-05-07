import SwiftUI

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
