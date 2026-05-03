import SwiftUI

struct GameView: View {
    let appId: Int64
    let title: String
    let scripts: InjectedScripts
    let blockList: BlockList
    let onBack: () -> Void

    @State private var showBack: Bool = true
    @State private var revision: Int = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let url = URL(string: "https://yandex.com/games/app/\(appId)") {
                GameWebView(url: url, scripts: scripts, blockList: blockList)
            }

            // Tap-to-reveal hot zone — small enough to not steal touches.
            Color.clear
                .frame(width: 64, height: 64)
                .contentShape(Rectangle())
                .onTapGesture { revision += 1 }

            if showBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.black.opacity(0.8))
                        .clipShape(Circle())
                }
                .padding(.leading, 12)
                .padding(.top, 8)
                .transition(.opacity)
            }
        }
        .navigationBarBackButtonHidden(true)
        .onChange(of: revision) { _ in scheduleHide() }
        .onAppear { scheduleHide() }
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.width > 80 && abs(value.translation.height) < 60 {
                        onBack()
                    }
                }
        )
    }

    private func scheduleHide() {
        showBack = true
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                withAnimation { showBack = false }
            }
        }
    }
}
