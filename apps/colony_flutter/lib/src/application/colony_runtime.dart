import '../domain/colony_ids.dart';
import '../infrastructure/colony_stream_event.dart';

class ColonyRuntimeState {
  final Map<ColonyId, List<String>> liveLogsBySessionTaskId;
  final Map<ColonyId, List<ColonyStreamEvent>> liveEventsBySessionTaskId;
  final Map<String, Object?> backendSnapshot;
  final String? lastError;
  final Map<String, Object?> metadata;

  const ColonyRuntimeState({
    this.liveLogsBySessionTaskId = const {},
    this.liveEventsBySessionTaskId = const {},
    this.backendSnapshot = const {},
    this.lastError,
    this.metadata = const {},
  });

  ColonyRuntimeState copyWith({
    Map<ColonyId, List<String>>? liveLogsBySessionTaskId,
    Map<ColonyId, List<ColonyStreamEvent>>? liveEventsBySessionTaskId,
    Map<String, Object?>? backendSnapshot,
    String? lastError,
    Map<String, Object?>? metadata,
  }) {
    return ColonyRuntimeState(
      liveLogsBySessionTaskId: liveLogsBySessionTaskId ?? this.liveLogsBySessionTaskId,
      liveEventsBySessionTaskId:
          liveEventsBySessionTaskId ?? this.liveEventsBySessionTaskId,
      backendSnapshot: backendSnapshot ?? this.backendSnapshot,
      lastError: lastError ?? this.lastError,
      metadata: metadata ?? this.metadata,
    );
  }
}
