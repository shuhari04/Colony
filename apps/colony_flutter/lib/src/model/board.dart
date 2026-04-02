import 'dart:convert';

import '../domain/building.dart';
import '../domain/worker.dart';

enum BoardBuildingKind {
  buildingWorkspace,
  buildingAltA,
  buildingAltB,
  server,
  kanban,
  machine,
  workflowLine,
}

enum BoardOrientation { l, r }

class BoardInventoryItem {
  final String id;
  final String label;
  final String description;
  final BoardBuildingKind kind;
  final AgentProvider provider;

  const BoardInventoryItem({
    required this.id,
    required this.label,
    required this.description,
    required this.kind,
    this.provider = AgentProvider.none,
  });
}

class GridPoint {
  final int x;
  final int y;

  const GridPoint({required this.x, required this.y});

  GridPoint copyWith({int? x, int? y}) {
    return GridPoint(x: x ?? this.x, y: y ?? this.y);
  }

  Map<String, Object?> toJson() => {'x': x, 'y': y};

  factory GridPoint.fromJson(Map<String, Object?> json) {
    return GridPoint(
      x: (json['x'] as num?)?.toInt() ?? 0,
      y: (json['y'] as num?)?.toInt() ?? 0,
    );
  }
}

class ServerConfig {
  final String alias;
  final String host;
  final String password;
  final String status;
  final String? error;

  const ServerConfig({
    required this.alias,
    required this.host,
    this.password = '',
    this.status = 'idle',
    this.error,
  });

  ServerConfig copyWith({
    String? alias,
    String? host,
    String? password,
    String? status,
    String? error,
  }) {
    return ServerConfig(
      alias: alias ?? this.alias,
      host: host ?? this.host,
      password: password ?? this.password,
      status: status ?? this.status,
      error: error ?? this.error,
    );
  }

  Map<String, Object?> toJson() => {
    'alias': alias,
    'host': host,
    'password': password,
    'status': status,
    'error': error,
  };

  factory ServerConfig.fromJson(Map<String, Object?> json) {
    return ServerConfig(
      alias: '${json['alias'] ?? ''}',
      host: '${json['host'] ?? ''}',
      password: '${json['password'] ?? ''}',
      status: '${json['status'] ?? 'idle'}',
      error: json['error'] as String?,
    );
  }
}

class PlacedBuilding {
  final String id;
  final BoardBuildingKind kind;
  final GridPoint origin;
  final BoardOrientation orientation;
  final AgentProvider provider;
  final String? workspacePath;
  final ServerConfig? serverConfig;
  final bool finishVisible;

  const PlacedBuilding({
    required this.id,
    required this.kind,
    required this.origin,
    this.orientation = BoardOrientation.l,
    this.provider = AgentProvider.none,
    this.workspacePath,
    this.serverConfig,
    this.finishVisible = false,
  });

  PlacedBuilding copyWith({
    String? id,
    BoardBuildingKind? kind,
    GridPoint? origin,
    BoardOrientation? orientation,
    AgentProvider? provider,
    String? workspacePath,
    bool clearWorkspacePath = false,
    ServerConfig? serverConfig,
    bool clearServerConfig = false,
    bool? finishVisible,
  }) {
    return PlacedBuilding(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      origin: origin ?? this.origin,
      orientation: orientation ?? this.orientation,
      provider: provider ?? this.provider,
      workspacePath: clearWorkspacePath ? null : (workspacePath ?? this.workspacePath),
      serverConfig: clearServerConfig ? null : (serverConfig ?? this.serverConfig),
      finishVisible: finishVisible ?? this.finishVisible,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'origin': origin.toJson(),
    'orientation': orientation.name,
    'provider': provider.name,
    'workspacePath': workspacePath,
    'serverConfig': serverConfig?.toJson(),
  };

  factory PlacedBuilding.fromJson(Map<String, Object?> json) {
    final origin = json['origin'];
    final serverConfig = json['serverConfig'];
    return PlacedBuilding(
      id: '${json['id'] ?? ''}',
      kind: BoardBuildingKind.values.byName(
        '${json['kind'] ?? BoardBuildingKind.buildingWorkspace.name}',
      ),
      origin: origin is Map
          ? GridPoint.fromJson(Map<String, Object?>.from(origin))
          : const GridPoint(x: 0, y: 0),
      orientation: BoardOrientation.values.byName(
        '${json['orientation'] ?? BoardOrientation.l.name}',
      ),
      provider: AgentProvider.values.byName(
        '${json['provider'] ?? AgentProvider.none.name}',
      ),
      workspacePath: json['workspacePath'] as String?,
      serverConfig: serverConfig is Map
          ? ServerConfig.fromJson(Map<String, Object?>.from(serverConfig))
          : null,
    );
  }
}

class PlacedWorker {
  final String id;
  final AgentProvider provider;
  final String homeBuildingId;
  final String? assignedBuildingId;
  final String? sessionAddress;
  final WorkerStatus status;

  const PlacedWorker({
    required this.id,
    required this.provider,
    required this.homeBuildingId,
    this.assignedBuildingId,
    this.sessionAddress,
    this.status = WorkerStatus.idle,
  });

  PlacedWorker copyWith({
    String? id,
    AgentProvider? provider,
    String? homeBuildingId,
    String? assignedBuildingId,
    bool clearAssignedBuildingId = false,
    String? sessionAddress,
    bool clearSessionAddress = false,
    WorkerStatus? status,
  }) {
    return PlacedWorker(
      id: id ?? this.id,
      provider: provider ?? this.provider,
      homeBuildingId: homeBuildingId ?? this.homeBuildingId,
      assignedBuildingId: clearAssignedBuildingId
          ? null
          : (assignedBuildingId ?? this.assignedBuildingId),
      sessionAddress: clearSessionAddress ? null : (sessionAddress ?? this.sessionAddress),
      status: status ?? this.status,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'provider': provider.name,
    'homeBuildingId': homeBuildingId,
    'assignedBuildingId': assignedBuildingId,
    'sessionAddress': sessionAddress,
    'status': status.name,
  };

  factory PlacedWorker.fromJson(Map<String, Object?> json) {
    return PlacedWorker(
      id: '${json['id'] ?? ''}',
      provider: AgentProvider.values.byName(
        '${json['provider'] ?? AgentProvider.none.name}',
      ),
      homeBuildingId: '${json['homeBuildingId'] ?? ''}',
      assignedBuildingId: json['assignedBuildingId'] as String?,
      sessionAddress: json['sessionAddress'] as String?,
      status: WorkerStatus.values.byName(
        '${json['status'] ?? WorkerStatus.idle.name}',
      ),
    );
  }
}

class BoardSnapshot {
  final List<PlacedBuilding> buildings;
  final List<PlacedWorker> workers;
  final String? selectedBuildingId;
  final String? selectedWorkerId;

  const BoardSnapshot({
    this.buildings = const [],
    this.workers = const [],
    this.selectedBuildingId,
    this.selectedWorkerId,
  });

  BoardSnapshot copyWith({
    List<PlacedBuilding>? buildings,
    List<PlacedWorker>? workers,
    String? selectedBuildingId,
    bool clearSelectedBuildingId = false,
    String? selectedWorkerId,
    bool clearSelectedWorkerId = false,
  }) {
    return BoardSnapshot(
      buildings: buildings ?? this.buildings,
      workers: workers ?? this.workers,
      selectedBuildingId: clearSelectedBuildingId
          ? null
          : (selectedBuildingId ?? this.selectedBuildingId),
      selectedWorkerId: clearSelectedWorkerId
          ? null
          : (selectedWorkerId ?? this.selectedWorkerId),
    );
  }

  String encode() {
    return jsonEncode({
      'buildings': buildings.map((building) => building.toJson()).toList(growable: false),
      'workers': workers.map((worker) => worker.toJson()).toList(growable: false),
      'selectedBuildingId': selectedBuildingId,
      'selectedWorkerId': selectedWorkerId,
    });
  }

  factory BoardSnapshot.decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return const BoardSnapshot();
    }
    final buildings = decoded['buildings'] as List? ?? const [];
    final workers = decoded['workers'] as List? ?? const [];
    return BoardSnapshot(
      buildings: buildings
          .whereType<Map>()
          .map((item) => PlacedBuilding.fromJson(Map<String, Object?>.from(item)))
          .toList(growable: false),
      workers: workers
          .whereType<Map>()
          .map((item) => PlacedWorker.fromJson(Map<String, Object?>.from(item)))
          .toList(growable: false),
      selectedBuildingId: decoded['selectedBuildingId'] as String?,
      selectedWorkerId: decoded['selectedWorkerId'] as String?,
    );
  }
}
