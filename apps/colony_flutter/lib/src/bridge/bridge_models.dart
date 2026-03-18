import 'dart:convert';

enum BridgeExecutionMode { balanced, quick, deep }

enum BridgeRole { user, assistant, status }

class BridgePairingPayload {
  final String? name;
  final String url;
  final String? token;
  final String? workspace;
  final String? bonjourType;

  const BridgePairingPayload({
    this.name,
    required this.url,
    this.token,
    this.workspace,
    this.bonjourType,
  });

  factory BridgePairingPayload.fromJson(Map<String, dynamic> json) {
    return BridgePairingPayload(
      name: json['name'] as String?,
      url: json['url'] as String? ?? '',
      token: json['token'] as String?,
      workspace: json['workspace'] as String?,
      bonjourType: json['bonjourType'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'url': url,
      'token': token,
      'workspace': workspace,
      'bonjourType': bonjourType,
    };
  }

  String toPrettyJson() {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(toJson());
  }
}

class BridgeChatMessage {
  final String id;
  final BridgeRole role;
  final String content;
  final String createdAt;
  final String? metadata;

  const BridgeChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.metadata,
  });

  factory BridgeChatMessage.fromJson(Map<String, dynamic> json) {
    return BridgeChatMessage(
      id: json['id'] as String? ?? '',
      role: _roleFromString(json['role'] as String? ?? 'status'),
      content: json['content'] as String? ?? '',
      createdAt: json['createdAt'] as String? ?? '',
      metadata: json['metadata'] as String?,
    );
  }

  static BridgeRole _roleFromString(String raw) {
    return switch (raw) {
      'user' => BridgeRole.user,
      'assistant' => BridgeRole.assistant,
      _ => BridgeRole.status,
    };
  }
}

class BridgeSession {
  final String id;
  final String workingDirectory;
  final BridgeExecutionMode executionMode;
  final String createdAt;
  final String updatedAt;
  final bool isRunning;
  final String? lastError;
  final List<BridgeChatMessage> messages;

  const BridgeSession({
    required this.id,
    required this.workingDirectory,
    required this.executionMode,
    required this.createdAt,
    required this.updatedAt,
    required this.isRunning,
    required this.lastError,
    required this.messages,
  });

  factory BridgeSession.fromJson(Map<String, dynamic> json) {
    return BridgeSession(
      id: json['id'] as String? ?? '',
      workingDirectory: json['workingDirectory'] as String? ?? '',
      executionMode: _executionModeFromString(json['executionMode'] as String? ?? 'balanced'),
      createdAt: json['createdAt'] as String? ?? '',
      updatedAt: json['updatedAt'] as String? ?? '',
      isRunning: json['isRunning'] as bool? ?? false,
      lastError: json['lastError'] as String?,
      messages: ((json['messages'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(BridgeChatMessage.fromJson)
          .toList(growable: false),
    );
  }
}

class BridgeServerInfo {
  final String name;
  final bool codexAvailable;
  final String defaultWorkingDirectory;

  const BridgeServerInfo({
    required this.name,
    required this.codexAvailable,
    required this.defaultWorkingDirectory,
  });

  factory BridgeServerInfo.fromJson(Map<String, dynamic> json) {
    return BridgeServerInfo(
      name: json['name'] as String? ?? '',
      codexAvailable: json['codexAvailable'] as bool? ?? false,
      defaultWorkingDirectory: json['defaultWorkingDirectory'] as String? ?? '',
    );
  }
}

class BridgeSnapshot {
  final BridgeSession session;
  final BridgeServerInfo server;

  const BridgeSnapshot({
    required this.session,
    required this.server,
  });

  factory BridgeSnapshot.fromJson(Map<String, dynamic> json) {
    return BridgeSnapshot(
      session: BridgeSession.fromJson(Map<String, dynamic>.from(json['session'] as Map? ?? const {})),
      server: BridgeServerInfo.fromJson(Map<String, dynamic>.from(json['server'] as Map? ?? const {})),
    );
  }
}

BridgeExecutionMode _executionModeFromString(String raw) {
  return switch (raw) {
    'quick' => BridgeExecutionMode.quick,
    'deep' => BridgeExecutionMode.deep,
    _ => BridgeExecutionMode.balanced,
  };
}

String bridgeExecutionModeName(BridgeExecutionMode mode) {
  return switch (mode) {
    BridgeExecutionMode.balanced => 'balanced',
    BridgeExecutionMode.quick => 'quick',
    BridgeExecutionMode.deep => 'deep',
  };
}

String bridgeExecutionModeTitle(BridgeExecutionMode mode) {
  return switch (mode) {
    BridgeExecutionMode.balanced => 'Balanced',
    BridgeExecutionMode.quick => 'Quick',
    BridgeExecutionMode.deep => 'Deep',
  };
}
