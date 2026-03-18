import 'colony_ids.dart';

enum BuildingType { townHall, agentHut, projectSite, portal, bridge, utility }

enum BuildingStatus { locked, available, active, blocked, offline }

enum AgentProvider { none, codex, claude, openclaw, other }

class WorldPosition {
  final double x;
  final double y;
  final double z;

  const WorldPosition({
    required this.x,
    required this.y,
    this.z = 0,
  });

  WorldPosition copyWith({
    double? x,
    double? y,
    double? z,
  }) {
    return WorldPosition(
      x: x ?? this.x,
      y: y ?? this.y,
      z: z ?? this.z,
    );
  }
}

class Building {
  final ColonyId id;
  final ColonyId worldId;
  final ColonyId? zoneId;
  final BuildingType type;
  final String name;
  final WorldPosition position;
  final int level;
  final BuildingStatus status;
  final AgentProvider provider;
  final Map<String, Object?> metadata;

  const Building({
    required this.id,
    required this.worldId,
    this.zoneId,
    required this.type,
    required this.name,
    required this.position,
    this.level = 1,
    this.status = BuildingStatus.available,
    this.provider = AgentProvider.none,
    this.metadata = const {},
  });

  Building copyWith({
    ColonyId? id,
    ColonyId? worldId,
    ColonyId? zoneId,
    BuildingType? type,
    String? name,
    WorldPosition? position,
    int? level,
    BuildingStatus? status,
    AgentProvider? provider,
    Map<String, Object?>? metadata,
  }) {
    return Building(
      id: id ?? this.id,
      worldId: worldId ?? this.worldId,
      zoneId: zoneId ?? this.zoneId,
      type: type ?? this.type,
      name: name ?? this.name,
      position: position ?? this.position,
      level: level ?? this.level,
      status: status ?? this.status,
      provider: provider ?? this.provider,
      metadata: metadata ?? this.metadata,
    );
  }
}
