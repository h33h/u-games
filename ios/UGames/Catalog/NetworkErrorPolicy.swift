import Foundation

enum NetworkErrorPolicy {
    static func isTransient(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet,
             .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .resourceUnavailable, .badServerResponse, .secureConnectionFailed,
             .cannotLoadFromNetwork:
            return true
        default:
            return false
        }
    }

    static func isTransientStatus(_ statusCode: Int) -> Bool {
        (500...599).contains(statusCode)
    }
}
