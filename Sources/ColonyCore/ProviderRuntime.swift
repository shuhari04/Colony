import Foundation

public protocol ProviderRuntime: Sendable {
    var id: ProviderID { get }
    var kind: SessionKind { get }
    var defaultModel: String? { get }
    var supportedModels: [String]? { get }

    func launchCommand(request: SessionCreateRequest, colonyBinaryPath: String) -> [String]
}

public struct ProviderRegistry: Sendable {
    private let runtimes: [ProviderID: ProviderRuntime]

    public init(runtimes: [ProviderRuntime] = [
        CodexProviderRuntime(),
        ClaudeProviderRuntime(),
        OpenClawProviderRuntime(),
        GenericProviderRuntime(),
    ]) {
        var storage: [ProviderID: ProviderRuntime] = [:]
        for runtime in runtimes {
            storage[runtime.id] = runtime
        }
        self.runtimes = storage
    }

    public func runtime(for provider: ProviderID) -> ProviderRuntime? {
        runtimes[provider]
    }

    public func providerSummaries(availableIDs: Set<String>) -> [ProviderSummary] {
        ProviderID.allCases
            .filter { $0 != .generic }
            .map { provider in
                let runtime = runtimes[provider]
                return ProviderSummary(
                    id: provider.rawValue,
                    displayName: provider.displayName,
                    available: availableIDs.contains(provider.rawValue),
                    defaultModel: runtime?.defaultModel,
                    supportedModels: runtime?.supportedModels
                )
            }
    }
}

public struct CodexProviderRuntime: ProviderRuntime {
    public let id: ProviderID = .codex
    public let kind: SessionKind = .codex
    public let defaultModel: String? = nil
    public let supportedModels: [String]? = nil

    public init() {}

    public func launchCommand(request: SessionCreateRequest, colonyBinaryPath: String) -> [String] {
        let model = request.model?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        switch request.target {
        case .local:
            var command = [colonyBinaryPath, "agent", "codex"]
            if let model {
                command.append(contentsOf: ["--model", model])
            }
            return command
        case .ssh:
            let wrapped = """
            set -euo pipefail
            MODEL=\(ShellEscape.joinSh([model ?? ""]))
            echo "[colony-agent] codex remote ready${MODEL:+ (model=$MODEL)}"
            while IFS= read -r line; do
              line="$(printf "%s" "$line" | tr -d '\\r')"
              [ -z "$line" ] && continue
              if [[ "$line" == /model\\ * ]]; then
                MODEL="${line#/model }"
                echo "[colony-agent] model set to $MODEL"
                continue
              fi
              echo "[colony-agent] >>> $line"
              CODEX_ARGS=(codex exec --json --skip-git-repo-check)
              if [[ -n "$MODEL" ]]; then
                CODEX_ARGS+=(-m "$MODEL")
              fi
              "${CODEX_ARGS[@]}" "$line" 2>&1
              echo "[colony-agent] <<< done"
            done
            """
            return ["/usr/bin/env", "bash", "-lc", wrapped]
        }
    }
}

public struct ClaudeProviderRuntime: ProviderRuntime {
    public let id: ProviderID = .claude
    public let kind: SessionKind = .claude
    public let defaultModel: String? = nil
    public let supportedModels: [String]? = nil

    public init() {}

    public func launchCommand(request: SessionCreateRequest, colonyBinaryPath: String) -> [String] {
        switch request.target {
        case .local:
            var command = [colonyBinaryPath, "agent", "claude"]
            if let model = request.model?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty {
                command.append(contentsOf: ["--model", model])
            }
            return command
        case .ssh:
            let wrapped = """
            set -euo pipefail
            echo "[colony-agent] claude remote ready"
            while IFS= read -r line; do
              line="$(printf "%s" "$line" | tr -d '\\r')"
              [ -z "$line" ] && continue
              if [[ "$line" == /model\\ * ]]; then
                MODEL="${line#/model }"
                echo "[colony-agent] model set to $MODEL"
                continue
              fi
              echo "[colony-agent] >>> $line"
              CLAUDE_ARGS=(claude -p --verbose --output-format=stream-json --include-partial-messages)
              if [[ -n "${MODEL:-}" ]]; then
                CLAUDE_ARGS+=(--model "$MODEL")
              fi
              "${CLAUDE_ARGS[@]}" "$line" 2>&1
              echo "[colony-agent] <<< done"
            done
            """
            return ["/usr/bin/env", "bash", "-lc", wrapped]
        }
    }
}

public struct OpenClawProviderRuntime: ProviderRuntime {
    public let id: ProviderID = .openclaw
    public let kind: SessionKind = .openclaw
    public let defaultModel: String? = nil
    public let supportedModels: [String]? = nil

    public init() {}

    public func launchCommand(request: SessionCreateRequest, colonyBinaryPath: String) -> [String] {
        let script = """
        set -euo pipefail
        AGENT_ID="$(openclaw agents list 2>/dev/null | awk '/^- /{print $2; exit}')"
        AGENT_ID="${AGENT_ID:-main}"
        echo "[colony-agent] openclaw ready (agent=$AGENT_ID)"
        while IFS= read -r line; do
          line="$(printf "%s" "$line" | tr -d '\\r')"
          [ -z "$line" ] && continue
          echo "[colony-agent] >>> $line"
          openclaw agent --local --agent "$AGENT_ID" --json -m "$line" 2>&1
          echo "[colony-agent] <<< done"
        done
        """
        switch request.target {
        case .local:
            return ["/bin/zsh", "-lc", "source ~/.zshrc >/dev/null 2>&1 || true; \(script)"]
        case .ssh:
            return ["/usr/bin/env", "bash", "-lc", script]
        }
    }
}

public struct GenericProviderRuntime: ProviderRuntime {
    public let id: ProviderID = .generic
    public let kind: SessionKind = .generic
    public let defaultModel: String? = nil
    public let supportedModels: [String]? = nil

    public init() {}

    public func launchCommand(request: SessionCreateRequest, colonyBinaryPath: String) -> [String] {
        ["/usr/bin/env", "bash", "-lc", "cat"]
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
