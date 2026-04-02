import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import '../application/colony_application.dart';
import '../domain/colony_domain.dart';
import '../infrastructure/board_snapshot_store.dart';
import '../infrastructure/infrastructure.dart';
import '../model/board.dart';
import '../model/entities.dart';

enum SelectionKind { none, building, session }

class Selection {
  final SelectionKind kind;
  final String id;

  const Selection._(this.kind, this.id);

  const Selection.none() : this._(SelectionKind.none, '');
  const Selection.building(String id) : this._(SelectionKind.building, id);
  const Selection.session(String id) : this._(SelectionKind.session, id);
}

class AppState extends ChangeNotifier {
  AppState({
    ColonyStore? store,
    ColonyBinaryLocator? binaryLocator,
    ColonyCommandAdapter? commandAdapter,
    BoardSnapshotStore? boardStore,
  }) : store = store ?? ColonyStore(),
       _binaryLocator = binaryLocator ?? const ColonyBinaryLocator(),
       _cli = commandAdapter,
       _boardStore = boardStore ?? const BoardSnapshotStore() {
    this.store.addListener(_onStoreChanged);
  }

  static const int boardDimension = 20;

  static const List<BoardInventoryItem> inventoryItems = [
    BoardInventoryItem(
      id: 'workspace',
      label: 'Workspace Building',
      description: 'Bind a local project folder.',
      kind: BoardBuildingKind.buildingWorkspace,
    ),
    BoardInventoryItem(
      id: 'building_a',
      label: 'Building A',
      description: 'Single-tile structure.',
      kind: BoardBuildingKind.buildingAltA,
    ),
    BoardInventoryItem(
      id: 'building_b',
      label: 'Building B',
      description: 'Single-tile structure.',
      kind: BoardBuildingKind.buildingAltB,
    ),
    BoardInventoryItem(
      id: 'server',
      label: 'Server',
      description: 'Configure a remote host.',
      kind: BoardBuildingKind.server,
    ),
    BoardInventoryItem(
      id: 'kanban',
      label: 'Kanban',
      description: 'Visual work board placeholder.',
      kind: BoardBuildingKind.kanban,
    ),
    BoardInventoryItem(
      id: 'machine_codex',
      label: 'Machine / Codex',
      description: 'Codex worker machine.',
      kind: BoardBuildingKind.machine,
      provider: AgentProvider.codex,
    ),
    BoardInventoryItem(
      id: 'machine_claude',
      label: 'Machine / Claude',
      description: 'Claude worker machine.',
      kind: BoardBuildingKind.machine,
      provider: AgentProvider.claude,
    ),
    BoardInventoryItem(
      id: 'machine_openclaw',
      label: 'Machine / OpenClaw',
      description: 'OpenClaw worker machine.',
      kind: BoardBuildingKind.machine,
      provider: AgentProvider.openclaw,
    ),
    BoardInventoryItem(
      id: 'workflow_line',
      label: 'Workflow Line',
      description: 'Five-tile workflow placeholder.',
      kind: BoardBuildingKind.workflowLine,
    ),
  ];

  final ColonyStore store;
  final ColonyBinaryLocator _binaryLocator;
  final BoardSnapshotStore _boardStore;
  ColonyCommandAdapter? _cli;

  final List<Project> projects = [];
  final List<Session> sessions = [];
  final Map<String, String> _sshPasswordByHost = {};
  final Map<String, List<AgentProvider>> _providersByNode = {};
  final Map<String, List<String>> _sessionLogs = {};
  final Map<String, ColonyLogStream> _logStreamsByTaskId = {};
  final Map<String, String> _sessionTaskIdByAddress = {};
  final Map<String, SessionKind> _sessionKindHintsByAddress = {};
  final Map<String, String> _preferredHomeBuildingByAddress = {};

  List<PlacedBuilding> _boardBuildings = const [];
  List<PlacedWorker> _boardWorkers = const [];

  Selection selection = const Selection.none();
  bool buildMode = false;
  Map<String, dynamic>? codexRateLimit;
  String? lastError;

  String? _draftBuildingId;
  bool _draftIsNew = false;
  String? _assigningWorkerId;

  List<PlacedBuilding> get boardBuildings =>
      List<PlacedBuilding>.unmodifiable(_boardBuildings);
  List<PlacedWorker> get boardWorkers =>
      List<PlacedWorker>.unmodifiable(_boardWorkers);
  String? get draftBuildingId => _draftBuildingId;
  String? get assigningWorkerId => _assigningWorkerId;
  bool get isEditingBoard => _draftBuildingId != null;

  Future<void> bootstrap() async {
    store.bootstrapLocalWorld();
    if (projects.isEmpty) {
      projects.add(
        Project(id: 'p_local', nodeId: 'local', name: 'Local', x: 0, y: 0),
      );
    }
    final bin = await _binaryLocator.discover();
    _cli ??= ProcessColonyCommandAdapter(bin ?? 'colony');
    final snapshot = await _boardStore.load();
    _boardBuildings = snapshot.buildings;
    _boardWorkers = const [];
    await refresh();
  }

  Future<void> refresh() async {
    lastError = null;
    notifyListeners();
    try {
      await _refreshProviders();
      await _refreshSessions();
      await _refreshRateLimit();
    } catch (e) {
      lastError = '$e';
      store.patchRuntime(lastError: lastError);
    }
    notifyListeners();
  }

  Future<void> _refreshProviders() async {
    final cli = _cli;
    if (cli == null) return;

    try {
      final listed = await cli.listProviders(target: 'local');
      _providersByNode['local'] = _normalizedProviders(
        listed
            .map(_providerFromName)
            .whereType<AgentProvider>()
            .toList(growable: false),
        target: 'local',
      );
    } catch (_) {
      _providersByNode['local'] = _fallbackProvidersForTarget('local');
    }
  }

  Future<void> _refreshSessions() async {
    final cli = _cli;
    if (cli == null) return;

    final addresses = await cli.listSessions(target: 'local');
    sessions
      ..clear()
      ..addAll(_sessionsFromAddresses(addresses));
    _syncSessionTasks(addresses);
    _pruneStreamsForMissingTasks();
  }

  Future<void> _refreshRateLimit() async {
    final cli = _cli;
    if (cli == null) return;
    codexRateLimit = await cli.codexRateLimitJson();
    store.patchRuntime(
      backendSnapshot: Map<String, Object?>.from(codexRateLimit ?? const {}),
      lastError: lastError,
    );
  }

  void _syncSessionTasks(List<String> addresses) {
    final activeTaskIds = <String>{};
    final activeWorkerIds = <String>{};
    final currentWorkersByAddress = {
      for (final worker in _boardWorkers)
        if ((worker.sessionAddress ?? '').isNotEmpty)
          worker.sessionAddress!: worker,
    };
    final machineIdsByProvider = <AgentProvider, List<String>>{};
    for (final building in _boardBuildings.where(
      (item) => item.kind == BoardBuildingKind.machine,
    )) {
      machineIdsByProvider
          .putIfAbsent(building.provider, () => <String>[])
          .add(building.id);
    }
    for (final ids in machineIdsByProvider.values) {
      ids.sort();
    }
    final usageByMachineId = <String, int>{};
    final nextBoardWorkers = <PlacedWorker>[];

    for (final address in addresses) {
      final parsed = _parseAddress(address);
      if (parsed == null) continue;
      final (_, sessionName) = parsed;
      final taskId = _sessionTaskIdByAddress[address] ??= 'task:$address';
      activeTaskIds.add(taskId);

      final kind =
          _sessionKindHintsByAddress[address] ?? _inferKind(sessionName);
      final provider = _providerForSessionKind(kind);
      final machineId = _resolveHomeMachineId(
        address: address,
        provider: provider,
        currentWorkersByAddress: currentWorkersByAddress,
        machineIdsByProvider: machineIdsByProvider,
        usageByMachineId: usageByMachineId,
      );

      final existingWorker = currentWorkersByAddress[address];
      final effectiveAssignedBuildingId =
          existingWorker?.assignedBuildingId != null &&
              boardBuildingById(existingWorker!.assignedBuildingId!) != null
          ? existingWorker.assignedBuildingId
          : null;

      if (machineId != null) {
        final workerId = existingWorker?.id ?? 'worker:$address';
        activeWorkerIds.add(workerId);
        final worker =
            (existingWorker ??
                    PlacedWorker(
                      id: workerId,
                      provider: provider,
                      homeBuildingId: machineId,
                      sessionAddress: address,
                    ))
                .copyWith(
                  provider: provider,
                  homeBuildingId: machineId,
                  sessionAddress: address,
                  assignedBuildingId: effectiveAssignedBuildingId,
                  clearAssignedBuildingId: effectiveAssignedBuildingId == null,
                  status: effectiveAssignedBuildingId == null
                      ? WorkerStatus.idle
                      : WorkerStatus.working,
                );
        nextBoardWorkers.add(worker);

        store.upsertWorker(
          Worker(
            id: workerId,
            worldId: 'local',
            provider: provider,
            homeBuildingId: machineId,
            assignedBuildingId: effectiveAssignedBuildingId,
            sessionTaskId: taskId,
            status: effectiveAssignedBuildingId == null
                ? WorkerStatus.idle
                : WorkerStatus.working,
            metadata: {'sessionAddress': address},
          ),
        );
      }

      final currentTask = store.sessionTasksById[taskId];
      store.upsertSessionTask(
        (currentTask ??
                SessionTask(
                  id: taskId,
                  workerId: existingWorker?.id ?? 'worker:$address',
                  address: address,
                  backend: SessionBackend.localTmux,
                  title: sessionName,
                ))
            .copyWith(
              workerId: existingWorker?.id ?? 'worker:$address',
              address: address,
              backend: SessionBackend.localTmux,
              title: sessionName,
              status: SessionTaskStatus.running,
              startedAt: currentTask?.startedAt ?? DateTime.now(),
              metadata: {
                ...(currentTask?.metadata ?? const {}),
                'nodeId': 'local',
                'sessionKind': kind.name,
                ...?(machineId == null ? null : {'homeBuildingId': machineId}),
                ...?(effectiveAssignedBuildingId == null
                    ? null
                    : {'assignedBuildingId': effectiveAssignedBuildingId}),
              },
            ),
      );
    }

    _boardWorkers = nextBoardWorkers;

    final staleTaskIds = store.sessionTasksById.keys
        .where((taskId) => !activeTaskIds.contains(taskId))
        .toList();
    for (final taskId in staleTaskIds) {
      final task = store.sessionTasksById.remove(taskId);
      if (task != null) {
        store.workersById.remove(task.workerId);
      }
      _logStreamsByTaskId.remove(taskId)?.stop();
    }

    final activeLogs = Map<String, List<String>>.from(
      store.runtime.liveLogsBySessionTaskId,
    );
    final activeEvents = Map<String, List<ColonyStreamEvent>>.from(
      store.runtime.liveEventsBySessionTaskId,
    );
    activeLogs.removeWhere((taskId, _) => !activeTaskIds.contains(taskId));
    activeEvents.removeWhere((taskId, _) => !activeTaskIds.contains(taskId));
    _sessionTaskIdByAddress.removeWhere(
      (address, taskId) => !activeTaskIds.contains(taskId),
    );
    _sessionLogs.removeWhere((address, _) => !addresses.contains(address));
    store.patchRuntime(
      liveLogsBySessionTaskId: activeLogs,
      liveEventsBySessionTaskId: activeEvents,
      lastError: lastError,
    );
  }

  String? _resolveHomeMachineId({
    required String address,
    required AgentProvider provider,
    required Map<String, PlacedWorker> currentWorkersByAddress,
    required Map<AgentProvider, List<String>> machineIdsByProvider,
    required Map<String, int> usageByMachineId,
  }) {
    final preferredId = _preferredHomeBuildingByAddress[address];
    if (preferredId != null) {
      final preferred = boardBuildingById(preferredId);
      if (preferred != null &&
          preferred.kind == BoardBuildingKind.machine &&
          preferred.provider == provider) {
        usageByMachineId[preferredId] =
            (usageByMachineId[preferredId] ?? 0) + 1;
        return preferredId;
      }
    }

    final existingWorker = currentWorkersByAddress[address];
    if (existingWorker != null &&
        boardBuildingById(existingWorker.homeBuildingId) != null) {
      usageByMachineId[existingWorker.homeBuildingId] =
          (usageByMachineId[existingWorker.homeBuildingId] ?? 0) + 1;
      return existingWorker.homeBuildingId;
    }

    final candidates = machineIdsByProvider[provider] ?? const <String>[];
    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      final usageA = usageByMachineId[a] ?? 0;
      final usageB = usageByMachineId[b] ?? 0;
      if (usageA != usageB) return usageA.compareTo(usageB);
      return a.compareTo(b);
    });
    final chosen = candidates.first;
    usageByMachineId[chosen] = (usageByMachineId[chosen] ?? 0) + 1;
    return chosen;
  }

  void _onStoreChanged() {
    lastError = store.runtime.lastError;
    final snapshot = store.runtime.backendSnapshot;
    if (snapshot.isNotEmpty) {
      codexRateLimit = Map<String, dynamic>.from(snapshot);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    store.removeListener(_onStoreChanged);
    _stopStreaming();
    super.dispose();
  }

  Project? projectById(String id) =>
      projects.where((project) => project.id == id).firstOrNull;

  Session? sessionByAddress(String address) =>
      sessions.where((session) => session.address == address).firstOrNull;

  PlacedBuilding? boardBuildingById(String id) =>
      _boardBuildings.where((building) => building.id == id).firstOrNull;

  PlacedWorker? boardWorkerById(String id) =>
      _boardWorkers.where((worker) => worker.id == id).firstOrNull;

  PlacedWorker? boardWorkerForAddress(String address) => _boardWorkers
      .where((worker) => worker.sessionAddress == address)
      .firstOrNull;

  List<PlacedWorker> workersForBuilding(String buildingId) {
    return _boardWorkers
        .where(
          (worker) =>
              worker.homeBuildingId == buildingId ||
              worker.assignedBuildingId == buildingId,
        )
        .toList(growable: false);
  }

  List<PlacedWorker> workersOwnedByMachine(String buildingId) {
    return _boardWorkers
        .where((worker) => worker.homeBuildingId == buildingId)
        .toList(growable: false);
  }

  List<String> logsFor(String address) {
    final taskId = _taskIdForAddress(address);
    if (taskId != null) {
      return store.runtime.liveLogsBySessionTaskId[taskId] ?? const [];
    }
    return _sessionLogs[address] ?? const [];
  }

  List<ColonyStreamEvent> eventsFor(String address) {
    final taskId = _taskIdForAddress(address);
    if (taskId != null) {
      return store.runtime.liveEventsBySessionTaskId[taskId] ?? const [];
    }
    return const [];
  }

  String resolveAddressShorthand(String raw) {
    if (!raw.startsWith('@')) return raw;
    if (raw.contains(':')) return raw;
    final needle = raw.substring(1).toLowerCase();
    if (needle.isEmpty) return raw;

    final exact = sessions.where((session) {
      return session.name.toLowerCase() == needle ||
          session.address.toLowerCase() == raw.toLowerCase();
    }).toList();
    if (exact.isNotEmpty) return exact.first.address;

    final fuzzy = sessions
        .where((session) => session.address.toLowerCase().contains(needle))
        .toList();
    if (fuzzy.isNotEmpty) return fuzzy.first.address;

    return '@local:$needle';
  }

  Future<void> sendToSelection(String text, {String? addressOverride}) async {
    final cli = _cli;
    if (cli == null) return;

    final addrRaw =
        addressOverride ??
        (selection.kind == SelectionKind.session ? selection.id : null);
    final addr = addrRaw == null ? null : resolveAddressShorthand(addrRaw);
    if (addr == null || addr.isEmpty) {
      lastError = 'No worker selected';
      store.patchRuntime(lastError: lastError);
      notifyListeners();
      return;
    }

    lastError = null;
    store.patchRuntime(lastError: null);
    notifyListeners();
    try {
      await cli.send(addr, text, env: _envForAddress(addr));
    } catch (e) {
      lastError = '$e';
      store.patchRuntime(lastError: lastError);
      notifyListeners();
    }
  }

  Future<void> startNewSession(
    SessionKind kind,
    String name, {
    String? model,
    String nodeId = 'local',
    String? preferredHomeBuildingId,
  }) async {
    final cli = _cli;
    if (cli == null) return;

    final addr = '@$nodeId:$name';
    final codexModel = (model != null && model.trim().isNotEmpty)
        ? model.trim()
        : 'gpt-5.2';
    final cmd = _commandForSession(
      kind: kind,
      nodeId: nodeId,
      codexModel: codexModel,
      colonyBin: cli.binPath,
    );

    lastError = null;
    store.patchRuntime(lastError: null);
    notifyListeners();
    try {
      if (preferredHomeBuildingId != null) {
        _preferredHomeBuildingByAddress[addr] = preferredHomeBuildingId;
      }
      await cli.startSession(addr, cmd, env: _envForAddress(addr));
      _sessionKindHintsByAddress[addr] = kind;
      await _refreshSessions();
      final session = sessions.firstWhere(
        (candidate) => candidate.address == addr,
        orElse: () =>
            Session(node: NodeRef(nodeId), name: name, kind: kind, x: 0, y: 0),
      );
      selectSession(session);
    } catch (e) {
      lastError = '$e';
      store.patchRuntime(lastError: lastError);
      notifyListeners();
    }
  }

  Future<void> createWorkerForMachine(String buildingId) async {
    final building = boardBuildingById(buildingId);
    if (building == null || building.kind != BoardBuildingKind.machine) return;
    final kind = sessionKindForProvider(building.provider);
    if (kind == SessionKind.generic) {
      lastError = 'Machine provider is not supported';
      notifyListeners();
      return;
    }
    await startNewSession(
      kind,
      defaultSessionNameFor(kind),
      preferredHomeBuildingId: buildingId,
    );
  }

  Future<void> handleBuildingTap(String buildingId) async {
    final building = boardBuildingById(buildingId);
    if (building == null) return;

    if (_assigningWorkerId != null) {
      final worker = boardWorkerById(_assigningWorkerId!);
      if (worker != null && canAssignWorkerToBuilding(worker, building)) {
        assignWorkerToBuilding(worker.id, building.id);
        return;
      }
    }

    _upsertBoardBuilding(building.copyWith(finishVisible: false));
    selection = Selection.building(buildingId);
    buildMode = _draftBuildingId != null;
    _stopStreaming();
    notifyListeners();
  }

  Future<void> bindWorkspaceForBuilding(String buildingId) async {
    final building = boardBuildingById(buildingId);
    if (building == null || !_supportsWorkspaceBinding(building.kind)) {
      return;
    }
    final path = await getDirectoryPath(confirmButtonText: 'Bind Workspace');
    if (path == null || path.trim().isEmpty) return;
    _upsertBoardBuilding(building.copyWith(workspacePath: path.trim()));
    await _persistBoard();
    notifyListeners();
  }

  Future<void> configureServerBuilding(
    String buildingId, {
    required String alias,
    required String host,
    required String password,
  }) async {
    final building = boardBuildingById(buildingId);
    if (building == null || building.kind != BoardBuildingKind.server) return;
    final cleanAlias = alias.trim();
    final cleanHost = host.trim();
    final cleanPassword = password;
    var config = ServerConfig(
      alias: cleanAlias.isEmpty ? cleanHost : cleanAlias,
      host: cleanHost,
      password: cleanPassword,
      status: 'connecting',
    );
    _upsertBoardBuilding(building.copyWith(serverConfig: config));
    notifyListeners();

    try {
      final cli = _cli;
      if (cli != null && cleanHost.isNotEmpty) {
        _sshPasswordByHost[cleanHost] = cleanPassword;
        await cli.listProviders(
          target: cleanHost,
          env: cleanPassword.isEmpty
              ? const {}
              : {'COLONY_SSH_PASSWORD': cleanPassword},
        );
      }
      config = config.copyWith(status: 'connected', error: '');
    } catch (e) {
      config = config.copyWith(status: 'failed', error: '$e');
    }

    _upsertBoardBuilding(building.copyWith(serverConfig: config));
    await _persistBoard();
    notifyListeners();
  }

  void selectSession(Session session) {
    selection = Selection.session(session.address);
    final taskId = _taskIdForAddress(session.address);
    if (taskId != null) {
      store.selectSessionTask(taskId);
      _startStreamingForTask(taskId, session.address);
    } else {
      _stopStreaming();
    }
    notifyListeners();
  }

  void beginWorkerAssignment(String workerId) {
    final worker = boardWorkerById(workerId);
    if (worker == null) return;
    _assigningWorkerId = workerId;
    if ((worker.sessionAddress ?? '').isNotEmpty) {
      final session = sessionByAddress(worker.sessionAddress!);
      if (session != null) {
        selectSession(session);
        return;
      }
    }
    notifyListeners();
  }

  bool canAssignWorkerToBuilding(PlacedWorker worker, PlacedBuilding building) {
    return building.kind != BoardBuildingKind.machine;
  }

  void assignWorkerToBuilding(String workerId, String buildingId) {
    final worker = boardWorkerById(workerId);
    final building = boardBuildingById(buildingId);
    if (worker == null ||
        building == null ||
        !canAssignWorkerToBuilding(worker, building)) {
      return;
    }
    _replaceBoardWorker(
      worker.copyWith(
        assignedBuildingId: buildingId,
        status: WorkerStatus.working,
      ),
    );
    _assigningWorkerId = null;
    notifyListeners();
  }

  void clearSelection() {
    selection = const Selection.none();
    _assigningWorkerId = null;
    store.clearSelection();
    _stopStreaming();
    notifyListeners();
  }

  Future<void> handleBackgroundTap() async {
    if (_draftBuildingId != null) {
      await finalizeDraftPlacement();
      return;
    }
    if (_assigningWorkerId != null) {
      _assigningWorkerId = null;
      notifyListeners();
      return;
    }
    clearSelection();
  }

  Future<void> beginInventoryPlacement(BoardInventoryItem item) async {
    if (_draftBuildingId != null) return;
    final origin = _nearestAvailableOrigin(item.kind);
    if (origin == null) {
      lastError = 'No free tiles available for ${item.label}.';
      notifyListeners();
      return;
    }
    final building = PlacedBuilding(
      id: 'building:${DateTime.now().microsecondsSinceEpoch}',
      kind: item.kind,
      origin: origin,
      provider: item.provider,
      orientation: BoardOrientation.l,
    );
    _boardBuildings = [..._boardBuildings, building];
    _draftBuildingId = building.id;
    _draftIsNew = true;
    buildMode = true;
    selection = Selection.building(building.id);
    notifyListeners();
  }

  void beginMovingBuilding(String buildingId) {
    final building = boardBuildingById(buildingId);
    if (building == null) return;
    _draftBuildingId = buildingId;
    _draftIsNew = false;
    buildMode = true;
    selection = Selection.building(buildingId);
    notifyListeners();
  }

  void updateDraftBuildingOrigin(GridPoint origin) {
    final buildingId = _draftBuildingId;
    if (buildingId == null) return;
    final building = boardBuildingById(buildingId);
    if (building == null) return;
    _upsertBoardBuilding(building.copyWith(origin: origin));
    notifyListeners();
  }

  bool isPlacementLegalForBuilding(
    PlacedBuilding building, {
    GridPoint? origin,
  }) {
    final cells = footprintFor(building, origin: origin);
    for (final cell in cells) {
      if (cell.x < 0 ||
          cell.x >= boardDimension ||
          cell.y < 0 ||
          cell.y >= boardDimension) {
        return false;
      }
      for (final other in _boardBuildings) {
        if (other.id == building.id) continue;
        final otherCells = footprintFor(other);
        if (otherCells.any((item) => item.x == cell.x && item.y == cell.y)) {
          return false;
        }
      }
    }
    return true;
  }

  Future<void> finalizeDraftPlacement() async {
    final buildingId = _draftBuildingId;
    if (buildingId == null) return;
    final building = boardBuildingById(buildingId);
    if (building == null) return;
    if (!isPlacementLegalForBuilding(building)) {
      lastError =
          'This placement overlaps another building or leaves the board.';
      notifyListeners();
      return;
    }
    _draftBuildingId = null;
    _draftIsNew = false;
    buildMode = false;
    await _persistBoard();
    notifyListeners();
  }

  Future<void> deleteBuilding(String buildingId) async {
    final building = boardBuildingById(buildingId);
    if (building == null) return;

    final deletingMachine = building.kind == BoardBuildingKind.machine;
    final removedWorkerIds = _boardWorkers
        .where((worker) => worker.homeBuildingId == buildingId)
        .map((worker) => worker.id)
        .toSet();

    _boardBuildings = _boardBuildings
        .where((item) => item.id != buildingId)
        .toList(growable: false);
    _boardWorkers = _boardWorkers
        .where((worker) => !removedWorkerIds.contains(worker.id))
        .map((worker) {
          if (worker.assignedBuildingId == buildingId) {
            return worker.copyWith(
              clearAssignedBuildingId: true,
              status: WorkerStatus.idle,
            );
          }
          return worker;
        })
        .toList(growable: false);

    if (deletingMachine) {
      _preferredHomeBuildingByAddress.removeWhere(
        (_, preferredId) => preferredId == buildingId,
      );
    }

    if (selection.kind == SelectionKind.building &&
        selection.id == buildingId) {
      selection = const Selection.none();
    }
    if (_draftBuildingId == buildingId) {
      _draftBuildingId = null;
      _draftIsNew = false;
      buildMode = false;
    }
    if (_assigningWorkerId != null &&
        removedWorkerIds.contains(_assigningWorkerId)) {
      _assigningWorkerId = null;
    }

    await _persistBoard();
    notifyListeners();
  }

  Future<void> removeUncommittedBuildingIfNeeded() async {
    if (_draftBuildingId == null || !_draftIsNew) return;
    _boardBuildings = _boardBuildings
        .where((building) => building.id != _draftBuildingId)
        .toList(growable: false);
    _draftBuildingId = null;
    _draftIsNew = false;
    buildMode = false;
    notifyListeners();
  }

  List<GridPoint> footprintFor(PlacedBuilding building, {GridPoint? origin}) {
    final start = origin ?? building.origin;
    final length = switch (building.kind) {
      BoardBuildingKind.machine => 2,
      BoardBuildingKind.workflowLine => 5,
      _ => 1,
    };
    final expandOnX = building.orientation == BoardOrientation.r;
    return [
      for (var index = 0; index < length; index++)
        GridPoint(
          x: expandOnX ? start.x + index : start.x,
          y: expandOnX ? start.y : start.y + index,
        ),
    ];
  }

  String titleForBuildingKind(BoardBuildingKind kind) {
    return switch (kind) {
      BoardBuildingKind.buildingWorkspace => 'Workspace Building',
      BoardBuildingKind.buildingAltA => 'Building A',
      BoardBuildingKind.buildingAltB => 'Building B',
      BoardBuildingKind.server => 'Server',
      BoardBuildingKind.kanban => 'Kanban',
      BoardBuildingKind.machine => 'Machine',
      BoardBuildingKind.workflowLine => 'Workflow Line',
    };
  }

  String subtitleForBuilding(PlacedBuilding building) {
    return switch (building.kind) {
      BoardBuildingKind.buildingWorkspace =>
        (building.workspacePath ?? '').isEmpty
            ? 'Bind a local project folder'
            : building.workspacePath!,
      BoardBuildingKind.buildingAltA =>
        (building.workspacePath ?? '').isEmpty
            ? 'Choose a local project folder'
            : building.workspacePath!,
      BoardBuildingKind.buildingAltB =>
        (building.workspacePath ?? '').isEmpty
            ? 'Choose a local project folder'
            : building.workspacePath!,
      BoardBuildingKind.server =>
        building.serverConfig == null
            ? 'Configure remote host'
            : '${building.serverConfig!.alias} • ${building.serverConfig!.status}',
      BoardBuildingKind.kanban => 'Visual task board',
      BoardBuildingKind.machine =>
        '${providerLabel(building.provider)} worker machine',
      BoardBuildingKind.workflowLine => 'Five-tile line placeholder',
    };
  }

  String assetPathForBuilding(PlacedBuilding building) {
    return switch (building.kind) {
      BoardBuildingKind.buildingWorkspace =>
        'assets/colony_res/building_workspace.png',
      BoardBuildingKind.buildingAltA => 'assets/colony_res/building_alt_a.png',
      BoardBuildingKind.buildingAltB => 'assets/colony_res/building_alt_b.png',
      BoardBuildingKind.server => 'assets/colony_res/server.png',
      BoardBuildingKind.kanban => 'assets/colony_res/kanban.png',
      BoardBuildingKind.machine =>
        workersOwnedByMachine(
              building.id,
            ).any((worker) => worker.status == WorkerStatus.working)
            ? 'assets/colony_res/machine_working_l.png'
            : 'assets/colony_res/machine_idle_l.png',
      BoardBuildingKind.workflowLine => 'assets/colony_res/workflow_line_l.png',
    };
  }

  String assetPathForInventoryItem(BoardInventoryItem item) {
    return switch (item.kind) {
      BoardBuildingKind.buildingWorkspace =>
        'assets/colony_res/building_workspace.png',
      BoardBuildingKind.buildingAltA => 'assets/colony_res/building_alt_a.png',
      BoardBuildingKind.buildingAltB => 'assets/colony_res/building_alt_b.png',
      BoardBuildingKind.server => 'assets/colony_res/server.png',
      BoardBuildingKind.kanban => 'assets/colony_res/kanban.png',
      BoardBuildingKind.machine => 'assets/colony_res/machine_idle_l.png',
      BoardBuildingKind.workflowLine => 'assets/colony_res/workflow_line_l.png',
    };
  }

  AgentProvider? providerForAddress(String address) {
    final worker = boardWorkerForAddress(address);
    return worker?.provider;
  }

  SessionKind sessionKindForProvider(AgentProvider provider) {
    return switch (provider) {
      AgentProvider.codex => SessionKind.codex,
      AgentProvider.claude => SessionKind.claude,
      AgentProvider.openclaw => SessionKind.openclaw,
      AgentProvider.other || AgentProvider.none => SessionKind.generic,
    };
  }

  String providerLabel(AgentProvider provider) {
    return switch (provider) {
      AgentProvider.codex => 'codex',
      AgentProvider.claude => 'claude',
      AgentProvider.openclaw => 'openclaw',
      AgentProvider.other => 'agent',
      AgentProvider.none => 'idle',
    };
  }

  String defaultSessionNameFor(SessionKind kind, {String nodeId = 'local'}) {
    final prefix = switch (kind) {
      SessionKind.codex => 'codex',
      SessionKind.claude => 'claude',
      SessionKind.openclaw => 'openclaw',
      SessionKind.generic => 'agent',
    };

    final used = sessions
        .where((session) => session.node.id == nodeId)
        .map((session) => session.name)
        .toSet();
    var index = 1;
    while (used.contains('$prefix$index')) {
      index += 1;
    }
    return '$prefix$index';
  }

  List<String> _commandForSession({
    required SessionKind kind,
    required String nodeId,
    required String codexModel,
    required String colonyBin,
  }) {
    final isLocal = nodeId == 'local';
    if (isLocal) {
      return switch (kind) {
        SessionKind.codex => <String>[
          colonyBin,
          'agent',
          'codex',
          '--model',
          codexModel,
        ],
        SessionKind.claude => <String>[colonyBin, 'agent', 'claude'],
        SessionKind.openclaw => <String>[
          '/bin/zsh',
          '-lc',
          _localZshScript(_bashAgentOpenClaw()),
        ],
        SessionKind.generic => <String>['/usr/bin/env', 'bash', '-lc', 'cat'],
      };
    }

    return switch (kind) {
      SessionKind.codex => <String>[
        '/usr/bin/env',
        'bash',
        '-lc',
        _remoteBashAgentCodex(model: codexModel),
      ],
      SessionKind.claude => <String>[
        '/usr/bin/env',
        'bash',
        '-lc',
        _remoteBashAgentClaude(),
      ],
      SessionKind.openclaw => <String>[
        '/usr/bin/env',
        'bash',
        '-lc',
        _bashAgentOpenClaw(),
      ],
      SessionKind.generic => <String>['/usr/bin/env', 'bash', '-lc', 'cat'],
    };
  }

  String _bashAgentOpenClaw() {
    final script = r'''
set -euo pipefail
AGENT_ID="$(openclaw agents list 2>/dev/null | awk '/^- /{print $2; exit}')"
AGENT_ID="${AGENT_ID:-main}"
echo "[colony-agent] openclaw ready (agent=$AGENT_ID)"
while IFS= read -r line; do
  line="$(printf "%s" "$line" | tr -d '\r')"
  [ -z "$line" ] && continue
  echo "[colony-agent] >>> $line"
  openclaw agent --local --agent "$AGENT_ID" --json -m "$line" 2>&1
  echo "[colony-agent] <<< done"
done
''';
    return script
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('; ');
  }

  String _localZshScript(String script) {
    return 'source ~/.zshrc >/dev/null 2>&1 || true; $script';
  }

  String _remoteBashAgentCodex({required String model}) {
    final sanitized = model.replaceAll("'", '');
    final script =
        r'''
set -euo pipefail
MODEL="''' +
        sanitized +
        r'''"
echo "[colony-agent] codex remote ready (model=$MODEL)"
while IFS= read -r line; do
  line="$(printf "%s" "$line" | tr -d '\r')"
  [ -z "$line" ] && continue
  if [[ "$line" == /model\ * ]]; then
    MODEL="${line#/model }"
    echo "[colony-agent] model set to $MODEL"
    continue
  fi
  echo "[colony-agent] >>> $line"
  codex exec --json --skip-git-repo-check -m "$MODEL" "$line" 2>&1
  echo "[colony-agent] <<< done"
done
''';
    return script
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('; ');
  }

  String _remoteBashAgentClaude() {
    final script = r'''
set -euo pipefail
echo "[colony-agent] claude remote ready"
while IFS= read -r line; do
  line="$(printf "%s" "$line" | tr -d '\r')"
  [ -z "$line" ] && continue
  echo "[colony-agent] >>> $line"
  claude -p --verbose --output-format=stream-json --include-partial-messages "$line" 2>&1
  echo "[colony-agent] <<< done"
done
''';
    return script
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('; ');
  }

  void _startStreamingForTask(String taskId, String address) {
    _stopStreaming();
    final cli = _cli;
    if (cli == null) return;

    cli
        .startLogStream(address, env: _envForAddress(address))
        .then((stream) {
          _logStreamsByTaskId[taskId] = stream;
          stream.events.listen((event) {
            final currentLogs = Map<String, List<String>>.from(
              store.runtime.liveLogsBySessionTaskId,
            );
            final currentEvents = Map<String, List<ColonyStreamEvent>>.from(
              store.runtime.liveEventsBySessionTaskId,
            );
            final logBuffer = List<String>.from(
              currentLogs[taskId] ?? const <String>[],
            )..add(event.rawLine);
            if (logBuffer.length > 2000) {
              logBuffer.removeRange(0, logBuffer.length - 2000);
            }
            final eventBuffer = List<ColonyStreamEvent>.from(
              currentEvents[taskId] ?? const <ColonyStreamEvent>[],
            )..add(event);
            if (eventBuffer.length > 800) {
              eventBuffer.removeRange(0, eventBuffer.length - 800);
            }
            currentLogs[taskId] = logBuffer;
            currentEvents[taskId] = eventBuffer;
            _sessionLogs[address] = logBuffer;
            store.patchRuntime(
              liveLogsBySessionTaskId: currentLogs,
              liveEventsBySessionTaskId: currentEvents,
              lastError: lastError,
            );
            _handleStreamEvent(address, event);
          });
        })
        .catchError((Object error) {
          lastError = '$error';
          store.patchRuntime(lastError: lastError);
          notifyListeners();
        });
  }

  void _handleStreamEvent(String address, ColonyStreamEvent event) {
    if (event.kind != ColonyStreamEventKind.systemEvent) return;
    final text = event.text.trim().toLowerCase();
    if (!text.startsWith('turn completed')) return;
    final worker = boardWorkerForAddress(address);
    if (worker == null) return;
    final assignedBuildingId = worker.assignedBuildingId;
    if (assignedBuildingId == null) return;
    final building = boardBuildingById(assignedBuildingId);
    if (building == null) return;

    _upsertBoardBuilding(building.copyWith(finishVisible: true));
    _replaceBoardWorker(
      worker.copyWith(clearAssignedBuildingId: true, status: WorkerStatus.idle),
    );
    notifyListeners();
  }

  void _stopStreaming() {
    for (final stream in _logStreamsByTaskId.values) {
      stream.stop();
    }
    _logStreamsByTaskId.clear();
  }

  void _pruneStreamsForMissingTasks() {
    final validTaskIds = store.sessionTasksById.keys.toSet();
    final staleTaskIds = _logStreamsByTaskId.keys
        .where((taskId) => !validTaskIds.contains(taskId))
        .toList();
    for (final taskId in staleTaskIds) {
      _logStreamsByTaskId.remove(taskId)?.stop();
    }
  }

  List<Session> _sessionsFromAddresses(List<String> addresses) {
    final output = <Session>[];
    for (final address in addresses) {
      final parsed = _parseAddress(address);
      if (parsed == null) continue;
      final (nodeId, name) = parsed;
      output.add(
        Session(
          node: NodeRef(nodeId),
          name: name,
          kind: _sessionKindHintsByAddress[address] ?? _inferKind(name),
          x: 0,
          y: 0,
          status: SessionStatus.running,
        ),
      );
    }
    return output;
  }

  SessionKind _inferKind(String name) {
    final normalized = name.toLowerCase();
    if (normalized.contains('codex')) return SessionKind.codex;
    if (normalized.contains('claude')) return SessionKind.claude;
    if (normalized.contains('openclaw') || normalized.contains('opencode')) {
      return SessionKind.openclaw;
    }
    return SessionKind.generic;
  }

  AgentProvider _providerForSessionKind(SessionKind kind) {
    return switch (kind) {
      SessionKind.codex => AgentProvider.codex,
      SessionKind.claude => AgentProvider.claude,
      SessionKind.openclaw => AgentProvider.openclaw,
      SessionKind.generic => AgentProvider.other,
    };
  }

  AgentProvider? _providerFromName(String raw) {
    return switch (raw.trim().toLowerCase()) {
      'codex' => AgentProvider.codex,
      'claude' => AgentProvider.claude,
      'openclaw' || 'opencode' => AgentProvider.openclaw,
      'other' => AgentProvider.other,
      '' => null,
      _ => AgentProvider.other,
    };
  }

  List<AgentProvider> _normalizedProviders(
    List<AgentProvider> providers, {
    required String target,
  }) {
    final next = <AgentProvider>[];
    final seen = <AgentProvider>{};
    for (final provider in providers) {
      if (provider == AgentProvider.none) continue;
      if (seen.add(provider)) {
        next.add(provider);
      }
    }
    if (target == 'local') {
      for (final provider in const [
        AgentProvider.codex,
        AgentProvider.claude,
        AgentProvider.openclaw,
      ]) {
        if (seen.add(provider)) {
          next.add(provider);
        }
      }
    }
    return next.isEmpty ? _fallbackProvidersForTarget(target) : next;
  }

  List<AgentProvider> _fallbackProvidersForTarget(String target) {
    if (target == 'local') {
      return const [
        AgentProvider.codex,
        AgentProvider.claude,
        AgentProvider.openclaw,
      ];
    }
    return const [AgentProvider.codex];
  }

  Map<String, String> _envForAddress(String address) {
    final parsed = _parseAddress(address);
    if (parsed == null) return const {};
    final (nodeId, _) = parsed;
    if (nodeId == 'local') return const {};
    final password = _sshPasswordByHost[nodeId];
    if (password == null || password.isEmpty) return const {};
    return {'COLONY_SSH_PASSWORD': password};
  }

  (String, String)? _parseAddress(String value) {
    if (!value.startsWith('@')) return null;
    final body = value.substring(1);
    final idx = body.indexOf(':');
    if (idx < 0) return null;
    final node = body.substring(0, idx);
    final name = body.substring(idx + 1);
    if (node.isEmpty || name.isEmpty) return null;
    return (node, name);
  }

  String? _taskIdForAddress(String address) => _sessionTaskIdByAddress[address];

  GridPoint? _nearestAvailableOrigin(BoardBuildingKind kind) {
    final probe = PlacedBuilding(
      id: '__probe__',
      kind: kind,
      origin: const GridPoint(x: 0, y: 0),
    );
    final candidates = <GridPoint>[
      for (var y = 0; y < boardDimension; y++)
        for (var x = 0; x < boardDimension; x++) GridPoint(x: x, y: y),
    ];
    candidates.sort((a, b) {
      final da = (a.x - 9).abs() + (a.y - 9).abs();
      final db = (b.x - 9).abs() + (b.y - 9).abs();
      if (da != db) return da.compareTo(db);
      if (a.y != b.y) return a.y.compareTo(b.y);
      return a.x.compareTo(b.x);
    });
    for (final candidate in candidates) {
      if (isPlacementLegalForBuilding(probe, origin: candidate)) {
        return candidate;
      }
    }
    return null;
  }

  Future<void> _persistBoard() async {
    await _boardStore.save(BoardSnapshot(buildings: _boardBuildings));
  }

  bool _supportsWorkspaceBinding(BoardBuildingKind kind) {
    return kind == BoardBuildingKind.buildingWorkspace ||
        kind == BoardBuildingKind.buildingAltA ||
        kind == BoardBuildingKind.buildingAltB;
  }

  void _upsertBoardBuilding(PlacedBuilding next) {
    final index = _boardBuildings.indexWhere(
      (building) => building.id == next.id,
    );
    if (index < 0) {
      _boardBuildings = [..._boardBuildings, next];
      return;
    }
    final copy = List<PlacedBuilding>.from(_boardBuildings);
    copy[index] = next;
    _boardBuildings = copy;
  }

  void _replaceBoardWorker(PlacedWorker next) {
    final index = _boardWorkers.indexWhere((worker) => worker.id == next.id);
    if (index < 0) {
      _boardWorkers = [..._boardWorkers, next];
      return;
    }
    final copy = List<PlacedWorker>.from(_boardWorkers);
    copy[index] = next;
    _boardWorkers = copy;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
