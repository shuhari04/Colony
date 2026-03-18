import 'colony_ids.dart';

enum SessionBackend { localTmux, sshTmux, relay, other }

enum SessionTaskStatus { queued, running, waiting, blocked, done, failed }

class SessionProgress {
  final double? fraction;
  final String? label;

  const SessionProgress({
    this.fraction,
    this.label,
  });

  SessionProgress copyWith({
    double? fraction,
    String? label,
  }) {
    return SessionProgress(
      fraction: fraction ?? this.fraction,
      label: label ?? this.label,
    );
  }
}

class Artifact {
  final ColonyId id;
  final String kind;
  final String name;
  final String? uri;
  final Map<String, Object?> metadata;

  const Artifact({
    required this.id,
    required this.kind,
    required this.name,
    this.uri,
    this.metadata = const {},
  });

  Artifact copyWith({
    ColonyId? id,
    String? kind,
    String? name,
    String? uri,
    Map<String, Object?>? metadata,
  }) {
    return Artifact(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      uri: uri ?? this.uri,
      metadata: metadata ?? this.metadata,
    );
  }
}

class SessionTask {
  final ColonyId id;
  final ColonyId workerId;
  final String address;
  final SessionBackend backend;
  final String title;
  final ColonyId? promptThreadId;
  final SessionProgress progress;
  final SessionTaskStatus status;
  final List<Artifact> artifacts;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final Map<String, Object?> metadata;

  const SessionTask({
    required this.id,
    required this.workerId,
    required this.address,
    required this.backend,
    required this.title,
    this.promptThreadId,
    this.progress = const SessionProgress(),
    this.status = SessionTaskStatus.queued,
    this.artifacts = const [],
    this.startedAt,
    this.endedAt,
    this.metadata = const {},
  });

  SessionTask copyWith({
    ColonyId? id,
    ColonyId? workerId,
    String? address,
    SessionBackend? backend,
    String? title,
    ColonyId? promptThreadId,
    SessionProgress? progress,
    SessionTaskStatus? status,
    List<Artifact>? artifacts,
    DateTime? startedAt,
    DateTime? endedAt,
    Map<String, Object?>? metadata,
  }) {
    return SessionTask(
      id: id ?? this.id,
      workerId: workerId ?? this.workerId,
      address: address ?? this.address,
      backend: backend ?? this.backend,
      title: title ?? this.title,
      promptThreadId: promptThreadId ?? this.promptThreadId,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      artifacts: artifacts ?? this.artifacts,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      metadata: metadata ?? this.metadata,
    );
  }
}
