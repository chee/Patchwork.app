import AppIntents

struct PatchworkShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RunJavaScriptIntent(),
            phrases: ["Run JavaScript in \(.applicationName)"],
            shortTitle: "Run JavaScript",
            systemImageName: "curlybraces"
        )
        AppShortcut(
            intent: AddDictionaryToFolderIntent(),
            phrases: ["Add a dictionary in \(.applicationName)"],
            shortTitle: "Add Dictionary",
            systemImageName: "folder.badge.plus"
        )
        AppShortcut(
            intent: AddFileToFolderIntent(),
            phrases: ["Add a file in \(.applicationName)"],
            shortTitle: "Add File",
            systemImageName: "doc.badge.plus"
        )
    }
}
