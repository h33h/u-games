import Foundation

struct NetworkService {
    let session: URLSession
    let decoder: JSONDecoder
    let cookieHeaderProvider: () -> String

    init(
        session: URLSession = .shared,
        decoder: JSONDecoder = NetworkService.makeDecoder(),
        cookieHeaderProvider: @escaping () -> String = { "" }
    ) {
        self.session = session
        self.decoder = decoder
        self.cookieHeaderProvider = cookieHeaderProvider
    }

    func execute<T: Request>(_ request: T) async throws -> T.DTO {
        try await execute(request, attempts: 1)
    }

    func execute<T: Request>(_ request: T, attempts: Int) async throws -> T.DTO {
        let urlRequest = makeRequest(from: request)
        let totalAttempts = max(1, attempts)
        var lastError: Error = URLError(.unknown)
        for attempt in 0..<totalAttempts {
            try await exponentialBackoff(beforeAttempt: attempt)
            do {
                let (data, response) = try await session.data(for: urlRequest)
                try validate(response: response, data: data)
                return try decoder.decode(T.DTO.self, from: data)
            } catch is CancellationError {
                throw CancellationError()
            } catch where error.isTransientNetworkError {
                lastError = error
                continue
            } catch {
                throw error
            }
        }
        throw lastError
    }

    private func makeRequest<T: Request>(from request: T) -> URLRequest {
        var urlRequest = URLRequest(url: request.url)
        switch request.method {
        case .get:
            urlRequest.httpMethod = "GET"
        case .post:
            urlRequest.httpMethod = "POST"
            urlRequest.setValue(request.contentType, forHTTPHeaderField: "Content-Type")
        }
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        if request.headers.keys.contains(where: { $0.caseInsensitiveCompare("Cookie") == .orderedSame }) == false {
            let cookieHeader = cookieHeaderProvider()
            if !cookieHeader.isEmpty {
                urlRequest.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            }
        }
        urlRequest.httpBody = request.body
        return urlRequest
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let snippet = String(decoding: data.prefix(512), as: UTF8.self)
            throw NetworkError.httpStatus(statusCode: http.statusCode, bodySnippet: snippet)
        }
    }

    private func exponentialBackoff(beforeAttempt attempt: Int) async throws {
        guard attempt > 0 else { return }
        let retryIndex = min(attempt - 1, 6)
        let delayMs = UInt64(400) * UInt64(1 << retryIndex)
        try await Task.sleep(nanoseconds: delayMs * 1_000_000)
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { codingPath in
            let raw = codingPath.last?.stringValue ?? ""
            return AnyCodingKey(stringValue: raw.normalizedJSONKey)
        }
        return decoder
    }
}
