import Foundation

public struct ExecResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public var succeeded: Bool { exitCode == 0 }
}

public enum ShellError: Error, CustomStringConvertible {
    case commandFailed(cmd: [String], exitCode: Int32, stderr: String)
    case outputDecodingFailed

    public var description: String {
        switch self {
        case let .commandFailed(cmd, exitCode, stderr):
            return "Command failed (exit \(exitCode)): \(cmd.joined(separator: " "))\n\(stderr)"
        case .outputDecodingFailed:
            return "Failed to decode process output as UTF-8"
        }
    }
}

public final class Shell {
    public init() {}

    public func run(_ cmd: [String], env: [String: String] = [:], cwd: URL? = nil) throws -> ExecResult {
        precondition(!cmd.isEmpty)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: cmd[0])
        p.arguments = Array(cmd.dropFirst())

        var mergedEnv = ProcessInfo.processInfo.environment
        for (k, v) in env { mergedEnv[k] = v }
        p.environment = mergedEnv
        p.currentDirectoryURL = cwd

        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err

        try p.run()
        p.waitUntilExit()

        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()

        guard let outStr = String(data: outData, encoding: .utf8),
              let errStr = String(data: errData, encoding: .utf8) else {
            throw ShellError.outputDecodingFailed
        }

        return ExecResult(exitCode: p.terminationStatus, stdout: outStr, stderr: errStr)
    }
}
