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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button("Copy P2P Code") {
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.server.irohNodeId ?? "", forType: .string)
                    #else
                    UIPasteboard.general.string = model.server.irohNodeId
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
                if !model.server.friends.isEmpty {
                    Section("Peers") {
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
