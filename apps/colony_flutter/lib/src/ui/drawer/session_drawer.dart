import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../model/entities.dart';
import '../../state/app_state.dart';

class SessionDrawer extends StatefulWidget {
  final AppState state;
  final String address;
  const SessionDrawer({super.key, required this.state, required this.address});

  @override
  State<SessionDrawer> createState() => _SessionDrawerState();
}

class _SessionDrawerState extends State<SessionDrawer> {
  final TextEditingController _composer = TextEditingController();
  final TextEditingController _model = TextEditingController(text: 'gpt-5.2');
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _composer.dispose();
    _model.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logs = widget.state.logsFor(widget.address);
    final s = widget.state.sessionByAddress(widget.address);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.terminal, size: 18, color: ColonyColors.text1),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.address,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: 'Stop',
              onPressed: () async {
                // Best-effort stop; refresh the list after.
                try {
                  await widget.state.sendToSelection('/exit', addressOverride: widget.address);
                } catch (_) {}
              },
              icon: const Icon(Icons.stop_circle_outlined, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (s?.kind == SessionKind.codex)
          Row(
            children: [
              const Icon(Icons.tune, size: 18, color: ColonyColors.text1),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _model,
                  decoration: const InputDecoration(hintText: 'codex model (e.g. gpt-5.2)'),
                  onSubmitted: (_) => _setModel(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _setModel,
                child: const Text('Set'),
              ),
            ],
          ),
        if (s?.kind == SessionKind.codex) const SizedBox(height: 10),
        Container(
          height: 320,
          decoration: BoxDecoration(
            color: ColonyColors.bg1.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(ColonyRadii.r2),
            border: Border.all(color: ColonyColors.border0),
          ),
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(10),
            itemCount: logs.length,
            itemBuilder: (context, i) {
              final l = logs[i];
              return Text(
                l,
                style: const TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 12,
                  height: 1.25,
                  color: ColonyColors.text0,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _composer,
                minLines: 1,
                maxLines: 5,
                decoration: const InputDecoration(hintText: 'Send to this session'),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: _send,
              child: const Text('Send'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _send() async {
    final msg = _composer.text.trimRight();
    if (msg.isEmpty) return;
    _composer.clear();
    await widget.state.sendToSelection(msg, addressOverride: widget.address);
  }

  Future<void> _setModel() async {
    final m = _model.text.trim();
    if (m.isEmpty) return;
    await widget.state.sendToSelection('/model $m', addressOverride: widget.address);
  }
}
