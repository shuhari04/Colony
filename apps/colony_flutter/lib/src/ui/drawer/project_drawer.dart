import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../model/entities.dart';
import '../../state/app_state.dart';
import '../dialogs/new_session_dialog.dart';

class ProjectDrawer extends StatelessWidget {
  final AppState state;
  final String projectId;
  const ProjectDrawer({super.key, required this.state, required this.projectId});

  @override
  Widget build(BuildContext context) {
    final p = state.projectById(projectId) ?? state.projects.first;
    final nodeId = p.nodeId;
    final nodeSessions = state.sessions.where((s) => s.node.id == nodeId).toList(growable: false);
    final availableKinds = state.sessionKindsForNode(nodeId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.home_work_outlined, size: 18, color: ColonyColors.text1),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                p.name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            _AddRemoteButton(state: state),
            const SizedBox(width: 8),
            _NewWorkerButton(state: state, nodeId: nodeId, availableKinds: availableKinds),
          ],
        ),
        const SizedBox(height: 14),
        const Text('Sessions', style: TextStyle(fontSize: 12, color: ColonyColors.text1)),
        const SizedBox(height: 8),
        for (final s in nodeSessions) _SessionRow(state: state, s: s),
        if (nodeSessions.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No sessions running', style: TextStyle(color: ColonyColors.text1)),
          ),
      ],
    );
  }
}

class _SessionRow extends StatelessWidget {
  final AppState state;
  final Session s;
  const _SessionRow({required this.state, required this.s});

  @override
  Widget build(BuildContext context) {
    final kind = switch (s.kind) {
      SessionKind.codex => 'codex',
      SessionKind.claude => 'claude',
      SessionKind.openclaw => 'openclaw',
      SessionKind.generic => 'agent',
    };
    return InkWell(
      onTap: () => state.selectSession(s),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: ColonyColors.surface1.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(ColonyRadii.r2),
          border: Border.all(color: ColonyColors.border0),
        ),
        child: Row(
          children: [
            const Icon(Icons.person_pin_circle_outlined, size: 16, color: ColonyColors.text1),
            const SizedBox(width: 10),
            Expanded(child: Text(s.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
            Text(kind, style: const TextStyle(fontSize: 11, color: ColonyColors.muted0)),
          ],
        ),
      ),
    );
  }
}

class _NewWorkerButton extends StatelessWidget {
  final AppState state;
  final String nodeId;
  final List<SessionKind> availableKinds;
  const _NewWorkerButton({required this.state, required this.nodeId, required this.availableKinds});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: () async {
        final res = await showDialog<NewSessionResult>(
          context: context,
          builder: (context) => NewSessionDialog(
            allowedKinds: availableKinds,
            initialKind: availableKinds.first,
            nodeId: nodeId,
          ),
        );
        if (res == null) return;
        await state.startNewSession(res.kind, res.name, model: res.model, nodeId: nodeId);
      },
      icon: const Icon(Icons.add, size: 16),
      label: const Text('New', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

class _AddRemoteButton extends StatelessWidget {
  final AppState state;
  const _AddRemoteButton({required this.state});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () async {
        final res = await showDialog<_RemoteResult>(
          context: context,
          builder: (context) => const _RemoteDialog(),
        );
        if (res == null) return;
        await state.addRemoteHost(res.host, password: res.password);
      },
      icon: const Icon(Icons.sensors_outlined, size: 16),
      label: const Text('Remote', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

class _RemoteResult {
  final String host;
  final String password;
  _RemoteResult(this.host, this.password);
}

class _RemoteDialog extends StatefulWidget {
  const _RemoteDialog();

  @override
  State<_RemoteDialog> createState() => _RemoteDialogState();
}

class _RemoteDialogState extends State<_RemoteDialog> {
  final TextEditingController _host = TextEditingController(text: 'leitong@192.168.1.30');
  final TextEditingController _password = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _host.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add remote'),
      backgroundColor: ColonyColors.surface0,
      surfaceTintColor: ColonyColors.surface0,
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _host,
              decoration: const InputDecoration(labelText: 'SSH host (user@host)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password (optional if key-based)'),
            ),
            const SizedBox(height: 6),
            if (_error != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(_error!, style: const TextStyle(fontSize: 11, color: ColonyColors.danger)),
              ),
            const SizedBox(height: 4),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Password is passed to colony via env and used with sshpass (if installed).',
                style: TextStyle(fontSize: 11, color: ColonyColors.text1),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final host = _host.text.trim();
            if (host.isEmpty) {
              setState(() => _error = 'Host is required.');
              return;
            }
            setState(() => _error = null);
            Navigator.of(context).pop(_RemoteResult(host, _password.text));
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
