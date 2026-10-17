import Foundation
import UniformTypeIdentifiers

final class OfflineDownloadCancellation {
    private let lock = NSLock()
    private var cancelled = false
    private var task: URLSessionTask?
    func check() throws {
        lock.lock()
        defer { lock.unlock() }
        if cancelled {
            throw URLError(.cancelled)
        }
    }

    func setTask(_ task: URLSessionTask) {
        lock.lock()
        self.task = task
        let stop = cancelled
        lock.unlock()
        if stop {
            task.cancel()
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = task
        lock.unlock()
        task?.cancel()
    }
}

final class OfflineResourceDownload: NSObject, URLSessionDataDelegate {
    private let output: FileHandle
    private let remainingBytes: Int64
    private let allows: (URL) -> Bool
    private let reserve: (Int64) throws -> Void
    private let completed = DispatchSemaphore(value: 0)
    private var bytes: Int64 = 0
    private var response: HTTPURLResponse?
    private var failure: Error?
    private var redirects = 0

    private init(
        destination: URL,
        remainingBytes: Int64,
        allows: @escaping (URL) -> Bool,
        reserve: @escaping (Int64) throws -> Void
    ) throws {
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        output = try FileHandle(forWritingTo: destination)
        self.remainingBytes = remainingBytes
        self.allows = allows
        self.reserve = reserve
    }

    static func fetch(
        _ url: URL,
        to destination: URL,
        configuration: URLSessionConfiguration,
        remainingBytes: Int64,
        allows: @escaping (URL) -> Bool,
        cancellation: OfflineDownloadCancellation,
        reserve: @escaping (Int64) throws -> Void
    ) throws -> SavedOfflineResource {
        guard remainingBytes >= 0 else { throw OfflineGameError.tooLarge }
        let operation = try OfflineResourceDownload(
            destination: destination,
            remainingBytes: remainingBytes,
            allows: allows, reserve: reserve
        )
        let session = URLSession(
            configuration: configuration,
            delegate: operation,
            delegateQueue: nil
        )
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpShouldHandleCookies = false
        let task = session.dataTask(with: request)
        cancellation.setTask(task)
        task.resume()
        operation.completed.wait()
        session.finishTasksAndInvalidate()
        try operation.output.close()
        if let error = operation.failure {
            throw error
        }
        guard let response = operation.response else { throw OfflineGameError.invalidResponse }
        let mime = response.mimeType ?? UTType(filenameExtension: url.pathExtension)?
            .preferredMIMEType ?? "application/octet-stream"
        return SavedOfflineResource(
            mimeType: mime.lowercased(),
            textEncoding: response.textEncodingName,
            bytes: operation.bytes
        )
    }

    func urlSession(
        _: URLSession,
        dataTask _: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200,
              let url = response.url, allows(url)
        else { failure = OfflineGameError.invalidResponse
            completionHandler(.cancel)
            return
        }
        guard response.expectedContentLength <= remainingBytes else {
            failure = OfflineGameError.tooLarge
            completionHandler(.cancel)
            return
        }
        self.response = response
        completionHandler(.allow)
    }

    func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard bytes + Int64(data.count) <= remainingBytes else {
            failure = OfflineGameError.tooLarge
            dataTask.cancel()
            return
        }
        do { try reserve(Int64(data.count))
            try output.write(contentsOf: data)
            bytes += Int64(data.count)
        } catch { failure = error
            dataTask.cancel()
        }
    }

    func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
        if failure == nil {
            failure = error
        }
        completed.signal()
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        redirects += 1
        guard redirects <= 8, let url = request.url, allows(url) else {
            failure = OfflineGameError.invalidResponse
            completionHandler(nil)
            return
        }
        var clean = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        clean.httpShouldHandleCookies = false
        completionHandler(clean)
    }

    func urlSession(
        _: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completionHandler(
            challenge.protectionSpace
                .authenticationMethod == NSURLAuthenticationMethodServerTrust ?
                .performDefaultHandling : .cancelAuthenticationChallenge,
            nil
        )
    }
}
