import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../model/board.dart';

class ServerConfigDialogResult {
  final String alias;
  final String host;
  final String password;

  const ServerConfigDialogResult({
    required this.alias,
    required this.host,
    required this.password,
  });
}

class ServerConfigDialog extends StatefulWidget {
  final ServerConfig? initial;

  const ServerConfigDialog({super.key, this.initial});

  @override
  State<ServerConfigDialog> createState() => _ServerConfigDialogState();
}

class _ServerConfigDialogState extends State<ServerConfigDialog> {
  late final TextEditingController _alias;
  late final TextEditingController _host;
  late final TextEditingController _password;

  @override
  void initState() {
    super.initState();
    _alias = TextEditingController(text: widget.initial?.alias ?? '');
    _host = TextEditingController(text: widget.initial?.host ?? '');
    _password = TextEditingController(text: widget.initial?.password ?? '');
  }

  @override
  void dispose() {
    _alias.dispose();
    _host.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ColonyColors.surface0,
      title: const Text('Configure Server'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _alias,
              decoration: const InputDecoration(labelText: 'Alias'),
            ),
            const SizedBox(height: ColonySpacing.s3),
            TextField(
              controller: _host,
              decoration: const InputDecoration(labelText: 'Host'),
            ),
            const SizedBox(height: ColonySpacing.s3),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              ServerConfigDialogResult(
                alias: _alias.text.trim(),
                host: _host.text.trim(),
                password: _password.text,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
