import 'colony_ids.dart';

enum WorldKind { local, ssh, mobileMirror }

enum WorldConnectionState { disconnected, connecting, connected, degraded }

class World {
  final ColonyId id;
  final WorldKind kind;
  final String name;
  final WorldConnectionState connectionState;
  final Map<String, Object?> metadata;

  const World({
    required this.id,
    required this.kind,
    required this.name,
    this.connectionState = WorldConnectionState.disconnected,
    this.metadata = const {},
  });

  World copyWith({
    ColonyId? id,
    WorldKind? kind,
    String? name,
    WorldConnectionState? connectionState,
    Map<String, Object?>? metadata,
  }) {
    return World(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      connectionState: connectionState ?? this.connectionState,
      metadata: metadata ?? this.metadata,
    );
  }
}
