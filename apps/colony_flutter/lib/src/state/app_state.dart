import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../application/colony_application.dart';
import '../domain/colony_domain.dart';
import '../infrastructure/infrastructure.dart';
import '../model/entities.dart';

enum SelectionKind { none, project, session }

class Selection {
  final SelectionKind kind;
  final String id;
  const Selection._(this.kind, this.id);
  const Selection.none() : this._(SelectionKind.none, '');
  const Selection.project(String id) : this._(SelectionKind.project, id);
  const Selection.session(String id) : this._(SelectionKind.session, id);
}

class AppState extends ChangeNotifier {
  AppState({
    ColonyStore? store,
    ColonyBinaryLocator? binaryLocator,
    ColonyCommandAdapter? commandAdapter,
  })  : store = store ?? ColonyStore(),
        _binaryLocator = binaryLocator ?? const ColonyBinaryLocator(),
        _cli = commandAdapter {
    this.store.addListener(_onStoreChanged);
  }

  final ColonyStore store;
  final ColonyBinaryLocator _binaryLocator;
  ColonyCommandAdapter? _cli;

  final List<Project> projects = [];
  final List<Session> sessions = [];
  final Map<String, String> _sshPasswordByHost = {};
  final Map<String, List<String>> _sessionLogs = {};
  final Map<String, ColonyLogStream> _logStreamsByTaskId = {};
  final Map<String, String> _sessionTaskIdByAddress = {};

  bool buildMode = false;
  Selection selection = const Selection.none();

  Map<String, dynamic>? codexRateLimit;
  String? lastError;

  Future<void> bootstrap() async {
    store.bootstrapLocalWorld();
    _syncProjectsFromStore();

    final bin = await _binaryLocator.discover();
    _cli ??= ProcessColonyCommandAdapter(bin ?? 'colony');

    await refresh();
  }

  Future<void> refresh() async {
    lastError = null;
    notifyListeners();
    try {
      await _refreshSessions();
      await _refreshRateLimit();
    } catch (e) {
      lastError = '$e';
      store.patchRuntime(lastError: lastError);
    }
    notifyListeners();
  }

  Future<void> _refreshSessions() async {
    final cli = _cli;
    if (cli == null) return;

    final addresses = <String>[];
    for (final project in projects) {
      final target = project.nodeId == 'local' ? 'local' : project.nodeId;
      final env = _envForTarget(target);
      final listed = await cli.listSessions(target: target, env: env);
      addresses.addAll(listed);
    }

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

  void toggleBuildMode(bool enabled) {
    buildMode = enabled;
    notifyListeners();
  }

  void selectProject(Project project) {
    selection = Selection.project(project.id);
    store.selectWorld(project.nodeId);
    _stopStreaming();
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

  void clearSelection() {
    selection = const Selection.none();
    store.clearSelection();
    _stopStreaming();
    notifyListeners();
  }

  List<String> logsFor(String address) {
    final taskId = _taskIdForAddress(address);
    if (taskId != null) {
      return store.runtime.liveLogsBySessionTaskId[taskId] ?? const [];
    }
    return _sessionLogs[address] ?? const [];
  }

  String resolveAddressShorthand(String raw) {
    if (!raw.startsWith('@')) return raw;
    if (raw.contains(':')) return raw;
    final needle = raw.substring(1).toLowerCase();
    if (needle.isEmpty) return raw;

    final exact = sessions.where((session) {
      return session.name.toLowerCase() == needle || session.address.toLowerCase() == raw.toLowerCase();
    }).toList();
    if (exact.isNotEmpty) return exact.first.address;

    final fuzzy = sessions.where((session) => session.address.toLowerCase().contains(needle)).toList();
    if (fuzzy.isNotEmpty) return fuzzy.first.address;

    return '@local:$needle';
  }

  Future<void> sendToSelection(String text, {String? addressOverride}) async {
    final cli = _cli;
    if (cli == null) return;

    final addrRaw = addressOverride ?? (selection.kind == SelectionKind.session ? selection.id : null);
    final addr = (addrRaw == null) ? null : resolveAddressShorthand(addrRaw);
    if (addr == null || addr.isEmpty) {
      lastError = 'No session selected';
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
  }) async {
    final cli = _cli;
    if (cli == null) return;

    final addr = '@$nodeId:$name';
    final codexModel = (model != null && model.trim().isNotEmpty) ? model.trim() : 'gpt-5.2';
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
      await cli.startSession(addr, cmd, env: _envForAddress(addr));
      await _refreshSessions();
      final session = sessions.firstWhere(
        (candidate) => candidate.address == addr,
        orElse: () => Session(node: NodeRef(nodeId), name: name, kind: kind, x: 3, y: 2),
      );
      selectSession(session);
    } catch (e) {
      lastError = '$e';
      store.patchRuntime(lastError: lastError);
      notifyListeners();
    }
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
        SessionKind.codex => <String>[colonyBin, 'agent', 'codex', '--model', codexModel],
        SessionKind.claude => <String>[colonyBin, 'agent', 'claude'],
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
      SessionKind.generic => <String>['/usr/bin/env', 'bash', '-lc', 'cat'],
    };
  }

  String _remoteBashAgentCodex({required String model}) {
    final sanitized = model.replaceAll("'", '');
    final script = r'''
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
    return script.split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty).join('; ');
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
    return script.split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty).join('; ');
  }

  Project get localProject => projects.firstWhere((project) => project.nodeId == 'local');

  void moveProject(String projectId, double dx, double dy) {
    final index = projects.indexWhere((project) => project.id == projectId);
    if (index < 0) return;
    final next = projects[index];
    next.x += dx;
    next.y += dy;
    notifyListeners();
  }

  void moveSession(String address, double dx, double dy) {
    final index = sessions.indexWhere((session) => session.address == address);
    if (index < 0) return;
    final next = sessions[index];
    next.x += dx;
    next.y += dy;

    final taskId = _taskIdForAddress(address);
    if (taskId != null) {
      final task = store.sessionTasksById[taskId];
      if (task != null) {
        final worker = store.workersById[task.workerId];
        if (worker != null) {
          store.upsertWorker(worker.copyWith(metadata: {
            ...worker.metadata,
            'x': next.x,
            'y': next.y,
          }));
        }
      }
    }

    notifyListeners();
  }

  Project? projectById(String id) => projects.where((project) => project.id == id).firstOrNull;

  Session? sessionByAddress(String address) => sessions.where((session) => session.address == address).firstOrNull;

  String nodeIdForProjectId(String projectId) {
    final project = projectById(projectId);
    return project?.nodeId ?? 'local';
  }

  Future<void> addRemoteHost(String host, {String? password}) async {
    final normalized = host.trim();
    if (normalized.isEmpty) return;
    if (password != null && password.isNotEmpty) {
      _sshPasswordByHost[normalized] = password;
    }

    final existingWorld = store.worldsById[normalized];
    if (existingWorld == null) {
      store.upsertWorld(
        World(
          id: normalized,
          kind: WorldKind.ssh,
          name: normalized,
          connectionState: WorldConnectionState.connecting,
          metadata: const {'source': 'ssh'},
        ),
      );
    }

    _ensureWorldScaffold(
      normalized,
      displayName: normalized,
      kind: WorldKind.ssh,
      townHallPosition: const WorldPosition(x: 7, y: 2),
    );

    _syncProjectsFromStore();
    await refresh();
  }

  Map<String, String> _envForTarget(String target) {
    if (target == 'local') return const {};
    final password = _sshPasswordByHost[target];
    if (password == null || password.isEmpty) return const {};
    return {'COLONY_SSH_PASSWORD': password};
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

  @override
  void dispose() {
    store.removeListener(_onStoreChanged);
    _stopStreaming();
    super.dispose();
  }

  void _onStoreChanged() {
    lastError = store.runtime.lastError;
    final snapshot = store.runtime.backendSnapshot;
    if (snapshot.isNotEmpty) {
      codexRateLimit = Map<String, dynamic>.from(snapshot);
    }
    notifyListeners();
  }

  void _syncProjectsFromStore() {
    final previousByNode = {
      for (final project in projects) project.nodeId: project,
    };

    final nextProjects = <Project>[];
    final sortedWorlds = store.worlds.toList()
      ..sort((a, b) {
        if (a.id == 'local') return -1;
        if (b.id == 'local') return 1;
        return a.name.compareTo(b.name);
      });

    for (var index = 0; index < sortedWorlds.length; index++) {
      final world = sortedWorlds[index];
      final existing = previousByNode[world.id];
      if (existing != null) {
        nextProjects.add(existing);
        continue;
      }

      final isLocal = world.id == 'local';
      nextProjects.add(
        Project(
          id: 'p_${world.id}',
          nodeId: world.id,
          name: world.name,
          x: isLocal ? 1.0 : (1.0 + index * 6.5),
          y: isLocal ? 1.0 : (1.0 + index * 2.6),
        ),
      );
    }

    projects
      ..clear()
      ..addAll(nextProjects);
  }

  void _syncSessionTasks(List<String> addresses) {
    final activeTaskIds = <String>{};

    for (final address in addresses) {
      final parsed = _parseAddress(address);
      if (parsed == null) continue;

      final (nodeId, sessionName) = parsed;
      _ensureWorldScaffold(
        nodeId,
        displayName: nodeId == 'local' ? 'Local' : nodeId,
        kind: nodeId == 'local' ? WorldKind.local : WorldKind.ssh,
        townHallPosition: const WorldPosition(x: 0, y: 0),
      );

      final taskId = _sessionTaskIdByAddress[address] ??= 'task:$address';
      activeTaskIds.add(taskId);

      final kind = _inferKind(sessionName);
      final provider = _providerForSessionKind(kind);
      final hutId = _hutIdForProvider(nodeId, provider);
      final workerId = 'worker:$address';
      final workerPos = _positionForAddress(address, nodeId: nodeId, name: sessionName);

      final currentWorker = store.workersById[workerId];
      store.upsertWorker(
        (currentWorker ??
                Worker(
                  id: workerId,
                  worldId: nodeId,
                  provider: provider,
                  homeBuildingId: hutId,
                ))
            .copyWith(
          assignedBuildingId: hutId,
          sessionTaskId: taskId,
          status: WorkerStatus.working,
          metadata: {
            ...(currentWorker?.metadata ?? const {}),
            'x': workerPos.$1,
            'y': workerPos.$2,
          },
        ),
      );

      final backend = nodeId == 'local' ? SessionBackend.localTmux : SessionBackend.sshTmux;
      final currentTask = store.sessionTasksById[taskId];
      store.upsertSessionTask(
        (currentTask ??
                SessionTask(
                  id: taskId,
                  workerId: workerId,
                  address: address,
                  backend: backend,
                  title: sessionName,
                ))
            .copyWith(
          workerId: workerId,
          address: address,
          backend: backend,
          title: sessionName,
          status: SessionTaskStatus.running,
          startedAt: currentTask?.startedAt ?? DateTime.now(),
          metadata: {
            ...(currentTask?.metadata ?? const {}),
            'nodeId': nodeId,
            'sessionKind': kind.name,
          },
        ),
      );
    }

    final staleTaskIds = store.sessionTasksById.keys.where((taskId) => !activeTaskIds.contains(taskId)).toList();
    for (final taskId in staleTaskIds) {
      final task = store.sessionTasksById.remove(taskId);
      if (task != null) {
        store.workersById.remove(task.workerId);
      }
      _logStreamsByTaskId.remove(taskId)?.stop();
    }

    final activeLogs = Map<String, List<String>>.from(store.runtime.liveLogsBySessionTaskId);
    activeLogs.removeWhere((taskId, _) => !activeTaskIds.contains(taskId));
    _sessionTaskIdByAddress.removeWhere((address, taskId) => !activeTaskIds.contains(taskId));
    store.patchRuntime(
      liveLogsBySessionTaskId: activeLogs,
      lastError: lastError,
    );
  }

  void _ensureWorldScaffold(
    String worldId, {
    required String displayName,
    required WorldKind kind,
    required WorldPosition townHallPosition,
  }) {
    final world = store.worldsById[worldId];
    if (world == null) {
      store.upsertWorld(
        World(
          id: worldId,
          kind: kind,
          name: displayName,
          connectionState: kind == WorldKind.local ? WorldConnectionState.connected : WorldConnectionState.connecting,
        ),
      );
    }

    final townHallId = '$worldId:town-hall';
    if (!store.buildingsById.containsKey(townHallId)) {
      store.upsertBuilding(
        Building(
          id: townHallId,
          worldId: worldId,
          type: BuildingType.townHall,
          name: worldId == 'local' ? 'Town Hall' : '$displayName Keep',
          position: townHallPosition,
          status: BuildingStatus.active,
        ),
      );
    }

    final zoneId = '$worldId:zone:default';
    if (!store.zonesById.containsKey(zoneId)) {
      store.upsertZone(
        Zone(
          id: zoneId,
          worldId: worldId,
          label: worldId == 'local' ? 'Village Core' : '$displayName Frontier',
          bounds: const ZoneBounds(x: -4, y: -3, width: 8, height: 6),
          status: ZoneStatus.active,
        ),
      );
    }

    _ensureHut(worldId, AgentProvider.codex, const WorldPosition(x: 2, y: 1));
    _ensureHut(worldId, AgentProvider.claude, const WorldPosition(x: -2, y: 1));
  }

  void _ensureHut(String worldId, AgentProvider provider, WorldPosition position) {
    final buildingId = _hutIdForProvider(worldId, provider);
    if (store.buildingsById.containsKey(buildingId)) return;
    store.upsertBuilding(
      Building(
        id: buildingId,
        worldId: worldId,
        type: BuildingType.agentHut,
        name: switch (provider) {
          AgentProvider.codex => 'Codex Hut',
          AgentProvider.claude => 'Claude Hut',
          AgentProvider.openclaw => 'OpenClaw Hut',
          AgentProvider.other => 'Agent Hut',
          AgentProvider.none => 'Empty Hut',
        },
        position: position,
        status: BuildingStatus.available,
        provider: provider,
      ),
    );
  }

  void _startStreamingForTask(String taskId, String address) {
    _stopStreaming();
    final cli = _cli;
    if (cli == null) return;

    cli.startLogStream(address, env: _envForAddress(address)).then((stream) {
      _logStreamsByTaskId[taskId] = stream;
      stream.lines.listen((line) {
        final currentLogs = Map<String, List<String>>.from(store.runtime.liveLogsBySessionTaskId);
        final buffer = List<String>.from(currentLogs[taskId] ?? const <String>[])..add(line);
        if (buffer.length > 2000) {
          buffer.removeRange(0, buffer.length - 2000);
        }
        currentLogs[taskId] = buffer;
        _sessionLogs[address] = buffer;
        store.patchRuntime(
          liveLogsBySessionTaskId: currentLogs,
          lastError: lastError,
        );
      });
    }).catchError((Object error) {
      lastError = '$error';
      store.patchRuntime(lastError: lastError);
      notifyListeners();
    });
  }

  void _stopStreaming() {
    for (final stream in _logStreamsByTaskId.values) {
      stream.stop();
    }
    _logStreamsByTaskId.clear();
  }

  void _pruneStreamsForMissingTasks() {
    final validTaskIds = store.sessionTasksById.keys.toSet();
    final staleTaskIds = _logStreamsByTaskId.keys.where((taskId) => !validTaskIds.contains(taskId)).toList();
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
      _projectForNode(nodeId);
      final position = _positionForAddress(address, nodeId: nodeId, name: name);
      output.add(
        Session(
          node: NodeRef(nodeId),
          name: name,
          kind: _inferKind(name),
          x: position.$1,
          y: position.$2,
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
    return SessionKind.generic;
  }

  AgentProvider _providerForSessionKind(SessionKind kind) {
    return switch (kind) {
      SessionKind.codex => AgentProvider.codex,
      SessionKind.claude => AgentProvider.claude,
      SessionKind.generic => AgentProvider.other,
    };
  }

  String _hutIdForProvider(String worldId, AgentProvider provider) {
    final suffix = switch (provider) {
      AgentProvider.codex => 'codex',
      AgentProvider.claude => 'claude',
      AgentProvider.openclaw => 'openclaw',
      AgentProvider.other => 'other',
      AgentProvider.none => 'none',
    };
    return '$worldId:hut:$suffix';
  }

  (double, double) _positionForAddress(
    String address, {
    required String nodeId,
    required String name,
  }) {
    final base = _projectForNode(nodeId);
    final hash = address.codeUnits.fold<int>(0, (acc, value) => (acc * 31 + value) & 0x7fffffff);
    final radius = 1.8 + (hash % 120) / 100.0;
    final angle = (hash % 360) * math.pi / 180.0;
    return (
      base.x + radius * math.cos(angle),
      base.y + radius * math.sin(angle),
    );
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

  Project _projectForNode(String nodeId) {
    final existing = projects.where((project) => project.nodeId == nodeId).firstOrNull;
    if (existing != null) return existing;

    final local = projects.firstWhere(
      (project) => project.nodeId == 'local',
      orElse: () => Project(id: 'p_local', nodeId: 'local', name: 'Local', x: 1.0, y: 1.0),
    );
    final index = projects.length;
    final project = Project(
      id: 'p_${nodeId.hashCode}',
      nodeId: nodeId,
      name: nodeId == 'local' ? 'Local' : nodeId,
      x: local.x + 7.0 + (index - 1) * 6.5,
      y: local.y + 1.5 + (index - 1) * 2.6,
    );
    projects.add(project);
    return project;
  }

  String? _taskIdForAddress(String address) => _sessionTaskIdByAddress[address];
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
