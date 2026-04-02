import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/tokens.dart';
import '../../model/entities.dart';
import '../../state/app_state.dart';

class CommandBar extends StatefulWidget {
  final AppState state;
  const CommandBar({super.key, required this.state});

  @override
  State<CommandBar> createState() => _CommandBarState();
}

class _CommandBarState extends State<CommandBar> {
  final TextEditingController _c = TextEditingController();
  final FocusNode _focus = FocusNode();

  List<String> _suggestions = const [];
  int _highlight = 0;

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _recomputeSuggestions(String text) {
    _suggestions = const [];
    _highlight = 0;

    if (!text.startsWith('@')) return;
    final parts = text.split(' ');
    final token = parts.first;
    if (!token.startsWith('@')) return;

    final q = token.substring(1);
    final all = widget.state.sessions
        .map((s) => s.address)
        .toList(growable: false);
    if (q.isEmpty) {
      _suggestions = all.take(10).toList(growable: false);
      return;
    }

    final filtered = all
        .where((a) => a.toLowerCase().contains(q.toLowerCase()))
        .take(10)
        .toList(growable: false);
    _suggestions = filtered;
  }

  Future<void> _submit() async {
    final raw = _c.text.trim();
    if (raw.isEmpty) return;

    String? addr;
    String msg = raw;

    if (raw.startsWith('@')) {
      final idx = raw.indexOf(' ');
      if (idx > 1) {
        addr = widget.state.resolveAddressShorthand(raw.substring(0, idx));
        msg = raw.substring(idx + 1).trimLeft();
      } else {
        return;
      }
    }

    if (msg.isEmpty) return;
    await widget.state.sendToSelection(msg, addressOverride: addr);
    _c.clear();
    _suggestions = const [];
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.state.selection.kind == SelectionKind.session
        ? widget.state.sessionByAddress(widget.state.selection.id)
        : null;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowDown): () {
          if (_suggestions.isEmpty) return;
          setState(
            () =>
                _highlight = (_highlight + 1).clamp(0, _suggestions.length - 1),
          );
        },
        const SingleActivator(LogicalKeyboardKey.arrowUp): () {
          if (_suggestions.isEmpty) return;
          setState(
            () =>
                _highlight = (_highlight - 1).clamp(0, _suggestions.length - 1),
          );
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_suggestions.isEmpty) return;
          setState(() => _suggestions = const []);
        },
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (_suggestions.isEmpty) return;
          _pickSuggestion(_suggestions[_highlight]);
        },
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: ColonySpacing.s2),
            decoration: BoxDecoration(
              color: ColonyColors.bg1.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(ColonyRadii.r2),
              border: Border.all(color: ColonyColors.border0),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.terminal_rounded,
                  size: 18,
                  color: ColonyColors.text1,
                ),
                if (selected != null) ...[
                  const SizedBox(width: ColonySpacing.s2),
                  _TargetPill(session: selected),
                ] else ...[
                  const SizedBox(width: ColonySpacing.s2),
                  const Text(
                    'Global',
                    style: TextStyle(
                      fontSize: 12,
                      color: ColonyColors.text1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(width: ColonySpacing.s2),
                Expanded(
                  child: TextField(
                    controller: _c,
                    focusNode: _focus,
                    onChanged: (t) => setState(() => _recomputeSuggestions(t)),
                    onSubmitted: (_) => _submit(),
                    style: const TextStyle(
                      fontSize: 13,
                      color: ColonyColors.text0,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      hintText: '@session message or send to selected worker',
                    ),
                  ),
                ),
                const SizedBox(width: ColonySpacing.s2),
                FilledButton.tonalIcon(
                  onPressed: _submit,
                  style: const ButtonStyle(
                    minimumSize: WidgetStatePropertyAll(Size(0, 34)),
                    backgroundColor: WidgetStatePropertyAll(
                      ColonyColors.surface2,
                    ),
                    foregroundColor: WidgetStatePropertyAll(ColonyColors.text0),
                  ),
                  icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                  label: const Text('Send'),
                ),
              ],
            ),
          ),
          if (_suggestions.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              top: 54,
              child: Container(
                decoration: BoxDecoration(
                  color: ColonyColors.surface0,
                  borderRadius: BorderRadius.circular(ColonyRadii.r2),
                  border: Border.all(color: ColonyColors.border0),
                  boxShadow: ColonyShadows.panel,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < _suggestions.length; i++)
                      _SuggestionRow(
                        text: _suggestions[i],
                        highlighted: i == _highlight,
                        onTap: () => _pickSuggestion(_suggestions[i]),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _pickSuggestion(String value) {
    _c.text = '$value ';
    _c.selection = TextSelection.fromPosition(
      TextPosition(offset: _c.text.length),
    );
    setState(() {
      _suggestions = const [];
      _highlight = 0;
    });
    _focus.requestFocus();
  }
}

class _TargetPill extends StatelessWidget {
  final Session session;
  const _TargetPill({required this.session});

  @override
  Widget build(BuildContext context) {
    final color = switch (session.kind) {
      SessionKind.codex => ColonyColors.accentCyan,
      SessionKind.claude => ColonyColors.info,
      SessionKind.openclaw => ColonyColors.success,
      SessionKind.generic => ColonyColors.text1,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        session.address,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  final String text;
  final bool highlighted;
  final VoidCallback onTap;

  const _SuggestionRow({
    required this.text,
    required this.highlighted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = highlighted ? ColonyColors.surface1 : ColonyColors.surface0;
    final border = highlighted
        ? ColonyColors.accentCyan.withValues(alpha: 0.5)
        : ColonyColors.border0;
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          border: Border(
            bottom: BorderSide(color: border.withValues(alpha: 0.45)),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.alternate_email_rounded,
              size: 16,
              color: ColonyColors.text1,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 12, color: ColonyColors.text0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
