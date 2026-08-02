#if os(macOS)
import AppKit
import PatchworkServerKit
import SwiftUI

struct MenuBarView: View {
    @State private var model = AppModel.shared

    var body: some View {
        Button("Open Patchwork") { activate() }
        Menu("Create New") {
            if model.datatypes.isEmpty {
                Text("Nothing registered yet")
            }
            ForEach(model.datatypes) { datatype in
                Button(datatype.name) { createNew(datatype) }
            }
        }
        Divider()
        Menu("Peer to Peer") {
            Button("Copy P2P Code") {
                guard let nodeId = model.server.irohNodeId else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(nodeId, forType: .string)
            }
            Button("Add Peer from Clipboard") {
                guard let nodeId = NSPasteboard.general.string(forType: .string)?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !nodeId.isEmpty else { return }
                do {
                    try model.server.addFriend(nodeId)
                } catch {
                    model.lastError = "add friend: \(error.localizedDescription)"
                }
            }
            if !model.server.friends.isEmpty {
                Divider()
                ForEach(model.server.friends, id: \.self) { friend in
                    Text("\(friend.prefix(10))…")
                }
            }
        }
        Divider()
        Button("Settings…") {
            activate()
            Task {
                _ = try? await model.runJS("window.__patchworkOpenSettings?.();")
            }
        }
        Button("Quit Patchwork") { NSApp.terminate(nil) }
    }

    private func activate() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }

    private func createNew(_ datatype: Datatype) {
        Task {
            do {
                _ = try await model.runJS(
                    "return await window.Patchwork.createNew(type, name);",
                    arguments: ["type": datatype.id, "name": datatype.name]
                )
                activate()
            } catch {
                model.lastError = "create new: \(error.localizedDescription)"
            }
        }
    }
}
#endif
