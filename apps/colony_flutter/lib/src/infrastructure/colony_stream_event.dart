import 'dart:convert';

enum ColonyStreamEventKind {
  userMessage,
  assistantMessage,
  systemEvent,
  toolCall,
  warning,
  error,
  processExit,
  raw,
}

class ColonyStreamEvent {
  final ColonyStreamEventKind kind;
  final String text;
  final String? label;
  final String? tone;
  final String rawLine;
  final Map<String, Object?> metadata;

  const ColonyStreamEvent({
    required this.kind,
    required this.text,
    required this.rawLine,
    this.label,
    this.tone,
    this.metadata = const {},
  });

  factory ColonyStreamEvent.fromLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return ColonyStreamEvent(
        kind: ColonyStreamEventKind.raw,
        text: '',
        rawLine: line,
      );
    }

    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) {
          final kind = _kindFromWire('${decoded['kind'] ?? ''}');
          if (kind != null) {
            return ColonyStreamEvent(
              kind: kind,
              text: '${decoded['text'] ?? ''}'.trim(),
              rawLine: line,
              label: (decoded['label'] as String?)?.trim(),
              tone: (decoded['tone'] as String?)?.trim(),
              metadata: Map<String, Object?>.from(
                decoded['metadata'] as Map? ?? const {},
              ),
            );
          }
        }
      } catch (_) {}
    }

    return ColonyStreamEvent(
      kind: ColonyStreamEventKind.raw,
      text: trimmed,
      rawLine: line,
    );
  }

  static ColonyStreamEvent diagnostic(
    String text, {
    required String rawLine,
    bool error = false,
  }) {
    return ColonyStreamEvent(
      kind: error ? ColonyStreamEventKind.error : ColonyStreamEventKind.warning,
      text: text,
      rawLine: rawLine,
      tone: error ? 'error' : 'warning',
    );
  }

  static ColonyStreamEvent processExit(int code) {
    return ColonyStreamEvent(
      kind: ColonyStreamEventKind.processExit,
      text: 'Stream exited ($code)',
      rawLine: '[process exited $code]',
      tone: code == 0 ? 'info' : 'error',
      metadata: {'exitCode': code},
    );
  }

  static ColonyStreamEventKind? _kindFromWire(String raw) {
    return switch (raw.trim()) {
      'user_message' => ColonyStreamEventKind.userMessage,
      'assistant_message' => ColonyStreamEventKind.assistantMessage,
      'system_event' => ColonyStreamEventKind.systemEvent,
      'tool_call' => ColonyStreamEventKind.toolCall,
      'warning' => ColonyStreamEventKind.warning,
      'error' => ColonyStreamEventKind.error,
      'process_exit' => ColonyStreamEventKind.processExit,
      'raw' => ColonyStreamEventKind.raw,
      _ => null,
    };
  }
}
