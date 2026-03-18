enum EntityKind { building, unit }

enum SessionKind { codex, claude, openclaw, generic }

enum SessionStatus { unknown, running, stopped, failed, throttled }

class NodeRef {
  final String id; // "local" or ssh host alias
  const NodeRef(this.id);
  bool get isLocal => id == 'local';
}

class Project {
  final String id;
  final String nodeId;
  final String name;
  double x;
  double y;
  Project({required this.id, required this.nodeId, required this.name, required this.x, required this.y});
}

class Session {
  final NodeRef node;
  final String name;
  final SessionKind kind;
  SessionStatus status;

  double x;
  double y;

  Session({
    required this.node,
    required this.name,
    required this.kind,
    required this.x,
    required this.y,
    this.status = SessionStatus.unknown,
  });

  String get address => '@${node.id}:$name';
}
