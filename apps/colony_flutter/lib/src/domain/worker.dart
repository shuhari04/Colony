import 'building.dart';
import 'colony_ids.dart';

enum WorkerStatus { idle, routing, working, blocked, done }

class Worker {
  final ColonyId id;
  final ColonyId worldId;
  final AgentProvider provider;
  final ColonyId homeBuildingId;
  final ColonyId? assignedBuildingId;
  final ColonyId? sessionTaskId;
  final WorkerStatus status;
  final Map<String, Object?> metadata;

  const Worker({
    required this.id,
    required this.worldId,
    required this.provider,
    required this.homeBuildingId,
    this.assignedBuildingId,
    this.sessionTaskId,
    this.status = WorkerStatus.idle,
    this.metadata = const {},
  });

  Worker copyWith({
    ColonyId? id,
    ColonyId? worldId,
    AgentProvider? provider,
    ColonyId? homeBuildingId,
    ColonyId? assignedBuildingId,
    ColonyId? sessionTaskId,
    WorkerStatus? status,
    Map<String, Object?>? metadata,
  }) {
    return Worker(
      id: id ?? this.id,
      worldId: worldId ?? this.worldId,
      provider: provider ?? this.provider,
      homeBuildingId: homeBuildingId ?? this.homeBuildingId,
      assignedBuildingId: assignedBuildingId ?? this.assignedBuildingId,
      sessionTaskId: sessionTaskId ?? this.sessionTaskId,
      status: status ?? this.status,
      metadata: metadata ?? this.metadata,
    );
  }
}
