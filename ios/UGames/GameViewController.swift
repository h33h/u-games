import UIKit
import WebKit

final class GameViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    var webView: WKWebView?
    private var backgroundObservation: NSKeyValueObservation?
    private let preparedView: WKWebView?
    let offlineGame: SavedOfflineGame?
    let offlineStore: OfflineGameStore
    let menuButton = UIButton(type: .system)
    var saving = false
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var errorPanel: UIStackView?
    private(set) var retryURL = URL(string: "https://yandex.ru/games/")!

    init(
        preparedView: WKWebView? = nil,
        offlineGame: SavedOfflineGame? = nil,
        offlineStore: OfflineGameStore = .shared
    ) {
        self.preparedView = preparedView
        self.offlineGame = offlineGame
        self.offlineStore = offlineStore
        super.init(nibName: nil, bundle: nil)
        if let game = offlineGame {
            retryURL = game.offlineURL
        }
    }

    required init?(coder _: NSCoder) {
        fatalError("Use programmatic initialization")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "UGames"
        view.backgroundColor = UGamesTheme.background
        view.tintColor = UGamesTheme.mint
        spinner.color = UGamesTheme.mint
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        configureMenu()
        if let preparedView = preparedView {
            attach(preparedView)
        } else {
            prepareAndLoad(retryURL)
        }
    }

    override var prefersStatusBarHidden: Bool {
        true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    private func prepareAndLoad(_ url: URL) {
        spinner.startAnimating()
        ProtectedWebViewFactory
            .make(offlineGame: offlineGame, offlineStore: offlineStore) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case let .success(view):
                    self.attach(view)
                    view.load(URLRequest(url: url))
                case .failure:
                    self
                        .showError(
                            "Не удалось подготовить приложение. Попробуй перезапустить UGames."
                        )
                }
            }
    }

    private func attach(_ webView: WKWebView) {
        if let previous = self.webView {
            previous.navigationDelegate = nil
            previous.uiDelegate = nil
            previous.stopLoading()
            OfflineGameReportReceiver.shared.unregister(previous)
            previous.removeFromSuperview()
        }
        self.webView = webView
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(webView, at: 0)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        backgroundObservation = webView.observe(
            \.underPageBackgroundColor,
            options: [.initial, .new]
        ) { [weak self] page, _ in
            guard let self = self, self.errorPanel == nil else { return }
            self.view.backgroundColor = page.underPageBackgroundColor
        }
        updateMenu()
    }

    @objc func openCatalog() {
        if let navigation = navigationController, navigation.viewControllers.first !== self {
            navigation.popToRootViewController(animated: true)
            if let root = navigationController?.viewControllers
                .first as? GameViewController
            {
                root.openCatalog()
            }
            return
        }
        if offlineGame != nil {
            let catalog = GameViewController(offlineStore: offlineStore)
            navigationController?.setViewControllers([catalog], animated: true)
            return
        }
        retryURL = URL(string: "https://yandex.ru/games/")!
        retry()
    }

    @objc private func retry() {
        errorPanel?.removeFromSuperview()
        errorPanel = nil
        webView?.isHidden = false
        view.backgroundColor = webView?.underPageBackgroundColor ?? UGamesTheme.background
        if offlineGame != nil {
            webView?.stopLoading()
            webView?.isHidden = true
            if let webView = webView {
                OfflineGameReportReceiver.shared.unregister(webView)
            }
            prepareAndLoad(retryURL)
            return
        }
        if let webView = webView {
            webView.load(URLRequest(url: retryURL))
        } else {
            prepareAndLoad(retryURL)
        }
    }

    private func showError(_ message: String) {
        spinner.stopAnimating()
        view.backgroundColor = UGamesTheme.background
        webView?.isHidden = true
        errorPanel?.removeFromSuperview()
        let label = UILabel()
        label.text = message
        label.textColor = UGamesTheme.text
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        let retry = UIButton(type: .system)
        var retryStyle = UIButton.Configuration.filled()
        retryStyle.baseBackgroundColor = UGamesTheme.accent
        retryStyle.baseForegroundColor = .white
        retry.configuration = retryStyle
        retry.setTitle("Попробовать снова", for: .normal)
        retry.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        retry.titleLabel?.adjustsFontForContentSizeCategory = true
        retry.addTarget(self, action: #selector(self.retry), for: .touchUpInside)
        retry.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        let catalog = UIButton(type: .system)
        var catalogStyle = UIButton.Configuration.filled()
        catalogStyle.baseBackgroundColor = UGamesTheme.surface
        catalogStyle.baseForegroundColor = UGamesTheme.mint
        catalog.configuration = catalogStyle
        catalog.setTitle("В каталог", for: .normal)
        catalog.titleLabel?.font = .preferredFont(forTextStyle: .body)
        catalog.titleLabel?.adjustsFontForContentSizeCategory = true
        catalog.addTarget(self, action: #selector(openCatalog), for: .touchUpInside)
        catalog.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        let panel = UIStackView(arrangedSubviews: [label, retry, catalog])
        panel.axis = .vertical
        panel.spacing = 16
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)
        view.bringSubviewToFront(menuButton)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: 24
            ),
            panel.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -24
            ),
            panel.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
        ])
        errorPanel = panel
    }

    func showProtectionError() {
        showError("Эта игра пока не работает без рекламы. Выбери другую в каталоге.")
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
        errorPanel?.removeFromSuperview()
        errorPanel = nil
        webView.isHidden = false
        view.backgroundColor = webView.underPageBackgroundColor
        spinner.startAnimating()
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        spinner.stopAnimating()
        if let url = webView.url, url.scheme == "https" {
            retryURL = url
        }
    }

    func webView(
        _: WKWebView,
        didFailProvisionalNavigation _: WKNavigation!,
        withError error: Error
    ) {
        if (error as NSError)
            .code !=
            NSURLErrorCancelled
        {
            showError(offlineGame == nil ?
                "Не удалось открыть страницу. Проверь подключение и попробуй ещё раз." :
                "Не удалось открыть сохранённую игру. Открой её с интернетом и сохрани снова.")
        }
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        if (error as NSError)
            .code != NSURLErrorCancelled
        {
            showError(offlineGame == nil ? "Игра не загрузилась. Попробуй ещё раз." :
                "Не удалось прочитать файлы сохранённой игры. Открой её с интернетом и сохрани снова.")
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = action.request.url else {
            decisionHandler(.cancel)
            return
        }
        let mainWindow = action.targetFrame?.isMainFrame != false
        let allowed: Bool
        if let game = offlineGame {
            allowed = OfflineNavigationPolicy.allows(url, in: game, isMainFrame: mainWindow)
        } else {
            allowed = mainWindow ? GameNavigationPolicy.allows(url) : GameNavigationPolicy
                .allowsFrame(
                    url,
                    source: action.sourceFrame.request.url
                )
        }
        if allowed {
            OfflineGameReportReceiver.shared.noteNavigation(
                to: url,
                in: webView,
                mainFrame: mainWindow
            )
            if action.targetFrame?.isMainFrame == true,
               url.scheme == "https"
            {
                retryURL = url
            }
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            if preparedView != nil,
               webView.url == nil || webView.url?.absoluteString == "about:blank"
            {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self,
                          self.navigationController?.topViewController === self else { return }
                    self.navigationController?.popViewController(animated: true)
                }
            }
        }
    }

    func webViewWebContentProcessDidTerminate(_: WKWebView) {
        // Offer a reload; never replay an already completed reward from native state.
        showError("Игра закрылась. Можно открыть её снова.")
    }

    func webView(
        _ parent: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for action: WKNavigationAction,
        windowFeatures _: WKWindowFeatures
    ) -> WKWebView? {
        guard offlineGame == nil else { return nil }
        guard let url = action.request.url, GameNavigationPolicy.allows(url) else { return nil }
        let child = ProtectedWebViewFactory.makePopup(configuration: configuration, parent: parent)
        let controller = GameViewController(preparedView: child)
        navigationController?.pushViewController(controller, animated: true)
        return child
    }

    func webViewDidClose(_: WKWebView) {
        navigationController?.popViewController(animated: true)
    }

    func webView(
        _: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame _: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.overrideUserInterfaceStyle = .dark
        alert.view.tintColor = UGamesTheme.mint
        alert.addAction(UIAlertAction(title: "ОК", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(
        _: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame _: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.overrideUserInterfaceStyle = .dark
        alert.view.tintColor = UGamesTheme.mint
        alert
            .addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in
                completionHandler(false)
            })
        alert
            .addAction(UIAlertAction(title: "ОК", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    func webView(
        _: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame _: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.overrideUserInterfaceStyle = .dark
        alert.view.tintColor = UGamesTheme.mint
        alert.addTextField {
            $0.text = defaultText
            $0.textColor = UGamesTheme.text
            $0.backgroundColor = UGamesTheme.surface
            $0.tintColor = UGamesTheme.mint
        }
        alert
            .addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in
                completionHandler(nil)
            })
        alert
            .addAction(UIAlertAction(title: "ОК", style: .default) { _ in
                completionHandler(alert.textFields?.first?.text)
            })
        present(alert, animated: true)
    }
}
