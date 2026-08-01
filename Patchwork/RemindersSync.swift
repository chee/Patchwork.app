#if os(macOS)
import EventKit
import Foundation

/// Mirrors new reminders from the default Reminders list into the folder at
/// tools.apple.remindersFolderUrl, falling back to defaultShortcutFolderUrl,
/// then the account root folder. Already-existing reminders are baselined on
/// first run so only reminders added afterwards are mirrored.
@MainActor
final class RemindersSync {
    private let store = EKEventStore()
    private var syncing = false
    private var needsResync = false

    private let seenKey = "remindersSync.seenReminderIds"

    func start() async {
        guard (try? await store.requestFullAccessToReminders()) == true else { return }
        if UserDefaults.standard.stringArray(forKey: seenKey) == nil {
            let ids = await fetchReminders().compactMap(\.calendarItemExternalIdentifier)
            UserDefaults.standard.set(ids, forKey: seenKey)
        }
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { _ in
            Task { @MainActor in await self.sync() }
        }
        await sync()
    }

    private func sync() async {
        if syncing {
            needsResync = true
            return
        }
        syncing = true
        defer { syncing = false }
        repeat {
            needsResync = false
            var seen = Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? [])
            for reminder in await fetchReminders() {
                guard let id = reminder.calendarItemExternalIdentifier,
                      !seen.contains(id) else { continue }
                do {
                    try await add(reminder)
                    seen.insert(id)
                } catch {
                    AppModel.shared.lastError = "reminders sync: \(error.localizedDescription)"
                }
            }
            UserDefaults.standard.set(Array(seen), forKey: seenKey)
        } while needsResync
    }

    private func fetchReminders() async -> [EKReminder] {
        guard let list = store.defaultCalendarForNewReminders() else { return [] }
        let predicate = store.predicateForReminders(in: [list])
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    private func add(_ reminder: EKReminder) async throws {
        let title = reminder.title ?? "Untitled"
        let action: [String: Any] = [
            "@patchwork": ["type": "@chee.baby/action", "title": title],
            "checklist": [Any](),
            "deleted": false,
            "id": "action-\(UUID().uuidString.lowercased())",
            "notes": reminder.notes ?? "",
            "state": "open",
            "stateChanged": NSNull(),
            "title": title,
            "type": "action",
            "when": NSNull(),
        ]
        let json = String(
            decoding: try JSONSerialization.data(withJSONObject: action),
            as: UTF8.self
        )
        _ = try await AppModel.shared.runJS(
            """
            const config = await window.Patchwork.appleConfig();
            const folder = config.remindersFolderUrl || config.defaultShortcutFolderUrl || undefined;
            return await window.Patchwork.addToFolder(folder, title, JSON.parse(json));
            """,
            arguments: ["title": title, "json": json]
        )
    }
}
#endif
