import Foundation
import ColonyCore

struct Usage {
    static func printAndExit(_ msg: String? = nil, code: Int32 = 1) -> Never {
        if let msg {
            fputs("error: \(msg)\n", stderr)
        }
        let help = """
        colony: control-plane CLI for local and SSH tmux-backed agent sessions

        Usage:
          colony start  <@addr> -- <cmd...>
          colony stop   <@addr>
          colony send   <@addr> <text> [--no-enter]
          colony keys   <@addr> <key...>
          colony recv   <@addr> [--lines N]
          colony watch  <@addr> [--json] [--lines N] [--interval-ms N] [--duration-sec N] [--no-initial]
          colony agent  <codex|claude> [--model MODEL]
          colony codex-rate-limit [--json]
          colony list   [local|<sshHostAlias>]
          colony providers [local|<sshHostAlias>] [--json]
          colony attach <@addr>

        Address forms:
          @session            (local)
          @local:session      (local)
          @host:session       (ssh host alias from ~/.ssh/config or resolvable hostname)

        Examples:
          colony start @local:codex1 -- codex
          colony send  @local:codex1 "explain this code" 
          colony recv  @local:codex1 --lines 200
          colony stop  @local:codex1

          colony start @mbp:claude1 -- claude
          colony attach @mbp:claude1
        """
        print(help)
        exit(code)
    }
}

enum CLIError: Error, CustomStringConvertible {
    case missingArg(String)
    case invalid(String)

    var description: String {
        switch self {
        case let .missingArg(s): return "missing argument: \(s)"
        case let .invalid(s): return s
        }
    }
}

func pop(_ args: inout ArraySlice<String>, name: String) throws -> String {
    guard let v = args.first else { throw CLIError.missingArg(name) }
    args = args.dropFirst()
    return v
}

let argv = CommandLine.arguments
var args = ArraySlice(argv.dropFirst())

guard let sub = args.first else {
    Usage.printAndExit(code: 0)
}
args = args.dropFirst()

let svc = ColonyService()

func splitLinesPreserveEmptyTail(_ s: String) -> [String] {
    // String.split omits trailing empty by default; keep it so watch doesn't
    // collapse updates when the last line becomes empty.
    var out: [String] = []
    var current = ""
    for ch in s {
        if ch == "\n" {
            out.append(current)
            current = ""
        } else {
            current.append(ch)
        }
    }
    out.append(current)
    return out
}

func computeAppendedLines(old: [String], new: [String]) -> [String] {
    if old.isEmpty { return new }
    if new.isEmpty { return [] }

    let maxK = min(old.count, new.count)
    if maxK == 0 { return new }

    // Find the largest overlap where old's suffix matches new's prefix.
    for k in stride(from: maxK, through: 1, by: -1) {
        if Array(old.suffix(k)) == Array(new.prefix(k)) {
            return Array(new.dropFirst(k))
        }
    }
    // No overlap; treat as a full redraw.
    return new
}

func runStreaming(_ cmd: [String], extraEnv: [String: String] = [:]) throws -> Int32 {
    precondition(!cmd.isEmpty)

    let p = Process()
    p.executableURL = URL(fileURLWithPath: cmd[0])
    p.arguments = Array(cmd.dropFirst())

    var env = ProcessInfo.processInfo.environment
    for (k, v) in extraEnv { env[k] = v }
    p.environment = env

    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe

    try p.run()

    // Stream bytes as they arrive.
    let h = pipe.fileHandleForReading
    while true {
        let data = h.availableData
        if data.isEmpty { break }
        FileHandle.standardOutput.write(data)
    }
    p.waitUntilExit()
    return p.terminationStatus
}

struct StreamEvent: Encodable {
    let kind: String
    let text: String
    let label: String?
    let tone: String?
    let metadata: [String: String]?
}

final class LineAccumulator: @unchecked Sendable {
    private var buffer = Data()
    private let onLine: @Sendable (String) -> Void

    init(onLine: @escaping @Sendable (String) -> Void) {
        self.onLine = onLine
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)

        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.prefix(upTo: newline)
            let line = String(data: lineData, encoding: .utf8)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\r")) ?? ""
            onLine(line)
            buffer.removeSubrange(...newline)
        }
    }

    func flush() {
        guard !buffer.isEmpty else { return }
        let line = String(data: buffer, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\r\n")) ?? ""
        if !line.isEmpty {
            onLine(line)
        }
        buffer.removeAll(keepingCapacity: false)
    }
}

@Sendable
func encodeStreamEvent(
    kind: String,
    text: String,
    label: String? = nil,
    tone: String? = nil,
    metadata: [String: String]? = nil
) -> String {
    let encoder = JSONEncoder()
    let data = try! encoder.encode(
        StreamEvent(kind: kind, text: text, label: label, tone: tone, metadata: metadata)
    )
    return String(data: data, encoding: .utf8) ?? #"{"kind":"error","text":"encoding failure"}"#
}

@Sendable
func emitStreamEvent(
    kind: String,
    text: String,
    label: String? = nil,
    tone: String? = nil,
    metadata: [String: String]? = nil
) {
    print(encodeStreamEvent(kind: kind, text: text, label: label, tone: tone, metadata: metadata))
    fflush(stdout)
}

@Sendable
func parseJSONObject(_ line: String) -> [String: Any]? {
    guard let data = line.data(using: .utf8),
          let raw = try? JSONSerialization.jsonObject(with: data),
          let object = raw as? [String: Any] else {
        return nil
    }
    return object
}

@Sendable
func isStreamEventLine(_ line: String) -> Bool {
    guard let object = parseJSONObject(line),
          let kind = object["kind"] as? String else {
        return false
    }
    return [
        "user_message",
        "assistant_message",
        "system_event",
        "tool_call",
        "warning",
        "error",
        "process_exit",
        "raw",
    ].contains(kind)
}

@Sendable
func stringValue(_ value: Any?) -> String? {
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

@Sendable
func extractReadableText(_ value: Any?) -> String? {
    guard let value else { return nil }

    if let string = value as? String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    if let array = value as? [Any] {
        let parts = array.compactMap { extractReadableText($0) }
        if parts.isEmpty { return nil }
        return dedupeAdjacent(parts).joined(separator: "\n")
    }

    if let dict = value as? [String: Any] {
        for key in [
            "text",
            "delta",
            "output_text",
            "completion",
            "message",
            "content",
            "result",
            "response",
            "part",
        ] {
            if let extracted = extractReadableText(dict[key]) {
                return extracted
            }
        }
    }

    return nil
}

@Sendable
func dedupeAdjacent(_ values: [String]) -> [String] {
    var output: [String] = []
    for value in values {
        guard output.last != value else { continue }
        output.append(value)
    }
    return output
}

@Sendable
func shouldSuppressDiagnosticLine(_ line: String) -> Bool {
    return line.hasPrefix("[oh-my-zsh]") ||
        line.contains("migration 21 was previously applied") ||
        line.contains("state db discrepancy during find_thread_path_by_id_str_in_subdir") ||
        line.contains("Failed to delete shell snapshot") ||
        line.contains("falling back to base instructions") ||
        line.contains("Falling back from WebSockets to HTTPS transport")
}

@Sendable
func diagnosticTone(for line: String) -> String {
    if line.contains("ERROR") || line.contains("error") || line.contains("fatal") {
        return "error"
    }
    return "warning"
}

@Sendable
func compactDiagnostic(_ line: String) -> String {
    let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    if parts.count > 4 {
        return parts.suffix(parts.count - 3).joined(separator: " ")
    }
    return line
}

@Sendable
func normalizeWatchLineAsEvent(_ line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if isStreamEventLine(trimmed) {
        return trimmed
    }
    guard !shouldSuppressDiagnosticLine(trimmed) else { return nil }
    if trimmed == "--- redraw ---" {
        return encodeStreamEvent(kind: "system_event", text: "Terminal redraw", tone: "neutral")
    }
    if trimmed.hasPrefix("[stderr] ") {
        let body = String(trimmed.dropFirst("[stderr] ".count))
        return encodeStreamEvent(kind: diagnosticTone(for: body), text: compactDiagnostic(body), tone: diagnosticTone(for: body))
    }
    if trimmed.hasPrefix("202") || trimmed.contains(" WARN ") || trimmed.contains(" ERROR ") {
        let tone = diagnosticTone(for: trimmed)
        return encodeStreamEvent(kind: tone, text: compactDiagnostic(trimmed), tone: tone)
    }
    return encodeStreamEvent(kind: "raw", text: trimmed, tone: "neutral")
}

@Sendable
func normalizeWatchLinesAsEvents(_ lines: [String]) -> [String] {
    var output: [String] = []
    var pendingJSON = ""

    func flushPendingIfNeeded() {
        guard !pendingJSON.isEmpty else { return }
        if let event = normalizeWatchLineAsEvent(pendingJSON) {
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
                flushPendingIfNeeded()
            }
            continue
        }

        if trimmed.hasPrefix("{") && parseJSONObject(trimmed) == nil {
            pendingJSON = trimmed
            continue
        }

        if let event = normalizeWatchLineAsEvent(trimmed) {
            output.append(event)
        }
    }

    flushPendingIfNeeded()
    return output
}

@Sendable
func appendNormalizedWatchLines(
    _ lines: [String],
    pendingJSON: inout String,
    output: inout [String]
) {
    func flushPendingIfNeeded() {
        guard !pendingJSON.isEmpty else { return }
        if let event = normalizeWatchLineAsEvent(pendingJSON) {
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
                flushPendingIfNeeded()
            }
            continue
        }

        if trimmed.hasPrefix("{") && parseJSONObject(trimmed) == nil {
            pendingJSON = trimmed
            continue
        }

        if let event = normalizeWatchLineAsEvent(trimmed) {
            output.append(event)
        }
    }
}

func runShellStreaming(
    command: [String],
    onStdoutLine: @escaping @Sendable (String) -> Void,
    onStderrLine: @escaping @Sendable (String) -> Void
) throws -> Int32 {
    precondition(!command.isEmpty)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: command[0])
    process.arguments = Array(command.dropFirst())
    process.environment = ProcessInfo.processInfo.environment

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    let stdoutAccumulator = LineAccumulator(onLine: onStdoutLine)
    let stderrAccumulator = LineAccumulator(onLine: onStderrLine)
    let group = DispatchGroup()

    group.enter()
    stdout.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        if data.isEmpty {
            handle.readabilityHandler = nil
            stdoutAccumulator.flush()
            group.leave()
            return
        }
        stdoutAccumulator.append(data)
    }

    group.enter()
    stderr.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        if data.isEmpty {
            handle.readabilityHandler = nil
            stderrAccumulator.flush()
            group.leave()
            return
        }
        stderrAccumulator.append(data)
    }

    try process.run()
    process.waitUntilExit()
    group.wait()
    return process.terminationStatus
}

@Sendable
func emitProviderEvent(from object: [String: Any], providerLabel: String) {
    let type = stringValue(object["type"]) ?? ""

    if type == "item.completed", let item = object["item"] as? [String: Any] {
        let itemType = stringValue(item["type"]) ?? ""
        if itemType == "agent_message", let text = extractReadableText(item["text"]) {
            emitStreamEvent(kind: "assistant_message", text: text, label: providerLabel)
            return
        }
        if itemType == "error" {
            let message = extractReadableText(item["message"] ?? item["error"]) ?? "Agent error"
            emitStreamEvent(kind: "error", text: message, tone: "error")
            return
        }
        if itemType.contains("tool") {
            let name = stringValue(item["name"]) ?? stringValue(item["tool_name"]) ?? "Tool call"
            emitStreamEvent(kind: "tool_call", text: name, tone: "info")
            return
        }
    }

    if type == "turn.completed" {
        if let usage = object["usage"] as? [String: Any] {
            let input = stringValue(usage["input_tokens"]) ?? "?"
            let output = stringValue(usage["output_tokens"]) ?? "?"
            emitStreamEvent(
                kind: "system_event",
                text: "Turn completed • input \(input) • output \(output)",
                tone: "info"
            )
        } else {
            emitStreamEvent(kind: "system_event", text: "Turn completed", tone: "info")
        }
        return
    }

    if type.contains("error") {
        let message = extractReadableText(object["message"] ?? object["error"]) ?? type
        emitStreamEvent(kind: "error", text: message, tone: "error")
        return
    }

    if type.contains("tool") {
        let name = stringValue(object["name"]) ?? stringValue(object["tool_name"]) ?? type
        emitStreamEvent(kind: "tool_call", text: name, tone: "info")
        return
    }

    if let text = extractReadableText(object),
       type.contains("assistant") || type.contains("message") || type.contains("delta") {
        emitStreamEvent(kind: "assistant_message", text: text, label: providerLabel)
    }
}

func runProviderTurn(shellScript: String, providerLabel: String) throws {
    let exitCode = try runShellStreaming(
        command: ["/bin/zsh", "-lc", shellScript],
        onStdoutLine: { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if let object = parseJSONObject(trimmed) {
                emitProviderEvent(from: object, providerLabel: providerLabel)
                return
            }
            guard !shouldSuppressDiagnosticLine(trimmed) else { return }
            emitStreamEvent(
                kind: diagnosticTone(for: trimmed),
                text: compactDiagnostic(trimmed),
                tone: diagnosticTone(for: trimmed)
            )
        },
        onStderrLine: { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            guard !shouldSuppressDiagnosticLine(trimmed) else { return }
            emitStreamEvent(
                kind: diagnosticTone(for: trimmed),
                text: compactDiagnostic(trimmed),
                tone: diagnosticTone(for: trimmed)
            )
        }
    )

    if exitCode != 0 {
        emitStreamEvent(
            kind: "error",
            text: "\(providerLabel) exited with code \(exitCode)",
            tone: "error",
            metadata: ["exitCode": "\(exitCode)"]
        )
    }
}

func runAgentCodex(initialModel: String) throws -> Never {
    var model = initialModel
    emitStreamEvent(kind: "system_event", text: "Codex ready • model \(model)", label: "Codex", tone: "info")

    while let lineRaw = readLine(strippingNewline: true) {
        let line = lineRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty { continue }
        if line.hasPrefix("/model ") {
            let m = line.dropFirst("/model ".count).trimmingCharacters(in: .whitespacesAndNewlines)
            if !m.isEmpty {
                model = m
                emitStreamEvent(kind: "system_event", text: "Model set to \(model)", label: "Codex", tone: "info")
            }
            continue
        }

        emitStreamEvent(kind: "user_message", text: line, label: "You")

        let tokens: [String] = [
            "codex", "exec",
            "--json",
            "--skip-git-repo-check",
            "-m", model,
            line
        ]
        let sh = ShellEscape.joinSh(tokens)
        let wrapped = "source ~/.zshrc >/dev/null 2>&1 || true; \(sh)"
        try runProviderTurn(shellScript: wrapped, providerLabel: "Codex")
    }
    exit(0)
}

func runAgentClaude(initialModel: String?) throws -> Never {
    var model = initialModel
    let readyText = model == nil ? "Claude ready" : "Claude ready • model \(model!)"
    emitStreamEvent(kind: "system_event", text: readyText, label: "Claude", tone: "info")

    while let lineRaw = readLine(strippingNewline: true) {
        let line = lineRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty { continue }
        if line.hasPrefix("/model ") {
            let m = line.dropFirst("/model ".count).trimmingCharacters(in: .whitespacesAndNewlines)
            if !m.isEmpty {
                model = m
                emitStreamEvent(kind: "system_event", text: "Model set to \(model!)", label: "Claude", tone: "info")
            }
            continue
        }

        emitStreamEvent(kind: "user_message", text: line, label: "You")

        var tokens: [String] = [
            "claude",
            "-p",
            "--verbose",
            "--output-format=stream-json",
            "--include-partial-messages",
        ]
        if let model, !model.isEmpty {
            tokens.append(contentsOf: ["--model", model])
        }
        tokens.append(line)
        let sh = ShellEscape.joinSh(tokens)
        let wrapped = "source ~/.zshrc >/dev/null 2>&1 || true; \(sh)"
        try runProviderTurn(shellScript: wrapped, providerLabel: "Claude")
    }
    exit(0)
}

do {
    switch sub {
    case "start":
        let addrRaw = try pop(&args, name: "@addr")
        // Expect a literal "--" then command.
        guard let sepIdx = args.firstIndex(of: "--") else {
            throw CLIError.invalid("start requires -- separator before command")
        }
        let after = args.index(after: sepIdx)
        let cmd = Array(args.suffix(from: after))
        guard !cmd.isEmpty else { throw CLIError.invalid("start missing command after --") }

        let addr = try Address.parse(addrRaw)
        try svc.start(address: addr, command: cmd)
        print("started \(addr.pretty)")

    case "stop":
        let addr = try Address.parse(try pop(&args, name: "@addr"))
        try svc.stop(address: addr)
        print("stopped \(addr.pretty)")

    case "send":
        let addr = try Address.parse(try pop(&args, name: "@addr"))
        let text = try pop(&args, name: "text")
        var pressEnter = true
        while let flag = args.first {
            if flag == "--no-enter" {
                pressEnter = false
                args = args.dropFirst()
            } else {
                throw CLIError.invalid("unknown flag: \(flag)")
            }
        }
        try svc.send(address: addr, text: text, pressEnter: pressEnter)

    case "keys":
        let addr = try Address.parse(try pop(&args, name: "@addr"))
        let keys = Array(args)
        guard !keys.isEmpty else { throw CLIError.missingArg("key") }
        try svc.keys(address: addr, keys: keys)

    case "recv":
        let addr = try Address.parse(try pop(&args, name: "@addr"))
        var lines = 200
        while let flag = args.first {
            if flag == "--lines" {
                args = args.dropFirst()
                let n = try pop(&args, name: "N")
                guard let v = Int(n), v > 0 else { throw CLIError.invalid("--lines must be a positive integer") }
                lines = v
            } else {
                throw CLIError.invalid("unknown flag: \(flag)")
            }
        }
        let out = try svc.recv(address: addr, lines: lines)
        print(out, terminator: "")

    case "watch":
        let addr = try Address.parse(try pop(&args, name: "@addr"))
        var lines = 400
        var intervalMs = 250
        var printInitial = true
        var durationSec: Int? = nil
        var emitJson = false
        while let flag = args.first {
            if flag == "--json" {
                emitJson = true
                args = args.dropFirst()
            } else if flag == "--lines" {
                args = args.dropFirst()
                let n = try pop(&args, name: "N")
                guard let v = Int(n), v > 0 else { throw CLIError.invalid("--lines must be a positive integer") }
                lines = v
            } else if flag == "--interval-ms" {
                args = args.dropFirst()
                let n = try pop(&args, name: "N")
                guard let v = Int(n), v > 0 else { throw CLIError.invalid("--interval-ms must be a positive integer") }
                intervalMs = v
            } else if flag == "--duration-sec" {
                args = args.dropFirst()
                let n = try pop(&args, name: "N")
                guard let v = Int(n), v > 0 else { throw CLIError.invalid("--duration-sec must be a positive integer") }
                durationSec = v
            } else if flag == "--no-initial" {
                args = args.dropFirst()
                printInitial = false
            } else {
                throw CLIError.invalid("unknown flag: \(flag)")
            }
        }

        var lastLines: [String] = []
        var pendingWatchJSON = ""
        if printInitial {
            let first = try svc.recv(address: addr, lines: lines)
            if emitJson {
                var events: [String] = []
                appendNormalizedWatchLines(
                    splitLinesPreserveEmptyTail(first),
                    pendingJSON: &pendingWatchJSON,
                    output: &events
                )
                for event in events {
                    print(event)
                }
                fflush(stdout)
            } else {
                print(first, terminator: first.hasSuffix("\n") ? "" : "\n")
                fflush(stdout)
            }
            lastLines = splitLinesPreserveEmptyTail(first)
        }

        let startTs = Date()
        while true {
            usleep(useconds_t(intervalMs * 1000))
            let snap = try svc.recv(address: addr, lines: lines)
            let currentLines = splitLinesPreserveEmptyTail(snap)
            let delta = computeAppendedLines(old: lastLines, new: currentLines)
            if !delta.isEmpty {
                if emitJson {
                    var events: [String] = []
                    appendNormalizedWatchLines(
                        delta,
                        pendingJSON: &pendingWatchJSON,
                        output: &events
                    )
                    for event in events {
                        print(event)
                    }
                } else {
                    // If it's a full redraw (no overlap), visually separate it.
                    if lastLines.count > 0 && delta.count == currentLines.count {
                        print("\n--- redraw ---")
                    }
                    for line in delta {
                        print(line)
                    }
                }
                fflush(stdout)
            }
            lastLines = currentLines

            if let durationSec, Date().timeIntervalSince(startTs) >= Double(durationSec) {
                break
            }
        }
        if emitJson, !pendingWatchJSON.isEmpty {
            if let event = normalizeWatchLineAsEvent(pendingWatchJSON) {
                print(event)
                fflush(stdout)
            }
        }
        // Clean exit after duration.
        exit(0)

    case "agent":
        let kind = try pop(&args, name: "codex|claude")
        var model: String? = nil
        while let flag = args.first {
            if flag == "--model" {
                args = args.dropFirst()
                model = try pop(&args, name: "MODEL")
            } else {
                throw CLIError.invalid("unknown flag: \(flag)")
            }
        }
        if kind == "codex" {
            try runAgentCodex(initialModel: model ?? "gpt-5.2")
        } else if kind == "claude" {
            try runAgentClaude(initialModel: model)
        } else {
            throw CLIError.invalid("agent kind must be 'codex' or 'claude'")
        }

    case "codex-rate-limit", "codex-ratelimit":
        var json = false
        while let flag = args.first {
            if flag == "--json" {
                json = true
                args = args.dropFirst()
            } else {
                throw CLIError.invalid("unknown flag: \(flag)")
            }
        }

        let reader = CodexRateLimitReader()
        let snap = try reader.latestCodexRateLimit()

        if json {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]

            struct Out: Codable {
                let timestamp: String?
                let sourceFile: String
                let rateLimits: CodexRateLimits
            }

            let ts = snap.timestamp.map { ISO8601DateFormatter().string(from: $0) }
            let out = Out(timestamp: ts, sourceFile: snap.sourceFile, rateLimits: snap.rateLimits)
            let data = try enc.encode(out)
            guard let s = String(data: data, encoding: .utf8) else { throw CLIError.invalid("failed to encode json") }
            print(s)
        } else {
            func fmtWindow(_ name: String, _ w: CodexRateLimits.Window?) -> String {
                guard let w else { return "\(name): (missing)" }
                let used = w.usedPercent.map { String(format: "%.1f%% used", $0) } ?? "used: ?"
                let win = w.windowMinutes.map { "window: \($0)m" } ?? "window: ?"
                let reset: String
                if let ra = w.resetsAt {
                    let d = Date(timeIntervalSince1970: TimeInterval(ra))
                    reset = "resetsAt: \(ISO8601DateFormatter().string(from: d))"
                } else {
                    reset = "resetsAt: ?"
                }
                return "\(name): \(used) (\(win), \(reset))"
            }

            print("codex rate limits")
            if let ts = snap.timestamp {
                print("observedAt: \(ISO8601DateFormatter().string(from: ts))")
            }
            print("source: \(snap.sourceFile)")
            if let limitId = snap.rateLimits.limitId { print("limitId: \(limitId)") }
            print(fmtWindow("primary", snap.rateLimits.primary))
            print(fmtWindow("secondary", snap.rateLimits.secondary))
            if let c = snap.rateLimits.credits {
                let bal = c.balance.map { "\($0)" } ?? "null"
                print("credits: hasCredits=\(c.hasCredits ?? false) unlimited=\(c.unlimited ?? false) balance=\(bal)")
            }
        }

    case "list":
        var t: Target = .local
        if let target = args.first {
            args = args.dropFirst()
            if target == "local" { t = .local }
            else { t = .ssh(host: target) }
        }
        if let extra = args.first {
            throw CLIError.invalid("unexpected argument: \(extra)")
        }
        let sessions = try svc.list(target: t)
        for s in sessions { print("@\(t.displayName):\(s)") }

    case "providers":
        var t: Target = .local
        var json = false
        while let arg = args.first {
            if arg == "--json" {
                json = true
                args = args.dropFirst()
            } else {
                args = args.dropFirst()
                if arg == "local" { t = .local }
                else { t = .ssh(host: arg) }
            }
        }

        let providers = try svc.providers(target: t)
        if json {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(providers)
            guard let s = String(data: data, encoding: .utf8) else { throw CLIError.invalid("failed to encode json") }
            print(s)
        } else {
            for p in providers { print(p) }
        }

    case "attach":
        let addr = try Address.parse(try pop(&args, name: "@addr"))
        if let extra = args.first {
            throw CLIError.invalid("unexpected argument: \(extra)")
        }
        // Replaces current process.
        try svc.attach(address: addr)

    case "help", "--help", "-h":
        Usage.printAndExit(code: 0)

    default:
        Usage.printAndExit("unknown subcommand: \(sub)")
    }
} catch {
    Usage.printAndExit(String(describing: error))
}
