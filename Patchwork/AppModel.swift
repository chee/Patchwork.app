import PatchworkServerKit
import Foundation
import Observation
import WebKit

@Observable
final class AppModel {
    static let shared = AppModel()

    let webView: WKWebView
    let server = ServerController()
    var lastError: String?

    private let schemeHandler: PatchworkSchemeHandler
    private var readyTask: Task<Void, Error>?
    #if os(macOS)
    private let remindersSync = RemindersSync()
    #endif

    private init() {
        UserDefaults.standard.set(true, forKey: "WebKitDeveloperExtras")
        let handler = PatchworkSchemeHandler()
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: "patchwork")
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isInspectable = true
        self.schemeHandler = handler
        self.webView = webView
        handler.model = self
        self.readyTask = Task { try await self.boot() }
    }

    /// Awaited by App Intents and views before touching the page's JS.
    func ready() async throws -> WKWebView {
        try await readyTask?.value
        return webView
    }

    func configScriptTag() -> String {
        var config: [String: Any] = [
            "publicEndpoint": "wss://subduction.sync.inkandswitch.com",
            "signerSeedHex": Self.signerSeedHex(),
        ]
        if let accountUrl = Keychain.read("accountUrl") {
            config["accountUrl"] = accountUrl
        }
        if let port = server.port {
            config["localWsPort"] = Int(port)
        }
        let json = (try? JSONSerialization.data(withJSONObject: config)).map {
            String(decoding: $0, as: UTF8.self)
        } ?? "{}"
        return "<script>window.__patchwork_CONFIG = \(json);</script>"
    }

    private static func signerSeedHex() -> String {
        let key = "patchwork.signerSeedHex"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: key)
        return hex
    }

    private func boot() async throws {
        // Server first: its port goes into the config injected with index.html.
        await server.start()
        webView.load(URLRequest(url: URL(string: "patchwork://app/index.html")!))
        // Poll until the page's boot promise resolves; early calls run against
        // a not-yet-loaded page and just come back false or throw.
        for _ in 0..<600 {
            let ready = try? await webView.callAsyncJavaScript(
                "return typeof window.patchworkReady !== 'undefined' ? (await window.patchworkReady, true) : false",
                contentWorld: .page
            ) as? Bool
            if ready == true {
                #if os(macOS)
                Task { await self.remindersSync.start() }
                #endif
                return
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        lastError = "page never became ready"
        throw PatchworkIntentError.javaScript("page never became ready")
    }
}
