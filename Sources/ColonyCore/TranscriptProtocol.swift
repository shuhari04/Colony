import Foundation

public struct TranscriptEvent: Codable, Equatable, Sendable {
    public let kind: String
    public let text: String
    public let label: String?
    public let tone: String?
    public let metadata: [String: String]?

    public init(kind: String, text: String, label: String? = nil, tone: String? = nil, metadata: [String: String]? = nil) {
        self.kind = kind
        self.text = text
        self.label = label
        self.tone = tone
        self.metadata = metadata
    }

    public func encodedLine() -> String {
        let encoder = JSONEncoder()
        let data = try! encoder.encode(self)
        return String(data: data, encoding: .utf8) ?? #"{"kind":"error","text":"encoding failure"}"#
    }
}

public enum TranscriptNormalizer {
    public static func normalizeWatchLine(_ line: String) -> TranscriptEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let event = parseTranscriptEventLine(trimmed) {
            return event
        }
        guard !shouldSuppressDiagnosticLine(trimmed) else { return nil }

        if trimmed == "--- redraw ---" {
            return TranscriptEvent(kind: "system_event", text: "Terminal redraw", tone: "neutral")
        }
        if trimmed.hasPrefix("[stderr] ") {
            let body = String(trimmed.dropFirst("[stderr] ".count))
            let tone = diagnosticTone(for: body)
            return TranscriptEvent(kind: tone, text: compactDiagnostic(body), tone: tone)
        }
        if trimmed.hasPrefix("[colony-agent] >>> ") {
            return TranscriptEvent(kind: "user_message", text: String(trimmed.dropFirst("[colony-agent] >>> ".count)).trimmingCharacters(in: .whitespacesAndNewlines), label: "You")
        }
        if trimmed.hasPrefix("[colony-agent] <<<") {
            return TranscriptEvent(kind: "system_event", text: "Turn completed", tone: "info")
        }
        if trimmed.hasPrefix("[colony-agent] model set to ") {
            return TranscriptEvent(kind: "system_event", text: String(trimmed.dropFirst("[colony-agent] ".count)).trimmingCharacters(in: .whitespacesAndNewlines), tone: "info")
        }
        if trimmed.hasPrefix("[colony-agent]") {
            return TranscriptEvent(kind: "system_event", text: String(trimmed.dropFirst("[colony-agent]".count)).trimmingCharacters(in: .whitespacesAndNewlines), tone: "neutral")
        }
        if trimmed.hasPrefix("202") || trimmed.contains(" WARN ") || trimmed.contains(" ERROR ") {
            let tone = diagnosticTone(for: trimmed)
            return TranscriptEvent(kind: tone, text: compactDiagnostic(trimmed), tone: tone)
        }
        return TranscriptEvent(kind: "raw", text: trimmed, tone: "neutral")
    }

    public static func normalizeWatchLines(_ lines: [String], pendingJSON: inout String) -> [TranscriptEvent] {
        var output: [TranscriptEvent] = []
        appendNormalizedWatchLines(lines, pendingJSON: &pendingJSON, output: &output)
        return output
    }

    public static func appendNormalizedWatchLines(_ lines: [String], pendingJSON: inout String, output: inout [TranscriptEvent]) {
        func flushPending() {
            guard !pendingJSON.isEmpty else { return }
            if let event = normalizeWatchLine(pendingJSON) {
                output.append(event)
            }
            pendingJSON = ""
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if !pendingJSON.isEmpty {
                pendingJSON += trimmed
                if parseJSONObject(pendingJSON) != nil {
                    flushPending()
                }
                continue
            }

            if trimmed.hasPrefix("{") && parseJSONObject(trimmed) == nil {
                pendingJSON = trimmed
                continue
            }

            if let event = normalizeWatchLine(trimmed) {
                output.append(event)
            }
        }
    }

    public static func parseProviderOutputLine(_ line: String, providerLabel: String) -> TranscriptEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let object = parseJSONObject(trimmed) {
            return providerEvent(from: object, providerLabel: providerLabel)
        }
        guard !shouldSuppressDiagnosticLine(trimmed) else { return nil }
        let tone = diagnosticTone(for: trimmed)
        return TranscriptEvent(kind: tone, text: compactDiagnostic(trimmed), tone: tone)
    }
}

public func parseTranscriptEventLine(_ line: String) -> TranscriptEvent? {
    guard let object = parseJSONObject(line),
          let kind = object["kind"] as? String else {
        return nil
    }
    guard [
        "user_message",
        "assistant_message",
        "system_event",
        "tool_call",
        "warning",
        "error",
        "process_exit",
        "raw",
    ].contains(kind) else {
        return nil
    }
    return TranscriptEvent(
        kind: kind,
        text: (object["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
        label: (object["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
        tone: (object["tone"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
        metadata: object["metadata"] as? [String: String]
    )
}

public func parseJSONObject(_ line: String) -> [String: Any]? {
    guard let data = line.data(using: .utf8),
          let raw = try? JSONSerialization.jsonObject(with: data),
          let object = raw as? [String: Any] else {
        return nil
    }
    return object
}

public func stringValue(_ value: Any?) -> String? {
    guard let value else { return nil }
    if let string = value as? String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    if let number = value as? NSNumber {
        return number.stringValue
    }
    return nil
}

public func extractReadableText(_ value: Any?) -> String? {
    guard let value else { return nil }
    if let string = value as? String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    if let array = value as? [Any] {
        let parts = array.compactMap { extractReadableText($0) }
        return parts.isEmpty ? nil : dedupeAdjacent(parts).joined(separator: "\n")
    }
    if let dict = value as? [String: Any] {
        for key in ["text", "delta", "output_text", "completion", "message", "content", "result", "response", "part"] {
            if let extracted = extractReadableText(dict[key]) {
                return extracted
            }
        }
    }
    return nil
}

public func dedupeAdjacent(_ values: [String]) -> [String] {
    var output: [String] = []
    for value in values where output.last != value {
        output.append(value)
    }
    return output
}

public func shouldSuppressDiagnosticLine(_ line: String) -> Bool {
    line.hasPrefix("[oh-my-zsh]") ||
    line.contains("migration 21 was previously applied") ||
    line.contains("state db discrepancy during find_thread_path_by_id_str_in_subdir") ||
    line.contains("Failed to delete shell snapshot") ||
    line.contains("falling back to base instructions") ||
    line.contains("Falling back from WebSockets to HTTPS transport")
}

public func diagnosticTone(for line: String) -> String {
    if line.contains("ERROR") || line.contains("error") || line.contains("fatal") {
        return "error"
    }
    return "warning"
}

public func compactDiagnostic(_ line: String) -> String {
    let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    if parts.count > 4 {
        return parts.suffix(parts.count - 3).joined(separator: " ")
    }
    return line
}

public func providerEvent(from object: [String: Any], providerLabel: String) -> TranscriptEvent? {
    let type = stringValue(object["type"]) ?? ""

    if type == "item.completed", let item = object["item"] as? [String: Any] {
        let itemType = stringValue(item["type"]) ?? ""
        if itemType == "agent_message", let text = extractReadableText(item["text"]) {
            return TranscriptEvent(kind: "assistant_message", text: text, label: providerLabel)
        }
        if itemType == "error" {
            let message = extractReadableText(item["message"] ?? item["error"]) ?? "Agent error"
            return TranscriptEvent(kind: "error", text: message, tone: "error")
        }
        if itemType.contains("tool") {
            let name = stringValue(item["name"]) ?? stringValue(item["tool_name"]) ?? "Tool call"
            return TranscriptEvent(kind: "tool_call", text: name, tone: "info")
        }
    }

    if type == "agent_message" {
        if let text = extractReadableText(object["text"] ?? object["content"]) {
            return TranscriptEvent(kind: "assistant_message", text: text, label: providerLabel)
        }
    }

    if type == "turn.completed" {
        if let usage = object["usage"] as? [String: Any] {
            let input = stringValue(usage["input_tokens"]) ?? "?"
            let output = stringValue(usage["output_tokens"]) ?? "?"
            return TranscriptEvent(kind: "system_event", text: "Turn completed • input \(input) • output \(output)", tone: "info")
        }
        return TranscriptEvent(kind: "system_event", text: "Turn completed", tone: "info")
    }

    if type.contains("error") {
        let message = extractReadableText(object["message"] ?? object["error"]) ?? type
        return TranscriptEvent(kind: "error", text: message, tone: "error")
    }

    if type.contains("tool") {
        let name = stringValue(object["name"]) ?? stringValue(object["tool_name"]) ?? type
        return TranscriptEvent(kind: "tool_call", text: name, tone: "info")
    }

    if let text = extractReadableText(object),
       type.contains("assistant") || type.contains("message") || type.contains("delta") {
        return TranscriptEvent(kind: "assistant_message", text: text, label: providerLabel)
    }
    return nil
}
