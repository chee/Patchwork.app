import AppIntents

struct FolderEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Patchwork Folder"
    static let defaultQuery = FolderEntityQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(id)")
    }
}

struct FolderEntityQuery: EntityQuery, EntityStringQuery {
    private func rootFolders() async throws -> [FolderEntity] {
        let result = try await AppModel.shared.runJS(
            "return await window.Patchwork.listRootFolders();"
        )
        guard let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let url = item["url"] as? String else { return nil }
            return FolderEntity(id: url, name: item["name"] as? String ?? url)
        }
    }

    func entities(for identifiers: [String]) async throws -> [FolderEntity] {
        let known = (try? await rootFolders()) ?? []
        return identifiers.map { id in
            known.first { $0.id == id } ?? FolderEntity(id: id, name: id)
        }
    }

    func suggestedEntities() async throws -> [FolderEntity] {
        try await rootFolders()
    }

    func entities(matching string: String) async throws -> [FolderEntity] {
        if string.hasPrefix("automerge:") {
            return [FolderEntity(id: string, name: string)]
        }
        return try await rootFolders().filter {
            $0.name.localizedCaseInsensitiveContains(string)
        }
    }
}
