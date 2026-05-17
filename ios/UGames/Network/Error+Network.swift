import Foundation

enum NetworkError: Error, Equatable {
    case httpStatus(statusCode: Int, bodySnippet: String)
}

extension Error {
    var isTransientNetworkError: Bool {
        if let networkError = self as? NetworkError {
            switch networkError {
            case .httpStatus(let statusCode, _):
                return [408, 429, 500, 502, 503, 504].contains(statusCode)
            }
        }
        guard let error = self as? URLError else { return false }
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
}
