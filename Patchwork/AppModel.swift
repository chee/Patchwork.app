import PatchworkServerKit
import Foundation
import Observation
import WebKit

struct Datatype: Identifiable, Hashable {
    let id: String
    let name: String
}

@Observable
final class AppModel {
    static let shared = AppModel()

    let webView: WKWebView
    let server = ServerController()
    var lastError: String?
    var datatypes: [Datatype] = []

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
        // Pin only the root view (frame.ts mounts body > repo-provider >
        // patchwork-view) to the viewport; nested patchwork-views style themselves.
        var css = ".frame-warning-banner{display:none}"
            + "body>repo-provider>patchwork-view{position:fixed;inset:0;display:flow-root;overflow:hidden}"
        #if os(macOS)
        // Frameless window: clear the traffic lights with the sidebar toggle.
        css += ".frame__left-toggle{margin-left:72px}"
        #endif
        configuration.userContentController.addUserScript(WKUserScript(
            source: "const style=document.createElement('style');style.textContent='\(css)';document.head.appendChild(style);",
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        #if os(macOS)
        configuration.userContentController.add(WindowDragHandler(), name: "dragWindow")
        configuration.userContentController.addUserScript(WKUserScript(
            source: """
            addEventListener("mousedown", event => {
                if (event.button !== 0 || event.clientY > 28) return;
                const interactive = "button, a, input, textarea, select, [role=button], [contenteditable=true]";
                if (event.composedPath().some(n => n.matches?.(interactive))) return;
                webkit.messageHandlers.dragWindow.postMessage(null);
            }, { capture: true });
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        #endif
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

    // The datatype registry fills as modules load, some time after boot.
    func loadDatatypes() async {
        for _ in 0..<30 {
            if let result = try? await runJS("return window.Patchwork.listDatatypes();"),
               let items = result as? [[String: String]] {
                let loaded = items.compactMap { item in
                    item["id"].map { Datatype(id: $0, name: item["name"] ?? $0) }
                }
                if !loaded.isEmpty {
                    datatypes = loaded
                    return
                }
            }
            try? await Task.sleep(for: .seconds(1))
        }
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
                Task { await self.loadDatatypes() }
                return
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        lastError = "page never became ready"
        throw PatchworkIntentError.javaScript("page never became ready")
    }
}

#if os(macOS)
final class WindowDragHandler: NSObject, WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let window = message.webView?.window,
              let event = NSApp.currentEvent else { return }
        window.performDrag(with: event)
    }
}
#endif
