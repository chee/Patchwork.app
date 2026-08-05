//
//  ContentView.swift
//  Patchwork
//
//  Created by chee on 2026-07-31.
//

import PatchworkServerKit
import SwiftUI
import WebKit

#if os(macOS)
struct PatchworkWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { AppModel.shared.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// Insets the traffic lights so they line up with the sidebar toggle in the
/// frameless window. AppKit resets button frames on resize, so re-apply.
struct WindowChrome: NSViewRepresentable {
    static let inset = CGPoint(x: 7, y: -7)

    final class Coordinator {
        var observer: (any NSObjectProtocol)?
        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let coordinator = context.coordinator
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            Self.adjust(window)
            coordinator.observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification, object: window, queue: .main
            ) { _ in
                MainActor.assumeIsolated { Self.adjust(window) }
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Self.adjust(nsView.window)
    }

    static func adjust(_ window: NSWindow?) {
        guard let window else { return }
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(type) else { continue }
            var origin = button.frame.origin
            origin.x += Self.inset.x
            origin.y += Self.inset.y
            button.setFrameOrigin(origin)
        }
    }
}
#else
struct PatchworkWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { AppModel.shared.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif

struct PeerSheet: View {
    @State private var model = AppModel.shared
    @State private var newEndpoint = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Sync") {
                    ForEach(model.subductionEndpoints, id: \.self) { endpoint in
                        HStack {
                            Text(endpoint)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("Remove") {
                                model.removeSubductionEndpoint(endpoint)
                            }
                        }
                    }
                    HStack {
                        TextField("ws:// or wss:// endpoint", text: $newEndpoint)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            #endif
                        Button("Add") {
                            do {
                                try model.addSubductionEndpoint(newEndpoint)
                                newEndpoint = ""
                            } catch {
                                model.lastError = "add endpoint: \(error.localizedDescription)"
                            }
                        }
                        .disabled(newEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let url = model.server.websocketURL {
                        Text("Local server: \(url.absoluteString)")
                    } else {
                        Text("Local server unavailable")
                    }
                }

                Section("Peer to Peer") {
                    if let nodeId = model.server.irohNodeId {
                        Button("Copy P2P Code") {
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(nodeId, forType: .string)
                            #else
                            UIPasteboard.general.string = nodeId
                            #endif
                        }
                        Button("Add Peer from Clipboard") {
                            #if os(macOS)
                            guard let nodeId = NSPasteboard.general.string(forType: .string)?
                                .trimmingCharacters(in: .whitespacesAndNewlines), !nodeId.isEmpty else { return }
                            #else
                            guard let nodeId = UIPasteboard.general.string?
                                .trimmingCharacters(in: .whitespacesAndNewlines), !nodeId.isEmpty else { return }
                            #endif
                            do {
                                try model.server.addFriend(nodeId)
                            } catch {
                                model.lastError = "add peer: \(error.localizedDescription)"
                            }
                        }
                    } else {
                        Text("Direct P2P unavailable; syncing can still use configured servers and local loopback.")
                    }
                    if !model.server.friends.isEmpty {
                        ForEach(model.server.friends, id: \.self) { friend in
                            Text("\(friend.prefix(10))…")
                        }
                    }
                }
            }
            .navigationTitle("Peer to Peer")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct ContentView: View {
    @State private var model = AppModel.shared

    var body: some View {
        VStack(spacing: 0) {
            PatchworkWebView()
                .ignoresSafeArea()
                #if os(macOS)
                .background(WindowChrome())
                #endif
            if let error = model.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(4)
            }
        }
        .sheet(isPresented: $model.showingAppleTray) {
            PeerSheet()
        }
    }
}

#Preview {
    ContentView()
}
