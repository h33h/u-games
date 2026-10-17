import Foundation
import Network

enum OfflineConnectionStatus { case unknown, online, offline }

/// Unknown starts with the real network. HTTP/TLS/server errors never change this state.
final class OfflineConnectivity {
    static let shared = OfflineConnectivity()
    static let changed = Notification.Name("UGamesConnectivityChanged")
    private(set) var status: OfflineConnectionStatus
    private let monitor: NWPathMonitor?

    init(status: OfflineConnectionStatus = .unknown, monitoring: Bool = true) {
        self.status = status
        monitor = monitoring ? NWPathMonitor() : nil
        monitor?.pathUpdateHandler = { [weak self] path in
            let status: OfflineConnectionStatus = path.status == .satisfied ? .online :
                (path.status == .unsatisfied ? .offline : .unknown)
            DispatchQueue.main.async { self?.update(status) }
        }
        monitor?.start(queue: DispatchQueue(label: "dev.ugames.connectivity"))
    }

    deinit { monitor?.cancel() }

    func update(_ status: OfflineConnectionStatus) {
        guard self.status != status else { return }
        self.status = status
        NotificationCenter.default.post(name: Self.changed, object: self)
    }

    @discardableResult
    func noteConnectionFailure(_ error: Error) -> Bool {
        let error = error as NSError
        guard error.domain == NSURLErrorDomain,
              error.code == NSURLErrorNotConnectedToInternet else { return false }
        update(.offline)
        return true
    }
}
