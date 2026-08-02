import Foundation
import WebKit

final class PatchworkSchemeHandler: NSObject, WKURLSchemeHandler {
    weak var model: AppModel?
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask)
        tasks[id] = Task { @MainActor in
            do {
                let (data, response) = try await self.respond(to: urlSchemeTask.request)
                guard self.tasks[id] != nil else { return }
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } catch {
                guard self.tasks[id] != nil else { return }
                urlSchemeTask.didFailWithError(error)
            }
            self.tasks[id] = nil
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask)
        tasks[id]?.cancel()
        tasks[id] = nil
    }

    private func respond(to request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url else { throw URLError(.badURL) }
        let path = url.path.isEmpty ? "" : String(url.path.dropFirst())
        let firstSegment = path.components(separatedBy: "/").first ?? ""
        if firstSegment == "__account" {
            return try handleAccountRoute(url: url)
        }
        if firstSegment.removingPercentEncoding?.hasPrefix("automerge:") == true {
            return try await resolveDocURL(path: path, url: url)
        }
        return try await serveBundleFile(path: path, url: url)
    }

    private func resolveDocURL(path: String, url: URL) async throws -> (Data, URLResponse) {
        guard let webView = model?.webView else { throw URLError(.cannotConnectToHost) }
        let result = try await webView.callAsyncJavaScript(
            "return await window.__patchworkResolve(path)",
            arguments: ["path": path],
            contentWorld: .page
        ) as? [String: Any]
        guard let result,
              let status = result["status"] as? Int,
              let mimeType = result["mimeType"] as? String,
              let base64 = result["base64"] as? String,
              let data = Data(base64Encoded: base64) else {
            throw URLError(.cannotParseResponse)
        }
        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": mimeType, "Content-Length": "\(data.count)"]
        )!
        return (data, response)
    }

    private func handleAccountRoute(url: URL) throws -> (Data, URLResponse) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let respond = { (status: Int, body: String) -> (Data, URLResponse) in
            let data = Data(body.utf8)
            let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/plain", "Content-Length": "\(data.count)"]
            )!
            return (data, response)
        }
        guard url.path.contains("__account/set") else {
            return respond(404, "unknown account route")
        }
        guard let accountUrl = components?.queryItems?.first(where: { $0.name == "url" })?.value,
              accountUrl.hasPrefix("automerge:") else {
            return respond(400, "url parameter must be an automerge: url")
        }
        Keychain.write("accountUrl", accountUrl)
        return respond(200, "ok")
    }

    // File reads happen off the main actor so module fetches don't serialize
    // through the UI thread; the config tag is read here first because it's
    // main-actor state.
    private func serveBundleFile(path: String, url: URL) async throws -> (Data, URLResponse) {
        let relative = path.isEmpty ? "index.html" : path
        let config = relative == "index.html" ? model?.configScriptTag() : nil
        return try await Task.detached {
            guard let base = Bundle.main.url(forResource: "PatchworkWeb", withExtension: "bundle") else {
                throw URLError(.fileDoesNotExist)
            }
            let fileURL = base.appendingPathComponent(relative)
            guard fileURL.path.hasPrefix(base.path),
                  FileManager.default.fileExists(atPath: fileURL.path) else {
                throw URLError(.fileDoesNotExist)
            }
            var data = try Data(contentsOf: fileURL)
            if let config {
                data = Data(
                    String(decoding: data, as: UTF8.self)
                        .replacingOccurrences(of: "<!-- patchwork_CONFIG -->", with: config)
                        .utf8
                )
            }
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": Self.mimeType(for: fileURL.pathExtension),
                    "Content-Length": "\(data.count)",
                ]
            )!
            return (data, response)
        }.value
    }

    private nonisolated static func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "html": "text/html; charset=utf-8"
        case "js", "mjs": "text/javascript"
        case "css": "text/css"
        case "json", "map": "application/json"
        case "wasm": "application/wasm"
        case "svg": "image/svg+xml"
        case "png": "image/png"
        case "txt": "text/plain; charset=utf-8"
        default: "application/octet-stream"
        }
    }
}
