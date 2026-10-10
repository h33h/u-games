import UIKit
import WebKit

final class GameViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private var webView: WKWebView?
    private var backgroundObservation: NSKeyValueObservation?
    private let preparedView: WKWebView?
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var errorPanel: UIStackView?
    private(set) var retryURL = URL(string: "https://yandex.ru/games/")!

    init(preparedView: WKWebView? = nil) {
        self.preparedView = preparedView
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder _: NSCoder) {
        fatalError("Use programmatic initialization")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "UGames"
        view.backgroundColor = .systemBackground
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
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
        ProtectedWebViewFactory.make { [weak self] result in
            guard let self = self else { return }
            switch result {
            case let .success(view):
                self.attach(view)
                view.load(URLRequest(url: url))
            case .failure:
                self.showError("Не удалось подготовить приложение. Попробуй перезапустить UGames.")
            }
        }
    }

    private func attach(_ webView: WKWebView) {
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
    }

    @objc private func openCatalog() {
        if let navigation = navigationController, navigation.viewControllers.first !== self {
            navigation.popToRootViewController(animated: true)
            if let root = navigationController?.viewControllers
                .first as? GameViewController
            {
                root.openCatalog()
            }
            return
        }
        retryURL = URL(string: "https://yandex.ru/games/")!
        retry()
    }

    @objc private func retry() {
        errorPanel?.removeFromSuperview()
        errorPanel = nil
        webView?.isHidden = false
        view.backgroundColor = webView?.underPageBackgroundColor ?? .systemBackground
        if let webView = webView {
            webView.load(URLRequest(url: retryURL))
        } else {
            prepareAndLoad(retryURL)
        }
    }

    private func showError(_ message: String) {
        spinner.stopAnimating()
        view.backgroundColor = .systemBackground
        webView?.isHidden = true
        errorPanel?.removeFromSuperview()
        let label = UILabel()
        label.text = message
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        let retry = UIButton(type: .system)
        retry.setTitle("Попробовать снова", for: .normal)
        retry.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        retry.titleLabel?.adjustsFontForContentSizeCategory = true
        retry.addTarget(self, action: #selector(self.retry), for: .touchUpInside)
        retry.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        let catalog = UIButton(type: .system)
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
            showError("Не удалось открыть страницу. Проверь подключение и попробуй ещё раз.")
        }
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        if (error as NSError)
            .code != NSURLErrorCancelled
        {
            showError("Игра не загрузилась. Попробуй ещё раз.")
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
        let allowed = mainWindow ? GameNavigationPolicy.allows(url) :
            GameNavigationPolicy.allowsFrame(url, source: action.sourceFrame.request.url)
        if allowed {
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
        alert.addTextField { $0.text = defaultText }
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
