import 'package:flutter/foundation.dart';

import '../domain/colony_domain.dart';
import 'colony_runtime.dart';
import 'colony_selection.dart';

class ColonyStore extends ChangeNotifier {
  final Map<ColonyId, World> worldsById = {};
  final Map<ColonyId, Zone> zonesById = {};
  final Map<ColonyId, Building> buildingsById = {};
  final Map<ColonyId, Worker> workersById = {};
  final Map<ColonyId, SessionTask> sessionTasksById = {};
  final Map<ColonyId, Link> linksById = {};

  ColonySelection selection = const ColonySelection.none();
  ColonyRuntimeState runtime = const ColonyRuntimeState();

  bool _bootstrapped = false;

  bool get isBootstrapped => _bootstrapped;

  List<World> get worlds => worldsById.values.toList(growable: false);
  List<Zone> get zones => zonesById.values.toList(growable: false);
  List<Building> get buildings => buildingsById.values.toList(growable: false);
  List<Worker> get workers => workersById.values.toList(growable: false);
  List<SessionTask> get sessionTasks => sessionTasksById.values.toList(growable: false);
  List<Link> get links => linksById.values.toList(growable: false);

  World? get selectedWorld => selection.kind == ColonySelectionKind.world ? worldsById[selection.id] : null;
  Zone? get selectedZone => selection.kind == ColonySelectionKind.zone ? zonesById[selection.id] : null;
  Building? get selectedBuilding => selection.kind == ColonySelectionKind.building ? buildingsById[selection.id] : null;
  Worker? get selectedWorker => selection.kind == ColonySelectionKind.worker ? workersById[selection.id] : null;
  SessionTask? get selectedSessionTask =>
      selection.kind == ColonySelectionKind.sessionTask ? sessionTasksById[selection.id] : null;
  Link? get selectedLink => selection.kind == ColonySelectionKind.link ? linksById[selection.id] : null;

  void bootstrapLocalWorld({String worldId = 'local', String name = 'Local'}) {
    if (_bootstrapped) return;

    final world = World(
      id: normalizeColonyId(worldId),
      kind: WorldKind.local,
      name: name,
      connectionState: WorldConnectionState.connected,
      metadata: const {'role': 'primary'},
    );
    worldsById[world.id] = world;

    final townHall = Building(
      id: '${world.id}:town-hall',
      worldId: world.id,
      type: BuildingType.townHall,
      name: 'Town Hall',
      position: const WorldPosition(x: 0, y: 0, z: 0),
      status: BuildingStatus.active,
      provider: AgentProvider.none,
    );
    buildingsById[townHall.id] = townHall;

    final codexHut = Building(
      id: '${world.id}:hut:codex',
      worldId: world.id,
      type: BuildingType.agentHut,
      name: 'Codex Hut',
      position: const WorldPosition(x: 2, y: 1, z: 0),
      status: BuildingStatus.available,
      provider: AgentProvider.codex,
    );
    buildingsById[codexHut.id] = codexHut;

    final claudeHut = Building(
      id: '${world.id}:hut:claude',
      worldId: world.id,
      type: BuildingType.agentHut,
      name: 'Claude Hut',
      position: const WorldPosition(x: -2, y: 1, z: 0),
      status: BuildingStatus.available,
      provider: AgentProvider.claude,
    );
    buildingsById[claudeHut.id] = claudeHut;

    final defaultZone = Zone(
      id: '${world.id}:zone:default',
      worldId: world.id,
      label: 'Village Core',
      bounds: const ZoneBounds(x: -4, y: -3, width: 8, height: 6),
      status: ZoneStatus.active,
      metadata: const {'seed': true},
    );
    zonesById[defaultZone.id] = defaultZone;

    _bootstrapped = true;
    notifyListeners();
  }

  void reset() {
    worldsById.clear();
    zonesById.clear();
    buildingsById.clear();
    workersById.clear();
    sessionTasksById.clear();
    linksById.clear();
    selection = const ColonySelection.none();
    runtime = const ColonyRuntimeState();
    _bootstrapped = false;
    notifyListeners();
  }

  void setSelection(ColonySelection value) {
    selection = value;
    notifyListeners();
  }

  void clearSelection() {
    selection = const ColonySelection.none();
    notifyListeners();
  }

  void upsertWorld(World world) {
    worldsById[world.id] = world;
    notifyListeners();
  }

  void upsertZone(Zone zone) {
    zonesById[zone.id] = zone;
    notifyListeners();
  }

  void upsertBuilding(Building building) {
    buildingsById[building.id] = building;
    notifyListeners();
  }

  void upsertWorker(Worker worker) {
    workersById[worker.id] = worker;
    notifyListeners();
  }

  void upsertSessionTask(SessionTask task) {
    sessionTasksById[task.id] = task;
    notifyListeners();
  }

  void upsertLink(Link link) {
    linksById[link.id] = link;
    notifyListeners();
  }

  void setRuntime(ColonyRuntimeState next) {
    runtime = next;
    notifyListeners();
  }

  void patchRuntime({
    Map<ColonyId, List<String>>? liveLogsBySessionTaskId,
    Map<String, Object?>? backendSnapshot,
    String? lastError,
    Map<String, Object?>? metadata,
  }) {
    runtime = runtime.copyWith(
      liveLogsBySessionTaskId: liveLogsBySessionTaskId,
      backendSnapshot: backendSnapshot,
      lastError: lastError,
      metadata: metadata,
    );
    notifyListeners();
  }

  ColonySelection selectWorld(ColonyId id) {
    selection = ColonySelection.world(id);
    notifyListeners();
    return selection;
  }

  ColonySelection selectZone(ColonyId id) {
    selection = ColonySelection.zone(id);
    notifyListeners();
    return selection;
  }

  ColonySelection selectBuilding(ColonyId id) {
    selection = ColonySelection.building(id);
    notifyListeners();
    return selection;
  }

  ColonySelection selectWorker(ColonyId id) {
    selection = ColonySelection.worker(id);
    notifyListeners();
    return selection;
  }

  ColonySelection selectSessionTask(ColonyId id) {
    selection = ColonySelection.sessionTask(id);
    notifyListeners();
    return selection;
  }

  ColonySelection selectLink(ColonyId id) {
    selection = ColonySelection.link(id);
    notifyListeners();
    return selection;
  }

  void notifyDomainChanged() {
    notifyListeners();
  }
}
