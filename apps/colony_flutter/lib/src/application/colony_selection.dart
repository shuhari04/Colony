import '../domain/colony_ids.dart';

enum ColonySelectionKind { none, world, zone, building, worker, sessionTask, link }

class ColonySelection {
  final ColonySelectionKind kind;
  final ColonyId id;

  const ColonySelection._(this.kind, this.id);

  const ColonySelection.none() : this._(ColonySelectionKind.none, '');
  const ColonySelection.world(ColonyId id) : this._(ColonySelectionKind.world, id);
  const ColonySelection.zone(ColonyId id) : this._(ColonySelectionKind.zone, id);
  const ColonySelection.building(ColonyId id) : this._(ColonySelectionKind.building, id);
  const ColonySelection.worker(ColonyId id) : this._(ColonySelectionKind.worker, id);
  const ColonySelection.sessionTask(ColonyId id) : this._(ColonySelectionKind.sessionTask, id);
  const ColonySelection.link(ColonyId id) : this._(ColonySelectionKind.link, id);

  bool get isNone => kind == ColonySelectionKind.none;
}
