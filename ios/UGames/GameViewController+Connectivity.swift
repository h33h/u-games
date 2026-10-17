import UIKit
import WebKit

extension GameViewController {
    func observeConnectionAndLifecycle() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: OfflineConnectivity.changed,
            object: connectivity,
            queue: .main
        ) { [weak self] _ in
            self?.connectionDidChange()
        })
        observers.append(center.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if let view = self?
                .webView
            {
                OfflineGameReportReceiver.shared.captureProgress(in: view) {}
            }
        })
        observers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.offlineStore.cancelDownloads()
        })
        observers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.connectionDidChange()
        })
    }

    func connectionDidChange() {
        guard isViewLoaded else { return }
        if connectivity.status == .offline, offlineGame == nil, !isOfflineCatalog {
            offlineStore.cancelDownloads()
            let target = webView
                .flatMap { OfflineGameReportReceiver.shared.report(for: $0)?.url } ?? retryURL
            openWithoutNetwork(target)
        } else if connectivity.status != .offline, offlineGame != nil || isOfflineCatalog {
            let game = offlineGame
            switchContext(
                to: game?.url ?? OfflineCatalog.onlineURL,
                game: nil,
                catalog: false,
                restore: game
            )
        }
    }

    func openWithoutNetwork(_ target: URL) {
        guard connectivity.status == .offline else { return }
        if let game = offlineStore.game(matching: target) {
            offlineStore.touch(game.id)
            if isOfflineCatalog, let navigation = navigationController {
                let controller = GameViewController(
                    offlineGame: game,
                    offlineStore: offlineStore,
                    connectivity: connectivity
                )
                navigation.pushViewController(controller, animated: true)
                return
            }
            switchContext(to: game.offlineURL, game: game, catalog: false)
        } else {
            switchContext(to: OfflineCatalog.url, game: nil, catalog: true)
        }
    }

    func switchContext(
        to url: URL,
        game: SavedOfflineGame?,
        catalog: Bool,
        restore: SavedOfflineGame? = nil
    ) {
        contextGeneration += 1
        let generation = contextGeneration
        let finish: () -> Void = { [weak self] in
            guard let self = self, self.contextGeneration == generation else { return }
            self.offlineGame = game
            self.isOfflineCatalog = catalog
            self.retryURL = url
            self.errorPanel?.removeFromSuperview()
            self.errorPanel = nil
            let latest = restore.flatMap { try? self.offlineStore.game(id: $0.id) } ?? restore
            self.prepareAndLoad(url, restoringProgressFrom: latest)
        }
        if let view = webView, offlineGame != nil {
            view.stopLoading()
            OfflineGameReportReceiver.shared.captureProgress(in: view, completion: finish)
        } else {
            webView?.stopLoading()
            finish()
        }
    }
}
