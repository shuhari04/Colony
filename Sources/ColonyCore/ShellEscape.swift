import Foundation

public enum ShellEscape {
    // POSIX shell single-quote escaping: ' -> '\''
    public static func shQuote(_ s: String) -> String {
        if s.isEmpty { return "''" }
        if !s.contains("'") { return "'\(s)'" }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func joinSh(_ args: [String]) -> String {
        args.map(shQuote).joined(separator: " ")
    }
}
