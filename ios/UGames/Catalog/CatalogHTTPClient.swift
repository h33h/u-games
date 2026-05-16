import Foundation

struct CatalogHTTPClient {
    let config: AppConfig

    func request(url: URL, accept: String, acceptLanguage: String? = nil, queryItems: [URLQueryItem] = []) -> URLRequest {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        var request = URLRequest(url: components.url!)
        request.setValue(config.http.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(acceptLanguage ?? config.http.acceptLanguage, forHTTPHeaderField: "Accept-Language")
        return request
    }

    func data(for request: URLRequest, attempts: Int = 3) async throws -> (Data, URLResponse) {
        let backoffMs: [UInt64] = [400, 1200]
        var lastError: Error = URLError(.unknown)
        for i in 0..<attempts {
            if i > 0 {
                let ms = backoffMs[min(i - 1, backoffMs.count - 1)]
                try? await Task.sleep(nanoseconds: ms * 1_000_000)
                if Task.isCancelled { throw CancellationError() }
            }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, NetworkErrorPolicy.isTransientStatus(http.statusCode) {
                    lastError = URLError(.badServerResponse)
                    continue
                }
                return (data, response)
            } catch is CancellationError {
                throw CancellationError()
            } catch let urlErr as URLError where NetworkErrorPolicy.isTransient(urlErr) {
                lastError = urlErr
                continue
            } catch {
                throw error
            }
        }
        throw lastError
    }
}
