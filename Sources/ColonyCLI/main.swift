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
          colony recv   <@addr> [--lines N]
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
