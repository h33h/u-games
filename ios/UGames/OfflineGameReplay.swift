import Foundation
import WebKit

enum OfflineResourceRewriter {
    static func isText(_ mime: String) -> Bool {
        mime.hasPrefix("text/") || [
            "application/javascript",
            "application/x-javascript",
            "application/ecmascript",
            "application/json",
            "application/manifest+json",
            "application/xhtml+xml",
            "image/svg+xml",
        ].contains(mime) || mime.hasSuffix("+json")
    }

    static func rewrite(_ data: Data, mimeType: String, textEncoding: String?) throws -> Data {
        guard isText(mimeType) else { return data }
        let encoding: String.Encoding
        switch textEncoding?.lowercased() {
        case "iso-8859-1", "latin1": encoding = .isoLatin1
        case "windows-1251": encoding = .windowsCP1251
        case "windows-1252": encoding = .windowsCP1252
        case "utf-16": encoding = .utf16
        default: encoding = .utf8
        }
        guard var text = String(data: data, encoding: encoding)
        else { throw OfflineGameError.invalidResponse }
        text = text.replacingOccurrences(of: "https://", with: OfflineGameStore.scheme + "://")
        text = text.replacingOccurrences(
            of: "https:\\/\\/",
            with: OfflineGameStore.scheme + ":\\/\\/"
        )
        if ["text/html", "application/xhtml+xml"].contains(mimeType) {
            text = removingIntegrityAttributes(from: text)
            let pattern = "<meta\\b(?=[^>]*http-equiv\\s*=\\s*(?:\"Content-Security-Policy\"|'Content-Security-Policy'|Content-Security-Policy)(?:\\s|/?>))[^>]*>"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                text = regex.stringByReplacingMatches(
                    in: text,
                    range: NSRange(text.startIndex..., in: text),
                    withTemplate: ""
                )
            }
            // Saved game documents can run local code, but cannot contact any network origin.
            let localPolicy = "default-src ugames-offline: data: blob: 'unsafe-inline' 'unsafe-eval'; connect-src ugames-offline: data: blob:; object-src 'none'; form-action 'none'; base-uri ugames-offline:;"
            let meta = "<meta http-equiv=\"Content-Security-Policy\" content=\"" + localPolicy + "\">"
            let head = text.range(
                of: "<head\\b[^>]*>",
                options: [.regularExpression, .caseInsensitive]
            )
            let doctype = text.range(
                of: "^\\s*<!doctype\\b[^>]*>",
                options: [.regularExpression, .caseInsensitive]
            )
            text.insert(
                contentsOf: meta,
                at: head?.upperBound ?? doctype?.upperBound ?? text.startIndex
            )
        }
        return Data(text.utf8)
    }

    private static func removingIntegrityAttributes(from text: String) -> String {
        // Rewriting HTTPS sources changes resource bytes; original SRI hashes no longer match.
        guard let tags = try? NSRegularExpression(
            pattern: "<(?:script|link)\\b(?:[^>\"']|\"[^\"]*\"|'[^']*')*>",
            options: .caseInsensitive
        ),
            let attributes =
            try? NSRegularExpression(
                pattern: "\\s+([A-Za-z_:][-A-Za-z0-9_:.]*)(?:\\s*=\\s*(?:\"[^\"]*\"|'[^']*'|[^\\s>]+))?"
            )
        else { return text }
        let result = NSMutableString(string: text)
        for tagMatch in tags.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .reversed()
        {
            let tag = (text as NSString).substring(with: tagMatch.range)
            let changed = NSMutableString(string: tag)
            for attribute in attributes.matches(in: tag, range: NSRange(tag.startIndex..., in: tag))
                .reversed()
                where (tag as NSString).substring(with: attribute.range(at: 1))
                .lowercased() == "integrity"
            {
                changed.deleteCharacters(in: attribute.range)
            }
            result.replaceCharacters(in: tagMatch.range, with: changed as String)
        }
        return result as String
    }
}

enum OfflineNavigationPolicy {
    static func allows(_ url: URL, in game: SavedOfflineGame, isMainFrame: Bool) -> Bool {
        if !isMainFrame,
           ["about:blank", "about:srcdoc"].contains(url.absoluteString)
        {
            return true
        }
        guard url.scheme == OfflineGameStore.scheme, url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              url.host?.lowercased() == game.url.host?.lowercased(),
              var original = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return false }
        original.scheme = "https"
        guard let originalURL = original.url,
              let resource = game
              .resources[OfflineResourcePolicy.canonical(originalURL).absoluteString]
        else { return false }
        return ["text/html", "application/xhtml+xml"].contains(resource.mimeType)
    }
}

final class OfflineGameSchemeHandler: NSObject, WKURLSchemeHandler {
    let game: SavedOfflineGame
    private let store: OfflineGameStore
    private let connectivity: OfflineConnectivity
    private let queue = DispatchQueue(label: "dev.ugames.offline-read", qos: .userInitiated)
    /// WebKit calls start/stop on the main thread. Delivery also runs there, so a stopped task
    /// never receives a late didReceive/didFinish callback (WebKit treats that as an exception).
    private var active = Set<ObjectIdentifier>()
    private var ownsPin = true

    init(
        game: SavedOfflineGame,
        store: OfflineGameStore,
        connectivity: OfflineConnectivity = .shared
    ) throws {
        self.game = try store.pinnedGame(id: game.id)
        self.store = store
        self.connectivity = connectivity
    }

    deinit {
        if ownsPin {
            store.unpin(game.id)
        }
    }

    func finishReplay() {
        guard ownsPin else { return }
        ownsPin = false
        active.removeAll()
        store.unpin(game.id)
    }

    func webView(_ view: WKWebView, start task: WKURLSchemeTask) {
        guard connectivity.status == .offline else { task.didFailWithError(URLError(.cancelled))
            return
        }
        let id = ObjectIdentifier(task)
        active.insert(id)
        queue.async {
            let result: Result<OfflineResourceResponse, Error> = Result {
                guard let url = task.request.url,
                      ["GET", "HEAD"].contains(task.request.httpMethod ?? "GET")
                else { throw OfflineGameError.missingResource }
                return try self.store.response(for: url, in: self.game)
            }
            DispatchQueue.main.async {
                guard self.active.remove(id) != nil else { return }
                guard self.connectivity.status == .offline
                else { task.didFailWithError(URLError(.cancelled))
                    return
                }
                switch result {
                case let .success(resource):
                    var statusCode = 200
                    var data = resource.data
                    var headers = [
                        "Content-Type": resource
                            .mimeType + (resource.textEncoding.map { "; charset=" + $0 } ?? ""),
                        "Access-Control-Allow-Origin": "*",
                        "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
                        "Accept-Ranges": "bytes",
                        "Cache-Control": "no-store",
                    ]
                    if let value = task.request.value(forHTTPHeaderField: "Range") {
                        if let range = Self.byteRange(value, count: data.count) {
                            headers["Content-Range"] = "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(data.count)"
                            data = data.subdata(in: range)
                            statusCode = 206
                        } else {
                            headers["Content-Range"] = "bytes */\(data.count)"
                            data = Data()
                            statusCode = 416
                        }
                    }
                    headers["Content-Length"] = String(data.count)
                    guard let url = task.request.url,
                          let response = HTTPURLResponse(
                              url: url,
                              statusCode: statusCode,
                              httpVersion: "HTTP/1.1",
                              headerFields: headers
                          )
                    else { task.didFailWithError(OfflineGameError.invalidResponse)
                        return
                    }
                    task.didReceive(response)
                    if task.request.httpMethod != "HEAD" {
                        task.didReceive(data)
                    }
                    task.didFinish()
                case let .failure(error): self.failedRead(task, in: view, error: error)
                }
            }
        }
    }

    private func failedRead(_ task: WKURLSchemeTask, in view: WKWebView, error: Error) {
        if ["GET", "HEAD"].contains(task.request.httpMethod ?? "GET"), contains(task.request.url) {
            task.didFailWithError(URLError(.cancelled))
            (view.navigationDelegate as? GameViewController)?.offlineReplayFailed(game, in: view)
        } else {
            task.didFailWithError(error)
        }
    }

    private func contains(_ url: URL?) -> Bool {
        guard let url = url, url.scheme == OfflineGameStore.scheme,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return false }
        components.scheme = "https"
        guard let original = components.url else { return false }
        return game.resources[OfflineResourcePolicy.canonical(original).absoluteString] != nil
    }

    func webView(_: WKWebView, stop task: WKURLSchemeTask) {
        active.remove(ObjectIdentifier(task))
    }

    private static func byteRange(_ value: String, count: Int) -> Range<Int>? {
        guard count > 0, value.hasPrefix("bytes=") else { return nil }
        let parts = value.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        if parts[0].isEmpty {
            guard let suffix = Int(parts[1]), suffix > 0 else { return nil }
            return max(0, count - suffix) ..< count
        }
        guard let start = Int(parts[0]), start >= 0, start < count else { return nil }
        if parts[1].isEmpty {
            return start ..< count
        }
        guard let end = Int(parts[1]), end >= start else { return nil }
        return start ..< (min(count - 1, end) + 1)
    }
}
