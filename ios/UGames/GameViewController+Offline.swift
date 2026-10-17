import UIKit
import WebKit

extension GameViewController {
    func configureMenu() {
        menuButton.setImage(
            UIImage(
                systemName: "ellipsis.circle.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 25)
            ),
            for: .normal
        )
        menuButton.tintColor = .label
        menuButton.backgroundColor = .secondarySystemBackground.withAlphaComponent(0.92)
        menuButton.layer.cornerRadius = 22
        menuButton.accessibilityLabel = "Меню игр"
        menuButton.accessibilityIdentifier = "ugames.menu"
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(menuButton)
        NSLayoutConstraint.activate([
            menuButton.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: 8
            ),
            menuButton.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -8
            ),
            menuButton.widthAnchor.constraint(equalToConstant: 44),
            menuButton.heightAnchor.constraint(equalToConstant: 44),
        ])
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reportUpdated(_:)),
            name: OfflineGameReportReceiver.updated,
            object: nil
        )
        updateMenu()
    }

    @objc private func reportUpdated(_ notification: Notification) {
        guard let changed = notification.object as? WKWebView, changed === webView else { return }
        updateMenu()
    }

    func updateMenu() {
        let report = webView.flatMap { OfflineGameReportReceiver.shared.report(for: $0) }
        let save = UIAction(
            title: saving ? "Сохраняем игру…" : "Сохранить для оффлайна",
            image: UIImage(systemName: "arrow.down.to.line"),
            attributes: saving || offlineGame != nil || report?.ready != true ? .disabled : []
        ) { [weak self] _ in self?.saveCurrentGame() }
        let library = UIAction(
            title: "Сохранённые игры",
            image: UIImage(systemName: "square.stack")
        ) { [weak self] _ in self?.openLibrary() }
        let catalog = UIAction(
            title: "Каталог",
            image: UIImage(systemName: "square.grid.2x2")
        ) { [weak self] _ in self?.openCatalog() }
        menuButton.menu = UIMenu(children: [save, library, catalog])
    }

    private func saveCurrentGame() {
        guard !saving, offlineGame == nil, let view = webView else { return }
        view.evaluateJavaScript("window.__UGamesOfflineCapture && window.__UGamesOfflineCapture()")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak view] in
            guard let self = self, let view = view, self.webView === view else { return }
            guard let report = OfflineGameReportReceiver.shared.report(for: view),
                  report.ready
            else {
                self.showNotice(
                    title: "Игра ещё загружается",
                    message: "Дождись начала игры и попробуй сохранить её снова."
                )
                return
            }
            self.saving = true
            self.updateMenu()
            let activity = UIActivityIndicatorView(style: .medium)
            activity.startAnimating()
            self.menuButton.setImage(nil, for: .normal)
            activity.translatesAutoresizingMaskIntoConstraints = false
            self.menuButton.addSubview(activity)
            NSLayoutConstraint.activate([
                activity.centerXAnchor.constraint(equalTo: self.menuButton.centerXAnchor),
                activity.centerYAnchor.constraint(equalTo: self.menuButton.centerYAnchor),
            ])
            self.offlineStore.save(report, progress: { [weak self] completed, total in
                self?.menuButton.accessibilityValue = "Сохранено файлов: \(completed) из \(total)"
            }, completion: { [weak self, weak activity] result in
                guard let self = self else { return }
                activity?.removeFromSuperview()
                self.menuButton.setImage(
                    UIImage(
                        systemName: "ellipsis.circle.fill",
                        withConfiguration: UIImage.SymbolConfiguration(pointSize: 25)
                    ),
                    for: .normal
                )
                self.saving = false
                self.menuButton.accessibilityValue = nil
                self.updateMenu()
                switch result {
                case let .success(game): self.showNotice(
                        title: "Игра сохранена",
                        message: "«\(game.title)» доступна в сохранённых играх без интернета. Новые уровни и сетевые функции могут потребовать подключения."
                    )
                case let .failure(error): self.showNotice(
                        title: "Игра не сохранена",
                        message: error.localizedDescription
                    )
                }
            })
        }
    }

    private func showNotice(title: String, message: String) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "ОК", style: .default))
        present(alert, animated: true)
    }

    private func openLibrary() {
        let library = OfflineLibraryViewController(store: offlineStore) { [weak self] game in
            guard let self = self else { return }
            let controller = GameViewController(offlineGame: game, offlineStore: self.offlineStore)
            self.navigationController?.pushViewController(controller, animated: true)
        }
        let navigation = UINavigationController(rootViewController: library)
        navigation.modalPresentationStyle = .pageSheet
        navigation.sheetPresentationController?.detents = [.medium(), .large()]
        navigation.sheetPresentationController?.prefersGrabberVisible = true
        present(navigation, animated: true)
    }
}
