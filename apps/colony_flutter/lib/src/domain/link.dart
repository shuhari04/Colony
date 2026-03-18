import 'colony_ids.dart';

enum LinkType { ssh, relay, mobile }

enum LinkStatus { disconnected, connecting, connected, degraded }

class Link {
  final ColonyId id;
  final ColonyId fromWorldId;
  final ColonyId toWorldId;
  final LinkType type;
  final LinkStatus status;
  final String configSummary;
  final Map<String, Object?> metadata;

  const Link({
    required this.id,
    required this.fromWorldId,
    required this.toWorldId,
    required this.type,
    this.status = LinkStatus.disconnected,
    required this.configSummary,
    this.metadata = const {},
  });

  Link copyWith({
    ColonyId? id,
    ColonyId? fromWorldId,
    ColonyId? toWorldId,
    LinkType? type,
    LinkStatus? status,
    String? configSummary,
    Map<String, Object?>? metadata,
  }) {
    return Link(
      id: id ?? this.id,
      fromWorldId: fromWorldId ?? this.fromWorldId,
      toWorldId: toWorldId ?? this.toWorldId,
      type: type ?? this.type,
      status: status ?? this.status,
      configSummary: configSummary ?? this.configSummary,
      metadata: metadata ?? this.metadata,
    );
  }
}
