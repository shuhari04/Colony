import '../domain/colony_ids.dart';

class ColonyRuntimeState {
  final Map<ColonyId, List<String>> liveLogsBySessionTaskId;
  final Map<String, Object?> backendSnapshot;
  final String? lastError;
  final Map<String, Object?> metadata;

  const ColonyRuntimeState({
    this.liveLogsBySessionTaskId = const {},
    this.backendSnapshot = const {},
    this.lastError,
    this.metadata = const {},
  });

  ColonyRuntimeState copyWith({
    Map<ColonyId, List<String>>? liveLogsBySessionTaskId,
    Map<String, Object?>? backendSnapshot,
    String? lastError,
    Map<String, Object?>? metadata,
  }) {
    return ColonyRuntimeState(
      liveLogsBySessionTaskId: liveLogsBySessionTaskId ?? this.liveLogsBySessionTaskId,
      backendSnapshot: backendSnapshot ?? this.backendSnapshot,
      lastError: lastError ?? this.lastError,
      metadata: metadata ?? this.metadata,
    );
  }
}
