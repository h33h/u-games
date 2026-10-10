import UIKit
import WebKit

final class GameViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private var webView: WKWebView?
    private let preparedView: WKWebView?
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var errorPanel: UIStackView?
    private var lastURL = URL(string: "https://yandex.ru/games/")!
    private var isRoot: Bool { preparedView == nil }

    init(preparedView: WKWebView? = nil) {
        self.preparedView = preparedView
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use programmatic initialization") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "U Games"
        view.backgroundColor = .systemBackground
        if isRoot {
            let back = UIBarButtonItem(title: "Назад", style: .plain, target: self, action: #selector(goBack))
            navigationItem.leftBarButtonItem = back
        }
        let home = UIBarButtonItem(image: UIImage(systemName: "square.grid.2x2"), style: .plain, target: self, action: #selector(openCatalog))
        home.accessibilityLabel = "Каталог"
        let reload = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(retry))
        reload.accessibilityLabel = "Обновить"
        navigationItem.rightBarButtonItems = [reload, home]
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        if let preparedView = preparedView { attach(preparedView) }
        else { prepareAndLoad(lastURL) }
    }

    private func prepareAndLoad(_ url: URL) {
        spinner.startAnimating()
        ProtectedWebViewFactory.make { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let view):
                self.attach(view)
                view.load(URLRequest(url: url))
            case .failure:
                self.showError("Не удалось подготовить приложение. Попробуй перезапустить U Games.")
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
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        webView.scrollView.contentInsetAdjustmentBehavior = .never
    }
    @objc private func goBack() {
        errorPanel?.removeFromSuperview(); errorPanel = nil
        webView?.isHidden = false
        if webView?.canGoBack == true { webView?.goBack() }
        else { openCatalog() }
    }
    @objc private func openCatalog() {
        if navigationController?.viewControllers.first !== self {
            navigationController?.popToRootViewController(animated: true)
            if let root = navigationController?.viewControllers.first as? GameViewController { root.openCatalog() }
            return
        }
        lastURL = URL(string: "https://yandex.ru/games/")!
        retry()
    }
    @objc private func retry() {
        errorPanel?.removeFromSuperview(); errorPanel = nil
        webView?.isHidden = false
        if let webView = webView { webView.load(URLRequest(url: lastURL)) }
        else { prepareAndLoad(lastURL) }
    }
    private func showError(_ message: String) {
        spinner.stopAnimating()
        webView?.isHidden = true
        errorPanel?.removeFromSuperview()
        let label = UILabel()
        label.text = message; label.numberOfLines = 0; label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        let retry = UIButton(type: .system)
        retry.setTitle("Попробовать снова", for: .normal)
        retry.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        retry.titleLabel?.adjustsFontForContentSizeCategory = true
        retry.addTarget(self, action: #selector(self.retry), for: .touchUpInside)
        retry.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        let panel = UIStackView(arrangedSubviews: [label, retry])
        panel.axis = .vertical; panel.spacing = 16
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            panel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            panel.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor)
        ])
        errorPanel = panel
    }
    func showProtectionError() {
        showError("Эта игра пока не работает без рекламы. Выбери другую в каталоге.")
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        errorPanel?.removeFromSuperview(); errorPanel = nil
        webView.isHidden = false
        spinner.startAnimating()
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        spinner.stopAnimating()
        if let url = webView.url, url.scheme == "https" { lastURL = url }
        if isRoot { navigationItem.leftBarButtonItem?.isEnabled = webView.canGoBack }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { showError("Не удалось открыть страницу. Проверь подключение и попробуй ещё раз.") }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { showError("Игра не загрузилась. Попробуй ещё раз.") }
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let scheme = action.request.url?.scheme
        if scheme == "https" || scheme == "http" || scheme == "about" {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            if action.targetFrame?.isMainFrame != false { showError("Эту ссылку нельзя открыть внутри приложения.") }
        }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // Offer a reload; never replay an already completed reward from native state.
        showError("Игра закрылась. Можно открыть её снова.")
    }
    func webView(_ parent: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let child = ProtectedWebViewFactory.makePopup(configuration: configuration, parent: parent)
        let controller = GameViewController(preparedView: child)
        navigationController?.pushViewController(controller, animated: true)
        return child
    }
    func webViewDidClose(_ webView: WKWebView) { navigationController?.popViewController(animated: true) }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "ОК", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "ОК", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "ОК", style: .default) { _ in completionHandler(alert.textFields?.first?.text) })
        present(alert, animated: true)
    }
}
