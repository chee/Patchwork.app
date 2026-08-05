import PatchworkServerKit
import Foundation
import Observation
import Security
import WebKit

struct Datatype: Identifiable, Hashable {
    let id: String
    let name: String
}

@Observable
@MainActor
final class AppModel {
    static let shared = AppModel()

    nonisolated static let defaultSubductionEndpoints = ["wss://subduction.sync.inkandswitch.com"]
    private nonisolated static let subductionEndpointsKey = "patchwork.subductionEndpoints"
    private nonisolated static let signerSeedKey = "patchwork.signerSeedHex"

    let webView: WKWebView
    let server = ServerController()
    var lastError: String?
    var datatypes: [Datatype] = []
    var showingAppleTray = false
    var subductionEndpoints: [String]

    private let schemeHandler: PatchworkSchemeHandler
    private var readyTask: Task<Void, Error>?
    private var pageReadyContinuation: CheckedContinuation<Void, Error>?
    #if os(macOS)
    private let remindersSync = RemindersSync()
    #endif

    private init() {
        self.subductionEndpoints = Self.loadSubductionEndpoints()
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
        // Frameless window: clear the traffic lights with the sidebar toggle,
        // and when the sidebar is collapsed pad the topbar past lights + toggle.
        css += ".frame__left-toggle{margin-left:72px}"
            + ".frame__topbar--left-collapsed{padding-left:calc(72px + var(--threepane-space-2xl))}"
        #endif
        configuration.userContentController.addUserScript(WKUserScript(
            source: "const style=document.createElement('style');style.textContent='\(css)';document.head.appendChild(style);",
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        configuration.userContentController.add(AppleTrayHandler(), name: "appleTray")
        configuration.userContentController.add(PatchworkReadyHandler(), name: "patchworkReady")
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
            "publicEndpoint": subductionEndpoints.first ?? Self.defaultSubductionEndpoints[0],
            "subductionEndpoints": subductionEndpoints,
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

    func addSubductionEndpoint(_ endpoint: String) throws {
        let normalized = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidSubductionEndpoint(normalized) else {
            throw PatchworkIntentError.javaScript("endpoint must be a ws:// or wss:// URL")
        }
        guard !subductionEndpoints.contains(normalized) else { return }
        subductionEndpoints.append(normalized)
        Self.saveSubductionEndpoints(subductionEndpoints)
    }

    func removeSubductionEndpoint(_ endpoint: String) {
        subductionEndpoints.removeAll { $0 == endpoint }
        if subductionEndpoints.isEmpty {
            subductionEndpoints = Self.defaultSubductionEndpoints
        }
        Self.saveSubductionEndpoints(subductionEndpoints)
    }

    private nonisolated static func loadSubductionEndpoints() -> [String] {
        let stored = UserDefaults.standard.stringArray(forKey: subductionEndpointsKey) ?? []
        let valid = stored.filter(isValidSubductionEndpoint)
        return valid.isEmpty ? defaultSubductionEndpoints : valid
    }

    private nonisolated static func saveSubductionEndpoints(_ endpoints: [String]) {
        UserDefaults.standard.set(endpoints, forKey: subductionEndpointsKey)
    }

    nonisolated static func isValidSubductionEndpoint(_ endpoint: String) -> Bool {
        guard let url = URL(string: endpoint),
              let scheme = url.scheme?.lowercased(),
              ["ws", "wss"].contains(scheme),
              url.host != nil else {
            return false
        }
        return true
    }

    private nonisolated static func signerSeedHex() -> String {
        if let existing = Keychain.read(signerSeedKey) {
            return existing
        }
        if let migrated = UserDefaults.standard.string(forKey: signerSeedKey) {
            try? Keychain.write(signerSeedKey, migrated)
            UserDefaults.standard.removeObject(forKey: signerSeedKey)
            return migrated
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
                + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        try? Keychain.write(signerSeedKey, hex)
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
        try await withCheckedThrowingContinuation { continuation in
            pageReadyContinuation = continuation
            webView.load(URLRequest(url: URL(string: "patchwork://app/index.html")!))
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(120))
                resolvePageReady(.failure(PatchworkIntentError.javaScript("page never became ready")))
            }
        }
        #if os(macOS)
        Task { await self.remindersSync.start() }
        #endif
        Task { await self.loadDatatypes() }
    }

    func webPageReady(error: String?) {
        if let error {
            resolvePageReady(.failure(PatchworkIntentError.javaScript(error)))
        } else {
            resolvePageReady(.success(()))
        }
    }

    private func resolvePageReady(_ result: Result<Void, Error>) {
        guard let continuation = pageReadyContinuation else { return }
        pageReadyContinuation = nil
        if case .failure(let error) = result {
            lastError = error.localizedDescription
        }
        continuation.resume(with: result)
    }
}

final class AppleTrayHandler: NSObject, WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        Task { @MainActor in
            AppModel.shared.showingAppleTray = true
        }
    }
}

final class PatchworkReadyHandler: NSObject, WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        let error = (message.body as? [String: Any])?["error"] as? String
        Task { @MainActor in
            AppModel.shared.webPageReady(error: error)
        }
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
