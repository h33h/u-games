import SwiftUI
import UIKit

struct GameView: View {
    let appId: Int64
    let title: String
    let scripts: InjectedScripts
    let blockList: BlockList
    let onBack: () -> Void

    @State private var showBack: Bool = true
    @State private var revision: Int = 0
    @StateObject private var orient: OrientationStore = .shared

    var body: some View {
        // Derive the current orientation from the actual layout size rather
        // than from `UIDevice.current.orientation`. UIDevice's reading is
        // unreliable until orientation notifications are turned on (and
        // returns `.unknown`/`.faceUp`/`.faceDown` when the phone is flat),
        // which used to make the rotate-overlay flash on entry. The view's
        // size is the source of truth for what the user sees.
        GeometryReader { proxy in
            let isPortrait = proxy.size.height >= proxy.size.width
            content(isPortrait: isPortrait)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func content(isPortrait: Bool) -> some View {
        let overlayVisible = isOverlayVisible(isPortrait: isPortrait)
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let url = URL(string: "https://yandex.com/games/app/\(appId)") {
                GameWebView(
                    url: url,
                    scripts: scripts,
                    blockList: blockList,
                    paused: overlayVisible,
                )
            }

            // Tap-to-reveal hot zone — small enough to not steal touches.
            Color.clear
                .frame(width: 64, height: 64)
                .contentShape(Rectangle())
                .onTapGesture { revision += 1 }

            if showBack {
                UGCircleIconButton(
                    systemName: "chevron.left",
                    tint: .white,
                    diameter: 40,
                    iconSize: 18,
                    background: Color.black.opacity(0.8),
                    action: onBack
                )
                .padding(.leading, UGSpace.m)
                .padding(.top, UGSpace.s)
                .transition(.opacity)
            }

            if overlayVisible, let target = orient.required {
                RotateDeviceOverlay(target: target, onBack: onBack)
                    .transition(.opacity)
            }
        }
        .navigationBarBackButtonHidden(true)
        .onChange(of: revision) { _ in scheduleHide() }
        .onAppear {
            orient.reset()
            scheduleHide()
        }
        .onDisappear {
            orient.reset()
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.width > 80 && abs(value.translation.height) < 60 {
                        onBack()
                    }
                }
        )
    }

    private func isOverlayVisible(isPortrait: Bool) -> Bool {
        switch orient.required {
        case .landscape: return isPortrait
        case .portrait: return !isPortrait
        case .none: return false
        }
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

/// Full-screen overlay shown when the running game requested an orientation
/// that the device is not currently in. Rotation is detected via
/// `screen.orientation.lock()` calls trapped by the SDK stub.
private struct RotateDeviceOverlay: View {
    let target: OrientationStore.Required
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.96).ignoresSafeArea()
            VStack(spacing: UGSpace.xxxl) {
                Image(systemName: "rotate.right")
                    .font(.system(size: 96, weight: .light))
                    .foregroundColor(.white)
                    .rotationEffect(target == .landscape ? .degrees(0) : .degrees(90))

                Text(headline)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text(subheadline)
                    .font(.callout)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, UGSpace.huge)

                Button(action: onBack) {
                    Text("Назад в каталог")
                        .font(.callout)
                        .foregroundColor(.white)
                        .padding(.horizontal, UGSpace.xxl)
                        .padding(.vertical, UGSpace.m)
                        .overlay(
                            RoundedRectangle(cornerRadius: UGRadius.xl)
                                .stroke(Color.white.opacity(0.4), lineWidth: 1)
                        )
                }
                .padding(.top, UGSpace.s)
            }
            .padding()
        }
    }

    private var headline: String {
        target == .landscape ? "Поверните устройство" : "Поверните в портрет"
    }
    private var subheadline: String {
        target == .landscape
            ? "Эта игра работает в горизонтальной ориентации."
            : "Эта игра работает в вертикальной ориентации."
    }
}
