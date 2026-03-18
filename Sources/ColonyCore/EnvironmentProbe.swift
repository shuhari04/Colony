import Foundation

public enum EnvironmentProbeError: Error, CustomStringConvertible {
    case commandFailed(String)

    public var description: String {
        switch self {
        case let .commandFailed(msg):
            return "Environment probe failed: \(msg)"
        }
    }
}

public struct EnvironmentProbe {
    private let shell: Shell

    public init(shell: Shell = Shell()) {
        self.shell = shell
    }

    public func availableAgents(target: Target) throws -> [String] {
        let script = """
        set -e
        if command -v codex >/dev/null 2>&1; then echo codex; fi
        if command -v claude >/dev/null 2>&1; then echo claude; fi
        if command -v openclaw >/dev/null 2>&1 || command -v opencode >/dev/null 2>&1; then echo openclaw; fi
        """

        let res = try runShell(target: target, script: script)
        guard res.exitCode == 0 else {
            throw EnvironmentProbeError.commandFailed(res.stderr.isEmpty ? res.stdout : res.stderr)
        }

        var seen = Set<String>()
        return res.stdout
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    private func runShell(target: Target, script: String) throws -> ExecResult {
        switch target {
        case .local:
            return try shell.run(["/usr/bin/env", "bash", "-lc", script])
        case let .ssh(host):
            let remote = ShellEscape.joinSh(["bash", "-lc", script])
            let env = ProcessInfo.processInfo.environment
            if let pw = env["COLONY_SSH_PASSWORD"], !pw.isEmpty {
                let check = try? shell.run(["/usr/bin/env", "bash", "-lc", "command -v sshpass >/dev/null 2>&1"])
                if check?.exitCode == 0 {
                    return try shell.run([
                        "/usr/bin/env", "sshpass", "-p", pw,
                        "ssh",
                        "-o", "StrictHostKeyChecking=accept-new",
                        "-T", host, remote,
                    ])
                }
            }
            return try shell.run([
                "/usr/bin/ssh",
                "-o", "StrictHostKeyChecking=accept-new",
                "-T", host, remote,
            ])
        }
    }
}
