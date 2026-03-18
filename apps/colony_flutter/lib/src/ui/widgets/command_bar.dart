import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/tokens.dart';
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
    if (q.isEmpty) {
      _suggestions = widget.state.sessions.map((s) => s.address).toList(growable: false);
      return;
    }

    final all = widget.state.sessions.map((s) => s.address).toList(growable: false);
    final filtered = all.where((a) => a.toLowerCase().contains(q.toLowerCase())).toList(growable: false);
    _suggestions = filtered.take(10).toList(growable: false);
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
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowDown): () {
          if (_suggestions.isEmpty) return;
          setState(() => _highlight = (_highlight + 1).clamp(0, _suggestions.length - 1));
        },
        const SingleActivator(LogicalKeyboardKey.arrowUp): () {
          if (_suggestions.isEmpty) return;
          setState(() => _highlight = (_highlight - 1).clamp(0, _suggestions.length - 1));
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_suggestions.isEmpty) return;
          setState(() => _suggestions = const []);
        },
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (_suggestions.isEmpty) return;
          final picked = _suggestions[_highlight];
          _c.text = '$picked ';
          _c.selection = TextSelection.fromPosition(TextPosition(offset: _c.text.length));
          setState(() {
            _suggestions = const [];
            _highlight = 0;
          });
          _focus.requestFocus();
        },
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          TextField(
            controller: _c,
            focusNode: _focus,
            onChanged: (t) => setState(() => _recomputeSuggestions(t)),
            onSubmitted: (_) => _submit(),
            style: const TextStyle(fontSize: 13, color: ColonyColors.text0),
            decoration: const InputDecoration(
              hintText: '@session message  (or send to selected session)',
              prefixIcon: Icon(Icons.terminal, size: 18),
            ),
          ),
          if (_suggestions.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              top: 48,
              child: Container(
                decoration: BoxDecoration(
                  color: ColonyColors.surface0,
                  borderRadius: BorderRadius.circular(ColonyRadii.r2),
                  border: Border.all(color: ColonyColors.border0),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < _suggestions.length; i++)
                      _SuggestionRow(
                        text: _suggestions[i],
                        highlighted: i == _highlight,
                        onTap: () {
                          _c.text = '${_suggestions[i]} ';
                          _c.selection = TextSelection.fromPosition(TextPosition(offset: _c.text.length));
                          setState(() {
                            _suggestions = const [];
                            _highlight = 0;
                          });
                          _focus.requestFocus();
                        },
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  final String text;
  final bool highlighted;
  final VoidCallback onTap;

  const _SuggestionRow({required this.text, required this.highlighted, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bg = highlighted ? ColonyColors.surface1 : ColonyColors.surface0;
    final border = highlighted ? ColonyColors.accentCyan.withValues(alpha: 0.6) : ColonyColors.border0;
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: bg, border: Border(bottom: BorderSide(color: border.withValues(alpha: 0.4)))),
        child: Row(
          children: [
            const Icon(Icons.alternate_email, size: 16, color: ColonyColors.text1),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: ColonyColors.text0))),
          ],
        ),
      ),
    );
  }
}
