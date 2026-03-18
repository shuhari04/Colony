import 'colony_ids.dart';

enum ZoneStatus { idle, active, blocked, complete }

class ZoneBounds {
  final double x;
  final double y;
  final double width;
  final double height;

  const ZoneBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  ZoneBounds copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
  }) {
    return ZoneBounds(
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }
}

class Zone {
  final ColonyId id;
  final ColonyId worldId;
  final ColonyId? projectId;
  final String label;
  final ZoneBounds bounds;
  final ZoneStatus status;
  final Map<String, Object?> metadata;

  const Zone({
    required this.id,
    required this.worldId,
    this.projectId,
    required this.label,
    required this.bounds,
    this.status = ZoneStatus.idle,
    this.metadata = const {},
  });

  Zone copyWith({
    ColonyId? id,
    ColonyId? worldId,
    ColonyId? projectId,
    String? label,
    ZoneBounds? bounds,
    ZoneStatus? status,
    Map<String, Object?>? metadata,
  }) {
    return Zone(
      id: id ?? this.id,
      worldId: worldId ?? this.worldId,
      projectId: projectId ?? this.projectId,
      label: label ?? this.label,
      bounds: bounds ?? this.bounds,
      status: status ?? this.status,
      metadata: metadata ?? this.metadata,
    );
  }
}
