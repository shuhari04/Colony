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
          colony session create --provider <id> --node <node> --name <name> [--model MODEL] [--json]
          colony session send   <@addr> <text> [--no-enter]
          colony session watch  <@addr> [--json] [--lines N] [--interval-ms N] [--duration-sec N] [--no-initial]
          colony session list   [local|<sshHostAlias>] [--json]
          colony session get    <@addr> [--json]
          colony session stop   <@addr>
          colony providers list [local|<sshHostAlias>] [--json]
          colony nodes probe    [local|<sshHostAlias>] [--json]
          colony agent          <codex|claude> [--model MODEL]

        Compatibility:
          colony start  <@addr> -- <cmd...>
          colony stop   <@addr>
          colony send   <@addr> <text> [--no-enter]
          colony watch  <@addr> [--json] [--lines N] [--interval-ms N] [--duration-sec N] [--no-initial]
          colony list   [local|<sshHostAlias>]
          colony providers [local|<sshHostAlias>] [--json]
          colony attach <@addr>
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
    guard let value = args.first else { throw CLIError.missingArg(name) }
    args = args.dropFirst()
    return value
}

func parseTarget(_ raw: String?) -> Target {
    guard let raw else { return .local }
    return raw == "local" ? .local : .ssh(host: raw)
}

func parseNode(_ raw: String) -> Target {
    raw == "local" ? .local : .ssh(host: raw)
}

func printJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    guard let text = String(data: data, encoding: .utf8) else {
        throw CLIError.invalid("failed to encode json")
    }
    print(text)
}

func splitLinesPreserveEmptyTail(_ s: String) -> [String] {
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
    for k in stride(from: maxK, through: 1, by: -1) {
        if Array(old.suffix(k)) == Array(new.prefix(k)) {
            return Array(new.dropFirst(k))
        }
    }
    return new
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

final class MutableBox<T>: @unchecked Sendable {
    var value: T

    init(_ value: T) {
        self.value = value
    }
}

func runShellStreaming(
    command: [String],
    extraEnv: [String: String] = [:],
    onStdoutLine: @escaping @Sendable (String) -> Void,
    onStderrLine: @escaping @Sendable (String) -> Void
) throws -> Int32 {
    precondition(!command.isEmpty)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: command[0])
    process.arguments = Array(command.dropFirst())
    var env = ProcessInfo.processInfo.environment
    for (key, value) in extraEnv {
        env[key] = value
    }
    process.environment = env
    process.standardInput = FileHandle(forReadingAtPath: "/dev/null")

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

func emit(_ event: TranscriptEvent) {
    print(event.encodedLine())
    fflush(stdout)
}

func runProviderTurn(shellScript: String, providerLabel: String) throws {
    let exitCode = try runShellStreaming(
        command: ["/bin/zsh", "-lc", shellScript],
        onStdoutLine: { line in
            if let event = TranscriptNormalizer.parseProviderOutputLine(line, providerLabel: providerLabel) {
                emit(event)
            }
        },
        onStderrLine: { line in
            if let event = TranscriptNormalizer.parseProviderOutputLine(line, providerLabel: providerLabel) {
                emit(event)
            }
        }
    )

    if exitCode != 0 {
        emit(TranscriptEvent(
            kind: "error",
            text: "\(providerLabel) exited with code \(exitCode)",
            tone: "error",
            metadata: ["exitCode": "\(exitCode)"]
        ))
    }
}

func runProviderCommand(
    command: [String],
    providerLabel: String,
    extraEnv: [String: String] = [:],
    onJSONObject: (@Sendable ([String: Any]) -> Void)? = nil
) throws {
    let exitCode = try runShellStreaming(
        command: command,
        extraEnv: extraEnv,
        onStdoutLine: { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if let object = parseJSONObject(trimmed) {
                onJSONObject?(object)
            }
            if let event = TranscriptNormalizer.parseProviderOutputLine(trimmed, providerLabel: providerLabel) {
                emit(event)
            }
        },
        onStderrLine: { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if let event = TranscriptNormalizer.parseProviderOutputLine(trimmed, providerLabel: providerLabel) {
                emit(event)
            }
        }
    )

    if exitCode != 0 {
        emit(TranscriptEvent(
            kind: "error",
            text: "\(providerLabel) exited with code \(exitCode)",
            tone: "error",
            metadata: ["exitCode": "\(exitCode)"]
        ))
    }
}

func makeColonyStateDir(component: String) throws -> String {
    let fm = FileManager.default
    let dir = fm.homeDirectoryForCurrentUser
        .appendingPathComponent(".colony", isDirectory: true)
        .appendingPathComponent("provider_state", isDirectory: true)
        .appendingPathComponent(component, isDirectory: true)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.path
}

func runAgentCodex(initialModel: String?) throws -> Never {
    var model = initialModel?.trimmingCharacters(in: .whitespacesAndNewlines)
    if model?.isEmpty == true {
        model = nil
    }
    let threadID = MutableBox<String?>(nil)
    let codexHome = try makeColonyStateDir(component: "codex-\(UUID().uuidString.lowercased())")
    let ready = model == nil ? "Codex ready" : "Codex ready • model \(model!)"
    emit(TranscriptEvent(kind: "system_event", text: ready, label: "Codex", tone: "info"))

    while let raw = readLine(strippingNewline: true) {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty { continue }
        if line.hasPrefix("/model ") {
            let next = String(line.dropFirst("/model ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !next.isEmpty {
                model = next
                emit(TranscriptEvent(kind: "system_event", text: "Model set to \(next)", label: "Codex", tone: "info"))
            }
            continue
        }

        emit(TranscriptEvent(kind: "user_message", text: line, label: "You"))
        var command = ["/usr/bin/env", "codex", "exec"]
        if let existing = threadID.value, !existing.isEmpty {
            command.append("resume")
        }
        command.append(contentsOf: [
            "--json",
            "--skip-git-repo-check",
        ])
        if let model, !model.isEmpty {
            command.append(contentsOf: ["-m", model])
        }
        if let existing = threadID.value, !existing.isEmpty {
            command.append(existing)
        }
        command.append(line)
        try runProviderCommand(
            command: command,
            providerLabel: "Codex",
            extraEnv: ["CODEX_HOME": codexHome],
            onJSONObject: { object in
                if (object["type"] as? String) == "thread.started",
                   let started = object["thread_id"] as? String,
                   !started.isEmpty {
                    threadID.value = started
                }
            }
        )
    }
    exit(0)
}

func runAgentClaude(initialModel: String?) throws -> Never {
    var model = initialModel
    let sessionID = UUID().uuidString.lowercased()
    var hasTurn = false
    let ready = model == nil ? "Claude ready" : "Claude ready • model \(model!)"
    emit(TranscriptEvent(kind: "system_event", text: ready, label: "Claude", tone: "info"))

    while let raw = readLine(strippingNewline: true) {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty { continue }
        if line.hasPrefix("/model ") {
            let next = String(line.dropFirst("/model ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !next.isEmpty {
                model = next
                emit(TranscriptEvent(kind: "system_event", text: "Model set to \(next)", label: "Claude", tone: "info"))
            }
            continue
        }

        emit(TranscriptEvent(kind: "user_message", text: line, label: "You"))
        var command = [
            "/usr/bin/env",
            "claude",
            "-p",
            "--verbose",
            "--output-format=stream-json",
            "--include-partial-messages",
        ]
        if hasTurn {
            command.append(contentsOf: ["--resume", sessionID])
        } else {
            command.append(contentsOf: ["--session-id", sessionID])
        }
        if let model, !model.isEmpty {
            command.append(contentsOf: ["--model", model])
        }
        command.append(line)
        try runProviderCommand(command: command, providerLabel: "Claude")
        hasTurn = true
    }
    exit(0)
}

let svc = ColonyService()
let argv = CommandLine.arguments
var args = ArraySlice(argv.dropFirst())
guard let sub = args.first else { Usage.printAndExit(code: 0) }
args = args.dropFirst()

@MainActor
func handleSession(_ args: inout ArraySlice<String>) throws {
    let command = try pop(&args, name: "session command")
    switch command {
    case "create":
        var provider: ProviderID?
        var node = "local"
        var name: String?
        var model: String?
        var json = false

        while let flag = args.first {
            switch flag {
            case "--provider":
                args = args.dropFirst()
                provider = ProviderID(rawValue: try pop(&args, name: "provider"))
            case "--node":
                args = args.dropFirst()
                node = try pop(&args, name: "node")
            case "--name":
                args = args.dropFirst()
                name = try pop(&args, name: "name")
            case "--model":
                args = args.dropFirst()
                model = try pop(&args, name: "model")
            case "--json":
                json = true
                args = args.dropFirst()
            default:
                throw CLIError.invalid("unknown flag: \(flag)")
            }
        }

        guard let provider else { throw CLIError.missingArg("--provider") }
        guard let name else { throw CLIError.missingArg("--name") }
        let summary = try svc.createSession(
            request: SessionCreateRequest(node: node, name: name, provider: provider, model: model),
            colonyBinaryPath: CommandLine.arguments[0]
        )
        if json {
            try printJSON(summary)
        } else {
            print(summary.address)
        }

    case "send":
        let address = try Address.parse(try pop(&args, name: "@addr"))
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
        try svc.send(address: address, text: text, pressEnter: pressEnter)

    case "watch":
        let address = try Address.parse(try pop(&args, name: "@addr"))
        var lines = 400
        var intervalMs = 250
        var printInitial = true
        var durationSec: Int?
        var emitJson = false

        while let flag = args.first {
            switch flag {
            case "--json":
                emitJson = true
                args = args.dropFirst()
            case "--lines":
                args = args.dropFirst()
                lines = Int(try pop(&args, name: "N")) ?? 0
                guard lines > 0 else { throw CLIError.invalid("--lines must be a positive integer") }
            case "--interval-ms":
                args = args.dropFirst()
                intervalMs = Int(try pop(&args, name: "N")) ?? 0
                guard intervalMs > 0 else { throw CLIError.invalid("--interval-ms must be a positive integer") }
            case "--duration-sec":
                args = args.dropFirst()
                durationSec = Int(try pop(&args, name: "N"))
                guard (durationSec ?? 0) > 0 else { throw CLIError.invalid("--duration-sec must be a positive integer") }
            case "--no-initial":
                printInitial = false
                args = args.dropFirst()
            default:
                throw CLIError.invalid("unknown flag: \(flag)")
            }
        }

        var lastLines: [String] = []
        var pendingJSON = ""
        if printInitial {
            let first = try svc.recv(address: address, lines: lines)
            if emitJson {
                for event in TranscriptNormalizer.normalizeWatchLines(splitLinesPreserveEmptyTail(first), pendingJSON: &pendingJSON) {
                    emit(event)
                }
            } else {
                print(first, terminator: first.hasSuffix("\n") ? "" : "\n")
                fflush(stdout)
            }
            lastLines = splitLinesPreserveEmptyTail(first)
        } else {
            let baseline = try svc.recv(address: address, lines: lines)
            lastLines = splitLinesPreserveEmptyTail(baseline)
        }

        let startTs = Date()
        while true {
            usleep(useconds_t(intervalMs * 1000))
            let snap = try svc.recv(address: address, lines: lines)
            let currentLines = splitLinesPreserveEmptyTail(snap)
            let delta = computeAppendedLines(old: lastLines, new: currentLines)
            if !delta.isEmpty {
                if emitJson {
                    var events: [TranscriptEvent] = []
                    TranscriptNormalizer.appendNormalizedWatchLines(delta, pendingJSON: &pendingJSON, output: &events)
                    for event in events { emit(event) }
                } else {
                    if lastLines.count > 0 && delta.count == currentLines.count {
                        print("\n--- redraw ---")
                    }
                    for line in delta { print(line) }
                    fflush(stdout)
                }
            }
            lastLines = currentLines

            if let durationSec, Date().timeIntervalSince(startTs) >= Double(durationSec) {
                break
            }
        }
        if emitJson, !pendingJSON.isEmpty, let event = TranscriptNormalizer.normalizeWatchLine(pendingJSON) {
            emit(event)
        }
        exit(0)

    case "list":
        var json = false
        let targetRaw = args.first.flatMap { $0.hasPrefix("-") ? nil : String($0) }
        if targetRaw != nil { args = args.dropFirst() }
        while let flag = args.first {
            if flag == "--json" {
                json = true
                args = args.dropFirst()
            } else {
                throw CLIError.invalid("unknown flag: \(flag)")
            }
        }
        let sessions = try svc.listSessionSummaries(target: parseTarget(targetRaw))
        if json {
            try printJSON(sessions)
        } else {
            for session in sessions { print(session.address) }
        }

    case "get":
        let address = try Address.parse(try pop(&args, name: "@addr"))
        let json = args.first == "--json"
        if json { args = args.dropFirst() }
        if let extra = args.first { throw CLIError.invalid("unexpected argument: \(extra)") }
        let session = try svc.sessionSummary(address: address)
        if json {
            try printJSON(session)
        } else {
            print(session.address)
        }

    case "stop":
        let address = try Address.parse(try pop(&args, name: "@addr"))
        if let extra = args.first { throw CLIError.invalid("unexpected argument: \(extra)") }
        try svc.stop(address: address)
        print("stopped \(address.pretty)")

    default:
        throw CLIError.invalid("unknown session command: \(command)")
    }
}

@MainActor
func handleProviders(_ args: inout ArraySlice<String>) throws {
    let maybeSub = args.first == nil ? nil : String(args.first!)
    if maybeSub == "list" {
        args = args.dropFirst()
    }

    var json = false
    let targetRaw = args.first.flatMap { $0.hasPrefix("-") ? nil : String($0) }
    if targetRaw != nil { args = args.dropFirst() }
    while let flag = args.first {
        if flag == "--json" {
            json = true
            args = args.dropFirst()
        } else {
            throw CLIError.invalid("unknown flag: \(flag)")
        }
    }
    let providers = try svc.providerSummaries(target: parseTarget(targetRaw))
    if json {
        try printJSON(providers)
    } else {
        for provider in providers where provider.available {
            print(provider.id)
        }
    }
}

@MainActor
func handleNodes(_ args: inout ArraySlice<String>) throws {
    let maybeSub = args.first == nil ? nil : String(args.first!)
    if maybeSub == "probe" {
        args = args.dropFirst()
    }
    var json = false
    let node = args.first.flatMap { $0.hasPrefix("-") ? nil : String($0) } ?? "local"
    if args.first != nil, !args.first!.hasPrefix("-") { args = args.dropFirst() }
    while let flag = args.first {
        if flag == "--json" {
            json = true
            args = args.dropFirst()
        } else {
            throw CLIError.invalid("unknown flag: \(flag)")
        }
    }

    struct NodeProbe: Encodable {
        let node: String
        let providers: [ProviderSummary]
    }

    let probe = NodeProbe(node: node, providers: try svc.providerSummaries(target: parseNode(node)))
    if json {
        try printJSON(probe)
    } else {
        print(node)
        for provider in probe.providers where provider.available {
            print("  \(provider.id)")
        }
    }
}

@MainActor
func handleLegacyStart(_ args: inout ArraySlice<String>) throws {
    let address = try Address.parse(try pop(&args, name: "@addr"))
    guard let sepIdx = args.firstIndex(of: "--") else {
        throw CLIError.invalid("start requires -- separator before command")
    }
    let command = Array(args.suffix(from: args.index(after: sepIdx)))
    guard !command.isEmpty else { throw CLIError.invalid("start missing command after --") }
    try svc.start(address: address, command: command)
    print("started \(address.pretty)")
}

do {
    switch sub {
    case "session":
        try handleSession(&args)

    case "providers":
        try handleProviders(&args)

    case "nodes":
        try handleNodes(&args)

    case "agent":
        let kind = try pop(&args, name: "codex|claude")
        var model: String?
        while let flag = args.first {
            if flag == "--model" {
                args = args.dropFirst()
                model = try pop(&args, name: "model")
            } else {
                throw CLIError.invalid("unknown flag: \(flag)")
            }
        }
        if kind == "codex" {
            try runAgentCodex(initialModel: model)
        } else if kind == "claude" {
            try runAgentClaude(initialModel: model)
        } else {
            throw CLIError.invalid("agent kind must be 'codex' or 'claude'")
        }

    case "start":
        try handleLegacyStart(&args)

    case "stop":
        let address = try Address.parse(try pop(&args, name: "@addr"))
        try svc.stop(address: address)
        print("stopped \(address.pretty)")

    case "send":
        args = ["send"] + args
        try handleSession(&args)

    case "watch":
        args = ["watch"] + args
        try handleSession(&args)

    case "list":
        args = ["list"] + args
        try handleSession(&args)

    case "attach":
        let address = try Address.parse(try pop(&args, name: "@addr"))
        if let extra = args.first { throw CLIError.invalid("unexpected argument: \(extra)") }
        try svc.attach(address: address)

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
            struct Out: Codable {
                let timestamp: String?
                let sourceFile: String
                let rateLimits: CodexRateLimits
            }
            let ts = snap.timestamp.map { ISO8601DateFormatter().string(from: $0) }
            try printJSON(Out(timestamp: ts, sourceFile: snap.sourceFile, rateLimits: snap.rateLimits))
        } else {
            func fmtWindow(_ name: String, _ w: CodexRateLimits.Window?) -> String {
                guard let w else { return "\(name): (missing)" }
                let used = w.usedPercent.map { String(format: "%.1f%% used", $0) } ?? "used: ?"
                let win = w.windowMinutes.map { "window: \($0)m" } ?? "window: ?"
                let reset = w.resetsAt.map {
                    "resetsAt: \(ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: TimeInterval($0))))"
                } ?? "resetsAt: ?"
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
            if let credits = snap.rateLimits.credits {
                let balance = credits.balance.map { "\($0)" } ?? "null"
                print("credits: hasCredits=\(credits.hasCredits ?? false) unlimited=\(credits.unlimited ?? false) balance=\(balance)")
            }
        }

    case "help", "--help", "-h":
        Usage.printAndExit(code: 0)

    default:
        Usage.printAndExit("unknown subcommand: \(sub)")
    }
} catch {
    Usage.printAndExit(String(describing: error))
}
