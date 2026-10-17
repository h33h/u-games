@testable import UGames
import WebKit
import XCTest

@MainActor
class WebViewTestCase: XCTestCase {
    /// A cold WebContent process can take tens of seconds to start on hosted simulators.
    private let webViewTimeout: TimeInterval = 60

    private struct WaitFailure: Error, CustomStringConvertible {
        let description: String
    }

    func makeView(configuration: WKWebViewConfiguration? = nil) throws -> WKWebView {
        let ready = XCTestExpectation(description: "Protected WebView is ready")
        var result: Result<WKWebView, Error>?
        ProtectedWebViewFactory.make(configuration: configuration) { value in
            result = value
            ready.fulfill()
        }
        try waitForWebView(ready)
        return try XCTUnwrap(result).get()
    }

    func waitUntil(_ description: String, condition: @escaping () -> Bool) throws {
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in condition() },
            object: nil
        )
        ready.expectationDescription = description
        try waitForWebView(ready)
    }

    func waitForJavaScript(_ expression: String, in webView: WKWebView) throws {
        var matched = false
        var evaluating = false
        var lastError: Error?
        do {
            try waitUntil("JavaScript condition: \(expression)") {
                if matched {
                    return true
                }
                if !evaluating {
                    evaluating = true
                    webView.evaluateJavaScript(expression) { value, error in
                        lastError = error
                        matched = error == nil && value as? Bool == true
                        evaluating = false
                    }
                }
                return false
            }
        } catch {
            throw WaitFailure(
                description: "\(error); last JavaScript error: \(String(describing: lastError))"
            )
        }
    }

    func loadHTMLFixture(_ html: String, baseURL: URL?, in webView: WKWebView) throws {
        let marker = "ugames-fixture-" + UUID().uuidString
        webView.loadHTMLString("<meta id='\(marker)'>" + html, baseURL: baseURL)
        // A previous document can also be complete. Wait for this specific fixture.
        try waitForJavaScript(
            "document.readyState==='complete' && document.getElementById('\(marker)')!==null",
            in: webView
        )
    }

    @discardableResult
    func evaluateJavaScript(_ script: String, in webView: WKWebView) throws -> Any? {
        let evaluated = XCTestExpectation(description: "JavaScript completed: \(script)")
        var result: Result<Any?, Error>?
        webView.evaluateJavaScript(script) { value, error in
            if let error = error {
                result = .failure(error)
            } else {
                result = .success(value)
            }
            evaluated.fulfill()
        }
        try waitForWebView(evaluated)
        return try XCTUnwrap(result).get()
    }

    func waitForWebView(_ expectation: XCTestExpectation) throws {
        guard XCTWaiter.wait(for: [expectation], timeout: webViewTimeout) == .completed else {
            throw WaitFailure(
                description: "Timed out after \(webViewTimeout)s: \(expectation.expectationDescription)"
            )
        }
    }
}
