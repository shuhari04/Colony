import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../model/entities.dart';

class NewSessionResult {
  final SessionKind kind;
  final String name;
  final String? model; // codex only; optional
  NewSessionResult(this.kind, this.name, {this.model});
}

class NewSessionDialog extends StatefulWidget {
  final List<SessionKind> allowedKinds;
  final SessionKind initialKind;
  final String? initialName;
  final String nodeId;

  const NewSessionDialog({
    super.key,
    this.allowedKinds = const [SessionKind.codex, SessionKind.claude],
    this.initialKind = SessionKind.codex,
    this.initialName,
    this.nodeId = 'local',
  });

  @override
  State<NewSessionDialog> createState() => _NewSessionDialogState();
}

class _NewSessionDialogState extends State<NewSessionDialog> {
  late SessionKind _kind;
  late final TextEditingController _name;
  final TextEditingController _model = TextEditingController(text: 'gpt-5.2');
  String? _error;

  @override
  void initState() {
    super.initState();
    _kind = widget.allowedKinds.contains(widget.initialKind) ? widget.initialKind : widget.allowedKinds.first;
    _name = TextEditingController(text: widget.initialName ?? _defaultNameFor(_kind));
  }

  @override
  void dispose() {
    _name.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New session'),
      backgroundColor: ColonyColors.surface0,
      surfaceTintColor: ColonyColors.surface0,
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<SessionKind>(
              initialValue: _kind,
              items: widget.allowedKinds
                  .map(
                    (kind) => DropdownMenuItem(
                      value: kind,
                      child: Text(_kindLabel(kind)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (v) => setState(() {
                final previous = _kind;
                _kind = v ?? widget.allowedKinds.first;
                if (_name.text.trim().isEmpty || _name.text.trim() == _defaultNameFor(previous)) {
                  _name.text = _defaultNameFor(_kind);
                }
              }),
              decoration: const InputDecoration(labelText: 'Type'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Session name (tmux session)'),
            ),
            const SizedBox(height: 10),
            if (_kind == SessionKind.codex)
              TextField(
                controller: _model,
                decoration: const InputDecoration(labelText: 'Model (codex --model)'),
              ),
            const SizedBox(height: 6),
            if (_error != null) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: const TextStyle(fontSize: 11, color: ColonyColors.danger),
                ),
              ),
              const SizedBox(height: 6),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _descriptionForKind(_kind, widget.nodeId),
                style: const TextStyle(fontSize: 11, color: ColonyColors.text1),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) {
              setState(() => _error = 'Session name is required.');
              return;
            }
            final model = _kind == SessionKind.codex ? _model.text.trim() : null;
            if (_kind == SessionKind.codex && (model == null || model.isEmpty)) {
              setState(() => _error = 'Model is required for codex sessions.');
              return;
            }
            // Avoid passing shell metacharacters into zsh -lc.
            final ok = RegExp(r'^[a-zA-Z0-9._-]+$');
            if (_kind == SessionKind.codex && model != null && !ok.hasMatch(model)) {
              setState(() => _error = 'Invalid model name (allowed: a-z A-Z 0-9 . _ -).');
              return;
            }
            setState(() => _error = null);
            Navigator.of(context).pop(NewSessionResult(_kind, name, model: (model?.isEmpty ?? true) ? null : model));
          },
          child: const Text('Create'),
        ),
      ],
    );
  }

  String _kindLabel(SessionKind kind) {
    return switch (kind) {
      SessionKind.codex => 'codex',
      SessionKind.claude => 'claude',
      SessionKind.openclaw => 'openclaw',
      SessionKind.generic => 'generic',
    };
  }

  String _defaultNameFor(SessionKind kind) {
    return switch (kind) {
      SessionKind.codex => 'codex1',
      SessionKind.claude => 'claude1',
      SessionKind.openclaw => 'openclaw1',
      SessionKind.generic => 'agent1',
    };
  }

  String _descriptionForKind(SessionKind kind, String nodeId) {
    final prefix = 'Creates a ${_kindLabel(kind)} session on $nodeId via colony session create';
    return switch (kind) {
      SessionKind.codex => '$prefix with model selection',
      SessionKind.claude => prefix,
      SessionKind.openclaw => prefix,
      SessionKind.generic => '$prefix (generic compatibility mode)',
    };
  }
}
