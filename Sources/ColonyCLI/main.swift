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
          colony watch  <@addr> [--lines N] [--interval-ms N] [--duration-sec N] [--no-initial]
          colony agent  <codex|claude> [--model MODEL]
          colony codex-rate-limit [--json]
          colony list   [local|<sshHostAlias>]
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

func runAgentCodex(initialModel: String) throws -> Never {
    var model = initialModel
    print("[colony-agent] codex ready (model=\(model))")
    fflush(stdout)

    while let lineRaw = readLine(strippingNewline: true) {
        let line = lineRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty { continue }
        if line.hasPrefix("/model ") {
            let m = line.dropFirst("/model ".count).trimmingCharacters(in: .whitespacesAndNewlines)
            if !m.isEmpty {
                model = m
                print("[colony-agent] model set to \(model)")
                fflush(stdout)
            }
            continue
        }

        print("[colony-agent] >>> \(line)")
        fflush(stdout)

        // Use zsh -lc so PATH matches the user's typical interactive shell.
        let tokens: [String] = [
            "codex", "exec",
            "--json",
            "--skip-git-repo-check",
            "-m", model,
            line
        ]
        let sh = ShellEscape.joinSh(tokens)
        _ = try runStreaming(["/usr/bin/env", "zsh", "-lc", sh])

        print("[colony-agent] <<< done")
        fflush(stdout)
    }
    exit(0)
}

func runAgentClaude(initialModel: String?) throws -> Never {
    var model = initialModel
    print("[colony-agent] claude ready\(model == nil ? "" : " (model=\(model!))")")
    fflush(stdout)

    while let lineRaw = readLine(strippingNewline: true) {
        let line = lineRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty { continue }
        if line.hasPrefix("/model ") {
            let m = line.dropFirst("/model ".count).trimmingCharacters(in: .whitespacesAndNewlines)
            if !m.isEmpty {
                model = m
                print("[colony-agent] model set to \(model!)")
                fflush(stdout)
            }
            continue
        }

        print("[colony-agent] >>> \(line)")
        fflush(stdout)

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
        _ = try runStreaming(["/usr/bin/env", "zsh", "-lc", sh])

        print("[colony-agent] <<< done")
        fflush(stdout)
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
        while let flag = args.first {
            if flag == "--lines" {
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
        if printInitial {
            let first = try svc.recv(address: addr, lines: lines)
            print(first, terminator: first.hasSuffix("\n") ? "" : "\n")
            fflush(stdout)
            lastLines = splitLinesPreserveEmptyTail(first)
        }

        let startTs = Date()
        while true {
            usleep(useconds_t(intervalMs * 1000))
            let snap = try svc.recv(address: addr, lines: lines)
            let currentLines = splitLinesPreserveEmptyTail(snap)
            let delta = computeAppendedLines(old: lastLines, new: currentLines)
            if !delta.isEmpty {
                // If it's a full redraw (no overlap), visually separate it.
                if lastLines.count > 0 && delta.count == currentLines.count {
                    print("\n--- redraw ---")
                }
                for line in delta {
                    print(line)
                }
                fflush(stdout)
            }
            lastLines = currentLines

            if let durationSec, Date().timeIntervalSince(startTs) >= Double(durationSec) {
                break
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
