import AppIntents

struct AddDictionaryToFolderIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Dictionary to Folder"
    static let description = IntentDescription(
        "Creates an Automerge document from a dictionary and links it into a folder document (the patchwork-folder shape). Returns the new document's automerge: URL."
    )

    @Parameter(
        title: "Folder URL",
        description: "The automerge: URL of the folder document. Leave empty to use your account's root folder."
    )
    var folderUrl: String?

    @Parameter(title: "Name", description: "The name for the new entry")
    var name: String

    @Parameter(
        title: "Dictionary",
        description: "The dictionary contents as JSON text (a Shortcuts Dictionary converts automatically)"
    )
    var dictionary: String

    @Parameter(
        title: "Type",
        description: "Optional @patchwork type — merged into the document as {\"@patchwork\": {\"type\": …}} and used as the folder entry's type"
    )
    var type: String?

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        if let folderUrl, !folderUrl.isEmpty, !folderUrl.hasPrefix("automerge:") {
            throw PatchworkIntentError.javaScript("Folder URL must start with automerge:")
        }
        let result = try await AppModel.shared.runJS(
            """
            const content = JSON.parse(json);
            return await window.Patchwork.addToFolder(folderUrl || undefined, name, content, type || undefined);
            """,
            arguments: [
                "folderUrl": folderUrl ?? "",
                "name": name,
                "json": dictionary,
                "type": type ?? "",
            ]
        )
        guard let url = result as? String else {
            throw PatchworkIntentError.unexpectedResult
        }
        return .result(value: url)
    }
}
