import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../model/entities.dart';
import '../services/colony_cli.dart';

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
  final List<Project> projects = [
    Project(id: 'p_local', nodeId: 'local', name: 'Local', x: 1.0, y: 1.0),
  ];
  final List<Session> sessions = [];
  final Map<String, String> _sshPasswordByHost = {}; // host -> password (in-memory for now)

  bool buildMode = false;
  Selection selection = const Selection.none();

  final Map<String, List<String>> _sessionLogs = {};
  LogStream? _activeLogStream;

  ColonyCli? _cli;
  Map<String, dynamic>? codexRateLimit;
  String? lastError;

  Future<void> bootstrap() async {
    final bin = await ColonyCli.discoverBin();
    _cli = ColonyCli(bin ?? 'colony');
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
    }
    notifyListeners();
  }

  Future<void> _refreshSessions() async {
    final cli = _cli;
    if (cli == null) return;
    final addresses = <String>[];
    for (final p in projects) {
      final t = p.nodeId == 'local' ? 'local' : p.nodeId;
      final env = _envForTarget(t);
      final one = await cli.listSessions(target: t, env: env);
      addresses.addAll(one);
    }
    sessions
      ..clear()
      ..addAll(_sessionsFromAddresses(addresses));
  }

  Future<void> _refreshRateLimit() async {
    final cli = _cli;
    if (cli == null) return;
    codexRateLimit = await cli.codexRateLimitJson();
  }

  void toggleBuildMode(bool enabled) {
    buildMode = enabled;
    notifyListeners();
  }

  void selectProject(Project p) {
    selection = Selection.project(p.id);
    _stopStreaming();
    notifyListeners();
  }

  void selectSession(Session s) {
    selection = Selection.session(s.address);
    _startStreaming(s.address);
    notifyListeners();
  }

  void clearSelection() {
    selection = const Selection.none();
    _stopStreaming();
    notifyListeners();
  }

  List<String> logsFor(String address) => _sessionLogs[address] ?? const [];

  String resolveAddressShorthand(String raw) {
    // Allow "@foo" to target an existing "@local:foo" / "@host:foo" session if present.
    if (!raw.startsWith('@')) return raw;
    if (raw.contains(':')) return raw;
    final needle = raw.substring(1).toLowerCase();
    if (needle.isEmpty) return raw;

    final exact = sessions.where((s) => s.name.toLowerCase() == needle || s.address.toLowerCase() == raw.toLowerCase()).toList();
    if (exact.isNotEmpty) return exact.first.address;

    final fuzzy = sessions.where((s) => s.address.toLowerCase().contains(needle)).toList();
    if (fuzzy.isNotEmpty) return fuzzy.first.address;

    // Fall back to local session name.
    return '@local:$needle';
  }

  Future<void> sendToSelection(String text, {String? addressOverride}) async {
    final cli = _cli;
    if (cli == null) return;
    final addrRaw = addressOverride ?? (selection.kind == SelectionKind.session ? selection.id : null);
    final addr = (addrRaw == null) ? null : resolveAddressShorthand(addrRaw);
    if (addr == null || addr.isEmpty) {
      lastError = 'No session selected';
      notifyListeners();
      return;
    }
    lastError = null;
    notifyListeners();
    try {
      await cli.send(addr, text, env: _envForAddress(addr));
    } catch (e) {
      lastError = '$e';
      notifyListeners();
    }
  }

  Future<void> startNewSession(SessionKind kind, String name, {String? model, String nodeId = 'local'}) async {
    final cli = _cli;
    if (cli == null) return;
    final addr = '@$nodeId:$name';
    final codexModel = (model != null && model.trim().isNotEmpty) ? model.trim() : 'gpt-5.2';
    final cmd = _commandForSession(kind: kind, nodeId: nodeId, codexModel: codexModel, colonyBin: cli.binPath);
    lastError = null;
    notifyListeners();
    try {
      await cli.startSession(addr, cmd, env: _envForAddress(addr));
      await _refreshSessions();
      final s = sessions.firstWhere(
        (x) => x.address == addr,
        orElse: () => Session(node: NodeRef(nodeId), name: name, kind: kind, x: 3, y: 2),
      );
      selectSession(s);
    } catch (e) {
      lastError = '$e';
      notifyListeners();
    }
  }

  List<String> _commandForSession({required SessionKind kind, required String nodeId, required String codexModel, required String colonyBin}) {
    final isLocal = nodeId == 'local';
    if (isLocal) {
      return switch (kind) {
        SessionKind.codex => <String>[colonyBin, 'agent', 'codex', '--model', codexModel],
        SessionKind.claude => <String>[colonyBin, 'agent', 'claude'],
        SessionKind.generic => <String>['/usr/bin/env', 'bash', '-lc', 'cat'],
      };
    }

    // Remote: run a tiny bash agent loop without requiring Colony to be installed on the remote.
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
    // Single-line bash loop; tmux will run this on the remote machine.
    // Reads one prompt per line and streams `codex exec --json` output.
    final m = model.replaceAll("'", ""); // model already validated in UI; keep it simple.
    final script = r'''
set -euo pipefail
MODEL="''' +
        m +
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
    return script.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).join('; ');
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
    return script.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).join('; ');
  }

  Project get localProject => projects.firstWhere((p) => p.nodeId == 'local');

  void moveProject(String projectId, double dx, double dy) {
    final idx = projects.indexWhere((p) => p.id == projectId);
    if (idx < 0) return;
    projects[idx].x += dx;
    projects[idx].y += dy;
    notifyListeners();
  }

  void moveSession(String address, double dx, double dy) {
    final idx = sessions.indexWhere((s) => s.address == address);
    if (idx < 0) return;
    sessions[idx].x += dx;
    sessions[idx].y += dy;
    notifyListeners();
  }

  void _startStreaming(String address) {
    _stopStreaming();
    final cli = _cli;
    if (cli == null) return;
    startLogStream(cli, address, env: _envForAddress(address)).then((ls) {
      _activeLogStream = ls;
      ls.lines.listen((line) {
        final buf = _sessionLogs.putIfAbsent(address, () => <String>[]);
        buf.add(line);
        if (buf.length > 2000) {
          buf.removeRange(0, buf.length - 2000);
        }
        notifyListeners();
      });
    }).catchError((e) {
      lastError = '$e';
      notifyListeners();
    });
  }

  void _stopStreaming() {
    _activeLogStream?.stop();
    _activeLogStream = null;
  }

  List<Session> _sessionsFromAddresses(List<String> addresses) {
    // Layout: scatter sessions around each node's base by stable hashing.
    final out = <Session>[];
    for (final a in addresses) {
      final parsed = _parseAddress(a);
      if (parsed == null) continue;
      final (node, name) = parsed;
      final base = _projectForNode(node);
      final h = name.codeUnits.fold<int>(0, (acc, v) => (acc * 31 + v) & 0x7fffffff);
      final r = 1.8 + (h % 120) / 100.0;
      final angle = (h % 360) * 3.1415926 / 180.0;
      out.add(
        Session(
          node: NodeRef(node),
          name: name,
          kind: _inferKind(name),
          x: base.x + r * math.cos(angle),
          y: base.y + r * math.sin(angle),
          status: SessionStatus.unknown,
        ),
      );
    }
    return out;
  }

  SessionKind _inferKind(String name) {
    final n = name.toLowerCase();
    if (n.contains('codex')) return SessionKind.codex;
    if (n.contains('claude')) return SessionKind.claude;
    return SessionKind.generic;
  }

  (String, String)? _parseAddress(String s) {
    // "@local:foo" or "@host:foo"
    if (!s.startsWith('@')) return null;
    final body = s.substring(1);
    final idx = body.indexOf(':');
    if (idx < 0) return null;
    final node = body.substring(0, idx);
    final name = body.substring(idx + 1);
    if (node.isEmpty || name.isEmpty) return null;
    return (node, name);
  }

  Project _projectForNode(String nodeId) {
    final existing = projects.where((p) => p.nodeId == nodeId).toList();
    if (existing.isNotEmpty) return existing.first;

    // Create a new base for this node with a deterministic, non-overlapping placement.
    final i = projects.length;
    final local = localProject;
    final p = Project(
      id: 'p_${nodeId.hashCode}',
      nodeId: nodeId,
      name: nodeId == 'local' ? 'Local' : nodeId,
      x: local.x + 7.0 + (i - 1) * 6.5,
      y: local.y + 1.5 + (i - 1) * 2.6,
    );
    projects.add(p);
    return p;
  }

  Project? projectById(String id) => projects.where((p) => p.id == id).firstOrNull;

  Session? sessionByAddress(String address) => sessions.where((s) => s.address == address).firstOrNull;

  String nodeIdForProjectId(String projectId) {
    final p = projectById(projectId);
    return p?.nodeId ?? 'local';
  }

  Map<String, String> _envForTarget(String target) {
    if (target == 'local') return const {};
    final pw = _sshPasswordByHost[target];
    if (pw == null || pw.isEmpty) return const {};
    return {'COLONY_SSH_PASSWORD': pw};
  }

  Map<String, String> _envForAddress(String address) {
    final parsed = _parseAddress(address);
    if (parsed == null) return const {};
    final (nodeId, _) = parsed;
    if (nodeId == 'local') return const {};
    final pw = _sshPasswordByHost[nodeId];
    if (pw == null || pw.isEmpty) return const {};
    return {'COLONY_SSH_PASSWORD': pw};
  }

  Future<void> addRemoteHost(String host, {String? password}) async {
    final h = host.trim();
    if (h.isEmpty) return;
    if (password != null && password.isNotEmpty) {
      _sshPasswordByHost[h] = password;
    }
    _projectForNode(h);
    await refresh();
  }

  @override
  void dispose() {
    _stopStreaming();
    super.dispose();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
