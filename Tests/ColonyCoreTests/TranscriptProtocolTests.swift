import XCTest
@testable import ColonyCore

final class TranscriptProtocolTests: XCTestCase {
    func testNormalizeProviderStructuredOutput() throws {
        let line = #"{"type":"turn.completed","usage":{"input_tokens":12,"output_tokens":34}}"#
        let event = try XCTUnwrap(TranscriptNormalizer.parseProviderOutputLine(line, providerLabel: "Codex"))

        XCTAssertEqual(event.kind, "system_event")
        XCTAssertEqual(event.text, "Turn completed • input 12 • output 34")
        XCTAssertEqual(event.tone, "info")
    }

    func testNormalizeLegacyMarkerLine() throws {
        let event = try XCTUnwrap(TranscriptNormalizer.normalizeWatchLine("[colony-agent] >>> hi"))

        XCTAssertEqual(event.kind, "user_message")
        XCTAssertEqual(event.text, "hi")
        XCTAssertEqual(event.label, "You")
    }

    func testNormalizePendingMultilineJSON() {
        var pending = ""
        let events = TranscriptNormalizer.normalizeWatchLines([
            #"{"kind":"assistant_message","text":"hel"#,
            #"lo","label":"Codex"}"#,
        ], pendingJSON: &pending)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, "assistant_message")
        XCTAssertEqual(events.first?.text, "hello")
        XCTAssertEqual(events.first?.label, "Codex")
        XCTAssertEqual(pending, "")
    }
}
