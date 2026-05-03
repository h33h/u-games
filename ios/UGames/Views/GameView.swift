import SwiftUI

struct GameView: View {
    let appId: Int64
    let title: String
    let scripts: InjectedScripts
    let blockList: BlockList
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let url = URL(string: "https://yandex.com/games/app/\(appId)") {
                GameWebView(url: url, scripts: scripts, blockList: blockList)
                    .ignoresSafeArea()
            }
        }
        .navigationBarBackButtonHidden(true)
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.width > 80 { onBack() }
                }
        )
    }
}
