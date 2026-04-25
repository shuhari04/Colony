import XCTest
@testable import ColonyCore

final class ProviderRegistryTests: XCTestCase {
    func testProviderSummariesReflectAvailability() {
        let registry = ProviderRegistry()
        let summaries = registry.providerSummaries(availableIDs: ["codex", "openclaw"])

        XCTAssertEqual(summaries.map(\.id), ["codex", "claude", "openclaw"])
        XCTAssertEqual(summaries.first(where: { $0.id == "codex" })?.available, true)
        XCTAssertEqual(summaries.first(where: { $0.id == "claude" })?.available, false)
        XCTAssertEqual(summaries.first(where: { $0.id == "openclaw" })?.available, true)
        XCTAssertNil(summaries.first(where: { $0.id == "codex" })?.defaultModel)
    }

    func testCodexLocalLaunchCommandUsesColonyAgent() throws {
        let request = SessionCreateRequest(node: "local", name: "codex1", provider: .codex, model: "gpt-5.2")
        let runtime = try XCTUnwrap(ProviderRegistry().runtime(for: .codex))

        XCTAssertEqual(
            runtime.launchCommand(request: request, colonyBinaryPath: "/tmp/colony"),
            ["/tmp/colony", "agent", "codex", "--model", "gpt-5.2"]
        )
    }
}
