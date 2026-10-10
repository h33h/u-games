import UIKit
import WebKit

final class GameViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private var webView: WKWebView?
    private var backgroundObservation: NSKeyValueObservation?
    private let preparedView: WKWebView?
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var errorPanel: UIStackView?
    private let menuButton = FloatingMenuButton()
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
        menuButton.addTarget(self, action: #selector(showMenu), for: .touchUpInside)
        view.addSubview(menuButton)
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
        menuButton.restorePosition()
        view.setNeedsLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        var area = view.safeAreaLayoutGuide.layoutFrame
        area.size.height = max(
            0,
            min(area.maxY, view.keyboardLayoutGuide.layoutFrame.minY) - area.minY
        )
        menuButton.place(in: area)
    }

    @objc private func showMenu() {
        let menu = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        menu.addAction(UIAlertAction(title: "Назад", style: .default) { [weak self] _ in
            self?.goBack()
        })
        menu.addAction(UIAlertAction(title: "Каталог", style: .default) { [weak self] _ in
            self?.openCatalog()
        })
        menu.addAction(UIAlertAction(title: "Обновить", style: .default) { [weak self] _ in
            self?.retry()
        })
        menu.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        menu.popoverPresentationController?.sourceView = menuButton
        menu.popoverPresentationController?.sourceRect = menuButton.bounds
        present(menu, animated: true)
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

    @objc private func goBack() {
        errorPanel?.removeFromSuperview()
        errorPanel = nil
        webView?.isHidden = false
        view.backgroundColor = webView?.underPageBackgroundColor ?? .systemBackground
        if let navigation = navigationController,
           navigation.viewControllers.first !== self
        {
            navigation.popViewController(animated: true)
        } else if webView?.canGoBack == true {
            webView?.goBack()
        } else {
            openCatalog()
        }
    }

    @objc private func openCatalog() {
        if navigationController?.viewControllers.first !== self {
            navigationController?.popToRootViewController(animated: true)
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
        let panel = UIStackView(arrangedSubviews: [label, retry])
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
        view.bringSubviewToFront(menuButton)
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
        _: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let scheme = action.request.url?.scheme
        if scheme == "https" || scheme == "http" || scheme == "about" {
            if action.targetFrame?.isMainFrame == true,
               let url = action.request.url, scheme == "https" || scheme == "http"
            {
                retryURL = url
            }
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            if action.targetFrame?
                .isMainFrame != false
            {
                showError("Эту ссылку нельзя открыть внутри приложения.")
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
        for _: WKNavigationAction,
        windowFeatures _: WKWindowFeatures
    ) -> WKWebView? {
        let child = ProtectedWebViewFactory.makePopup(configuration: configuration, parent: parent)
        let controller = GameViewController(preparedView: child)
        navigationController?.pushViewController(controller, animated: true)
        return child
    }

    func webViewDidClose(_: WKWebView) {
        navigationController?.popViewController(animated: true)
    }

    private func presentGameDialog(_ alert: UIAlertController) {
        // A running game can request a dialog while its navigation menu is open.
        if let menu = presentedViewController as? UIAlertController,
           menu.preferredStyle == .actionSheet
        {
            menu.dismiss(animated: false) { [weak self] in
                self?.present(alert, animated: true)
            }
        } else {
            present(alert, animated: true)
        }
    }

    func webView(
        _: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame _: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "ОК", style: .default) { _ in completionHandler() })
        presentGameDialog(alert)
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
        presentGameDialog(alert)
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
        presentGameDialog(alert)
    }
}
