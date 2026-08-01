import AppIntents
import UniformTypeIdentifiers

struct AddFileToFolderIntent: AppIntent {
    static let title: LocalizedStringResource = "Add File to Folder"
    static let description = IntentDescription(
        "Creates a patchwork file document (UnixFileEntry shape) from a file and links it into a folder document. Returns the new document's automerge: URL."
    )

    @Parameter(
        title: "Folder",
        description: "The folder to add to — pick a top-level folder or search by an automerge: URL. Leave empty to use the default shortcut folder, then your account's root folder."
    )
    var folder: FolderEntity?

    @Parameter(title: "File")
    var file: IntentFile

    @Parameter(
        title: "Name",
        description: "Entry name; defaults to the file's own name"
    )
    var name: String?

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let filename = name ?? file.filename
        let mimeType = file.type?.preferredMIMEType ?? "application/octet-stream"
        let result = try await AppModel.shared.runJS(
            """
            return await window.Patchwork.addFileToFolder(folderUrl || undefined, name, base64, mimeType);
            """,
            arguments: [
                "folderUrl": folder?.id ?? "",
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
