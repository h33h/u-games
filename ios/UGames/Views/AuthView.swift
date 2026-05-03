import SwiftUI
@preconcurrency import WebKit

struct AuthView: View {
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button(action: onClose) {
                        Image(systemName: "chevron.left")
                            .resizable()
                            .frame(width: 14, height: 22)
                            .foregroundColor(.white)
                            .padding(8)
                    }
                    Text("Sign in to Yandex")
                        .foregroundColor(.white)
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

                AuthWebView(onSignedIn: onClose)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
    }
}

private struct AuthWebView: UIViewRepresentable {
    let onSignedIn: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSignedIn: onSignedIn) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.backgroundColor = .black
        web.isOpaque = false
        var request = URLRequest(url: URL(string: "https://passport.yandex.com/auth?retpath=https%3A%2F%2Fyandex.com%2Fgames%2F")!)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        web.load(request)
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onSignedIn: () -> Void

        init(onSignedIn: @escaping () -> Void) {
            self.onSignedIn = onSignedIn
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url?.absoluteString else { return }
            if url.contains("yandex.com") && !url.contains("passport") {
                onSignedIn()
            }
        }
    }
}
