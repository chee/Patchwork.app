//
//  ContentView.swift
//  Patchwork
//
//  Created by chee on 2026-07-31.
//

import SwiftUI
import WebKit

#if os(macOS)
struct PatchworkWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { AppModel.shared.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#else
struct PatchworkWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { AppModel.shared.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif

struct ContentView: View {
    @State private var model = AppModel.shared

    var body: some View {
        VStack(spacing: 0) {
            PatchworkWebView()
            if let error = model.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(4)
            }
        }
    }
}

#Preview {
    ContentView()
}
