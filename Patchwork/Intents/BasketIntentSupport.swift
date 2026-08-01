import AppIntents
import Foundation
import WebKit

enum PatchworkIntentError: Error, CustomLocalizedStringResourceConvertible {
    case javaScript(String)
    case unexpectedResult

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .javaScript(let message): "JavaScript error: \(message)"
        case .unexpectedResult: "The page returned an unexpected result"
        }
    }
}

extension AppModel {
    /// Runs a JS function body in the app's page with the repo booted,
    /// surfacing JS exceptions as readable intent errors.
    func runJS(_ functionBody: String, arguments: [String: Any] = [:]) async throws -> Any? {
        let webView = try await ready()
        do {
            return try await webView.callAsyncJavaScript(
                functionBody,
                arguments: arguments,
                contentWorld: .page
            )
        } catch let error as NSError where error.domain == WKError.errorDomain {
            let message = (error.userInfo["WKJavaScriptExceptionMessage"] as? String)
                ?? error.localizedDescription
            throw PatchworkIntentError.javaScript(message)
        }
    }
}
