import AppIntents

struct RunJavaScriptIntent: AppIntent {
    static let title: LocalizedStringResource = "Run JavaScript in Patchwork"
    static let description = IntentDescription(
        "Runs JavaScript in Patchwork's live page. `repo` (the Automerge repo), `Patchwork` (helpers), `patchwork`, and the full window are in scope; await works. The return value comes back JSON-stringified."
    )

    @Parameter(
        title: "JavaScript",
        description: "Code to run. e.g. return (await repo.find(url)).doc()",
        inputOptions: String.IntentInputOptions(multiline: true)
    )
    var code: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let result = try await AppModel.shared.runJS(
            """
            const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
            const fn = new AsyncFunction("repo", "Patchwork", code);
            const value = await fn(window.repo, window.Patchwork);
            return value === undefined ? "undefined" : JSON.stringify(value) ?? "undefined";
            """,
            arguments: ["code": code]
        )
        guard let text = result as? String else {
            throw PatchworkIntentError.unexpectedResult
        }
        return .result(value: text)
    }
}
