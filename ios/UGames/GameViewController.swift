import UIKit
import WebKit

final class GameViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    var webView: WKWebView?
    private var backgroundObservation: NSKeyValueObservation?
    private let preparedView: WKWebView?
    var offlineGame: SavedOfflineGame?
    var isOfflineCatalog = false
    let connectivity: OfflineConnectivity
    var contextGeneration = 0
    var observers: [NSObjectProtocol] = []
    private var controllerIsActive = true
    let offlineStore: OfflineGameStore
    private let spinner = UIActivityIndicatorView(style: .medium)
    var errorPanel: UIStackView?
    var retryURL = URL(string: "https://yandex.ru/games/")!

    init(
        preparedView: WKWebView? = nil,
        offlineGame: SavedOfflineGame? = nil,
        offlineStore: OfflineGameStore = .shared,
        connectivity: OfflineConnectivity? = nil
    ) {
        self.preparedView = preparedView
        self.offlineGame = offlineGame
        self.offlineStore = offlineStore
        self.connectivity = connectivity ?? (offlineGame == nil ? .shared : OfflineConnectivity(
            status: .offline,
            monitoring: false
        ))
        isOfflineCatalog = offlineGame == nil && self.connectivity.status == .offline
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
        observeConnectionAndLifecycle()
        if let preparedView = preparedView {
            attach(preparedView)
        } else {
            if isOfflineCatalog {
                retryURL = OfflineCatalog.url
            }
            prepareAndLoad(retryURL)
        }
    }

    override var prefersStatusBarHidden: Bool {
        true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
        controllerIsActive = true
        if let view = webView {
            OfflineGameReportReceiver.shared.setActive(true, in: view)
        }
        connectionDidChange()
        if isOfflineCatalog, let view = webView,
           let source = try? OfflineCatalog.configuration(store: offlineStore)
        {
            view.evaluateJavaScript(source + "window.__UGamesOfflineCatalog?.render();")
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let canGoBack = (navigationController?.viewControllers.count ?? 0) > 1
        navigationController?.interactivePopGestureRecognizer?.delegate = nil
        navigationController?.interactivePopGestureRecognizer?.isEnabled = canGoBack
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        controllerIsActive = false
        if let view = webView {
            OfflineGameReportReceiver.shared.captureProgress(in: view) {}
            OfflineGameReportReceiver.shared.setActive(false, in: view)
        }
    }

    func prepareAndLoad(_ url: URL, restoringProgressFrom game: SavedOfflineGame? = nil) {
        spinner.startAnimating()
        let generation = contextGeneration
        ProtectedWebViewFactory
            .make(
                offlineGame: offlineGame,
                offlineCatalog: isOfflineCatalog,
                offlineStore: offlineStore,
                connectivity: connectivity,
                restoringProgressFrom: game
            ) { [weak self] result in
                guard let self = self, self.contextGeneration == generation else { return }
                switch result {
                case let .success(view):
                    if self.offlineGame != nil || self.isOfflineCatalog,
                       self.connectivity.status != .offline
                    {
                        let game = self.offlineGame
                        self.switchContext(
                            to: game?.url ?? OfflineCatalog.onlineURL,
                            game: nil,
                            catalog: false,
                            restore: game
                        )
                        return
                    }
                    if self.offlineGame == nil, !self.isOfflineCatalog,
                       self.connectivity.status == .offline
                    {
                        self.openWithoutNetwork(url)
                        return
                    }
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
        OfflineGameReportReceiver.shared.setActive(controllerIsActive, in: webView)
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
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        if let webView = webView {
            OfflineGameReportReceiver.shared.unregister(webView)
        }
    }

    @objc func openCatalog() {
        if let navigation = navigationController, navigation.viewControllers.first !== self {
            navigation.popToRootViewController(animated: true)
            (navigation.viewControllers.first as? GameViewController)?.openCatalog()
            return
        }
        let local = connectivity.status == .offline
        switchContext(
            to: local ? OfflineCatalog.url : OfflineCatalog.onlineURL,
            game: nil,
            catalog: local
        )
    }

    @objc private func retry() {
        errorPanel?.removeFromSuperview()
        errorPanel = nil
        webView?.isHidden = false
        view.backgroundColor = webView?.underPageBackgroundColor ?? UGamesTheme.background
        if offlineGame != nil || isOfflineCatalog {
            switchContext(to: retryURL, game: offlineGame, catalog: isOfflineCatalog)
        } else if let webView = webView {
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
        ProtectedWebViewFactory.finishProgressRestoration(in: webView)
        if let url = webView.url, url.scheme == "https" {
            retryURL = url
        }
    }

    func webView(
        _: WKWebView,
        didFailProvisionalNavigation _: WKNavigation!,
        withError error: Error
    ) {
        if (error as NSError).code == NSURLErrorCancelled {
            return
        }
        if offlineGame == nil, !isOfflineCatalog,
           connectivity.noteConnectionFailure(error)
        {
            return
        }
        if connectivity.status == .offline, offlineGame == nil, !isOfflineCatalog {
            openWithoutNetwork(retryURL)
            return
        }
        if (error as NSError).code != NSURLErrorCancelled {
            showError(offlineGame == nil ?
                "Не удалось открыть страницу. Проверь подключение и попробуй ещё раз." :
                "Не удалось открыть сохранённую игру. Открой её с интернетом.")
        }
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        if offlineGame == nil, !isOfflineCatalog,
           connectivity.noteConnectionFailure(error)
        {
            return
        }
        if (error as NSError)
            .code != NSURLErrorCancelled
        {
            showError(offlineGame == nil ? "Игра не загрузилась. Попробуй ещё раз." :
                "Не удалось прочитать файлы сохранённой игры. Открой её с интернетом.")
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
        if connectivity.status == .offline, mainWindow, url.scheme == "https",
           OfflineResourcePolicy.isGameURL(url) || GameNavigationPolicy.allows(url)
        {
            decisionHandler(.cancel)
            openWithoutNetwork(url)
            return
        }
        if connectivity.status == .offline, mainWindow, OfflineCatalog.isDocument(url),
           !isOfflineCatalog
        {
            decisionHandler(.cancel)
            openWithoutNetwork(OfflineCatalog.onlineURL)
            return
        }
        let allowed: Bool
        if isOfflineCatalog {
            allowed = mainWindow && OfflineCatalog.isDocument(url)
        } else if let game = offlineGame {
            allowed = OfflineNavigationPolicy.allows(url, in: game, isMainFrame: mainWindow)
        } else {
            allowed = mainWindow ?
                (GameNavigationPolicy.allows(url) || OfflineResourcePolicy.isGameURL(url)) :
                GameNavigationPolicy
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
}
