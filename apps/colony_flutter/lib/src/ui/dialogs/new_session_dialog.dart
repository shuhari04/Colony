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
  const NewSessionDialog({super.key});

  @override
  State<NewSessionDialog> createState() => _NewSessionDialogState();
}

class _NewSessionDialogState extends State<NewSessionDialog> {
  SessionKind _kind = SessionKind.codex;
  final TextEditingController _name = TextEditingController(text: 'codex1');
  final TextEditingController _model = TextEditingController(text: 'gpt-5.2');
  String? _error;

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
              items: const [
                DropdownMenuItem(value: SessionKind.codex, child: Text('codex')),
                DropdownMenuItem(value: SessionKind.claude, child: Text('claude')),
              ],
              onChanged: (v) => setState(() {
                _kind = v ?? SessionKind.codex;
                if (_kind == SessionKind.codex && _name.text.trim().isEmpty) _name.text = 'codex1';
                if (_kind == SessionKind.claude && _name.text.trim().isEmpty) _name.text = 'claude1';
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
                _kind == SessionKind.codex
                    ? 'Creates @local:<name> and starts: codex --model <model>'
                    : 'Creates @local:<name> and starts: claude',
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
}
