import AppIntents
import UniformTypeIdentifiers

struct AddFileToFolderIntent: AppIntent {
    static let title: LocalizedStringResource = "Add File to Folder"
    static let description = IntentDescription(
        "Creates a patchwork file document (UnixFileEntry shape) from a file and links it into a folder document. Returns the new document's automerge: URL."
    )

    @Parameter(
        title: "Folder URL",
        description: "The automerge: URL of the folder document. Leave empty to use your account's root folder."
    )
    var folderUrl: String?

    @Parameter(title: "File")
    var file: IntentFile

    @Parameter(
        title: "Name",
        description: "Entry name; defaults to the file's own name"
    )
    var name: String?

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        if let folderUrl, !folderUrl.isEmpty, !folderUrl.hasPrefix("automerge:") {
            throw PatchworkIntentError.javaScript("Folder URL must start with automerge:")
        }
        let filename = name ?? file.filename
        let mimeType = file.type?.preferredMIMEType ?? "application/octet-stream"
        let result = try await AppModel.shared.runJS(
            """
            return await window.Patchwork.addFileToFolder(folderUrl || undefined, name, base64, mimeType);
            """,
            arguments: [
                "folderUrl": folderUrl ?? "",
                "name": filename,
                "base64": file.data.base64EncodedString(),
                "mimeType": mimeType,
            ]
        )
        guard let url = result as? String else {
            throw PatchworkIntentError.unexpectedResult
        }
        return .result(value: url)
    }
}
