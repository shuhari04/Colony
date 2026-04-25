import 'dart:convert';

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../infrastructure/colony_stream_event.dart';
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
    final events = widget.state.eventsFor(widget.address);
    final logs = widget.state.logsFor(widget.address);
    final session = widget.state.sessionByAddress(widget.address);
    final color = switch (session?.kind) {
      SessionKind.codex => ColonyColors.accentCyan,
      SessionKind.claude => ColonyColors.info,
      SessionKind.openclaw => ColonyColors.success,
      SessionKind.generic || null => ColonyColors.text1,
    };
    final transcript = events.isNotEmpty
        ? _buildTranscriptFromEvents(events, session)
        : _buildTranscript(logs, session);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });

    return Column(
      children: [
        _SessionHeader(
          address: widget.address,
          session: session,
          accent: color,
          transcript: transcript,
          onDelete: () => _confirmDeleteSession(session),
          onStop: () async {
            try {
              await widget.state.sendToSelection(
                '/exit',
                addressOverride: widget.address,
              );
            } catch (_) {}
          },
        ),
        const SizedBox(height: ColonySpacing.s4),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 8,
                child: _ChatPane(
                  scroll: _scroll,
                  transcript: transcript,
                  accent: color,
                ),
              ),
              const SizedBox(width: ColonySpacing.s4),
              Expanded(
                flex: 4,
                child: _ActionPane(
                  session: session,
                  accent: color,
                  model: _model,
                  onSetModel: _setModel,
                  transcript: transcript,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: ColonySpacing.s4),
        _ComposerPane(controller: _composer, accent: color, onSend: _send),
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
    await widget.state.sendToSelection(
      '/model $m',
      addressOverride: widget.address,
    );
  }

  Future<void> _confirmDeleteSession(Session? session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ColonyColors.surface0,
        title: const Text('Delete Session'),
        content: Text(
          'Delete ${session?.name ?? widget.address}? This will stop the running session.',
          style: const TextStyle(height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ColonyColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.state.deleteSession(widget.address);
    }
  }
}

class _SessionHeader extends StatelessWidget {
  final String address;
  final Session? session;
  final Color accent;
  final List<_TranscriptEntry> transcript;
  final Future<void> Function() onDelete;
  final Future<void> Function() onStop;

  const _SessionHeader({
    required this.address,
    required this.session,
    required this.accent,
    required this.transcript,
    required this.onDelete,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final turns = transcript
        .where((entry) => entry.kind == _TranscriptEntryKind.user)
        .length;
    final responses = transcript
        .where((entry) => entry.kind == _TranscriptEntryKind.assistant)
        .length;

    return Container(
      padding: const EdgeInsets.all(ColonySpacing.s4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.12),
            ColonyColors.surface1.withValues(alpha: 0.94),
          ],
        ),
        borderRadius: BorderRadius.circular(ColonyRadii.r3),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: ColonyColors.surface0.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withValues(alpha: 0.35)),
              boxShadow: ColonyShadows.glowSmall(accent),
            ),
            child: const Icon(
              Icons.forum_rounded,
              size: 20,
              color: ColonyColors.text0,
            ),
          ),
          const SizedBox(width: ColonySpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session?.name ?? address,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  address,
                  style: const TextStyle(
                    fontSize: 12,
                    color: ColonyColors.text1,
                  ),
                ),
              ],
            ),
          ),
          _StatusChip(label: '$turns prompts', color: accent),
          const SizedBox(width: ColonySpacing.s2),
          _StatusChip(label: '$responses replies', color: ColonyColors.text1),
          const SizedBox(width: ColonySpacing.s2),
          _StatusChip(label: 'Streaming', color: accent),
          const SizedBox(width: ColonySpacing.s2),
          OutlinedButton.icon(
            onPressed: onStop,
            icon: const Icon(Icons.stop_circle_outlined, size: 16),
            label: const Text('Stop'),
          ),
          const SizedBox(width: ColonySpacing.s2),
          OutlinedButton.icon(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, size: 16),
            label: const Text('Delete'),
            style: OutlinedButton.styleFrom(
              foregroundColor: ColonyColors.danger,
              side: BorderSide(
                color: ColonyColors.danger.withValues(alpha: 0.55),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatPane extends StatelessWidget {
  final ScrollController scroll;
  final List<_TranscriptEntry> transcript;
  final Color accent;

  const _ChatPane({
    required this.scroll,
    required this.transcript,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            ColonyColors.bg1.withValues(alpha: 0.98),
            ColonyColors.bg0.withValues(alpha: 0.96),
          ],
        ),
        borderRadius: BorderRadius.circular(ColonyRadii.r3),
        border: Border.all(color: ColonyColors.border0),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(
              ColonySpacing.s4,
              ColonySpacing.s3,
              ColonySpacing.s4,
              ColonySpacing.s3,
            ),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: ColonyColors.border0)),
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                    boxShadow: ColonyShadows.glowSmall(ColonyColors.accentCyan),
                  ),
                ),
                const SizedBox(width: ColonySpacing.s2),
                const Text(
                  'Live Conversation',
                  style: TextStyle(
                    fontSize: 12,
                    color: ColonyColors.text1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${transcript.length} events',
                  style: const TextStyle(
                    fontSize: 11,
                    color: ColonyColors.muted0,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: transcript.isEmpty
                ? const _ChatEmptyState()
                : ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.all(ColonySpacing.s4),
                    itemCount: transcript.length,
                    itemBuilder: (context, index) {
                      final entry = transcript[index];
                      return Padding(
                        padding: const EdgeInsets.only(
                          bottom: ColonySpacing.s3,
                        ),
                        child: switch (entry.kind) {
                          _TranscriptEntryKind.system => _SystemEventCard(
                            entry: entry,
                          ),
                          _ => _ChatBubble(entry: entry, accent: accent),
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ChatEmptyState extends StatelessWidget {
  const _ChatEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(ColonySpacing.s5),
        decoration: BoxDecoration(
          color: ColonyColors.surface1.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(ColonyRadii.r3),
          border: Border.all(color: ColonyColors.border0),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              color: ColonyColors.text1,
              size: 28,
            ),
            SizedBox(height: ColonySpacing.s3),
            Text(
              'Waiting for the first turn',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: ColonySpacing.s2),
            Text(
              'New prompts, partial responses, and session state changes will appear here as a conversation timeline.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: ColonyColors.text1,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final _TranscriptEntry entry;
  final Color accent;

  const _ChatBubble({required this.entry, required this.accent});

  @override
  Widget build(BuildContext context) {
    final isUser = entry.kind == _TranscriptEntryKind.user;
    final bubbleColor = isUser
        ? accent.withValues(alpha: 0.16)
        : ColonyColors.surface1.withValues(alpha: 0.92);
    final borderColor = isUser
        ? accent.withValues(alpha: 0.45)
        : ColonyColors.border1.withValues(alpha: 0.72);
    final alignment = isUser
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return Column(
      crossAxisAlignment: alignment,
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: isUser ? 0 : 6,
            right: isUser ? 6 : 0,
            bottom: ColonySpacing.s1,
          ),
          child: Row(
            mainAxisAlignment: isUser
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              if (!isUser) ...[
                _AvatarChip(
                  icon: Icons.smart_toy_outlined,
                  color: accent,
                  label: entry.label ?? 'Agent',
                ),
              ] else ...[
                _AvatarChip(
                  icon: Icons.person_outline_rounded,
                  color: ColonyColors.text1,
                  label: entry.label ?? 'You',
                ),
              ],
            ],
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Container(
            padding: const EdgeInsets.all(ColonySpacing.s4),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isUser ? 18 : 6),
                bottomRight: Radius.circular(isUser ? 6 : 18),
              ),
              border: Border.all(color: borderColor),
              boxShadow: isUser ? ColonyShadows.glowSmall(accent) : null,
            ),
            child: SelectableText(
              entry.body,
              style: const TextStyle(
                fontSize: 13,
                height: 1.55,
                color: ColonyColors.text0,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SystemEventCard extends StatelessWidget {
  final _TranscriptEntry entry;

  const _SystemEventCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.tone) {
      _SystemTone.info => ColonyColors.info,
      _SystemTone.warning => ColonyColors.warning,
      _SystemTone.error => ColonyColors.danger,
      _SystemTone.neutral => ColonyColors.text1,
    };

    return Align(
      alignment: Alignment.center,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 680),
        padding: const EdgeInsets.symmetric(
          horizontal: ColonySpacing.s3,
          vertical: ColonySpacing.s3,
        ),
        decoration: BoxDecoration(
          color: ColonyColors.surface0.withValues(alpha: 0.76),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_systemIcon(entry.tone), size: 15, color: color),
            const SizedBox(width: ColonySpacing.s2),
            Flexible(
              child: Text(
                entry.body,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _systemIcon(_SystemTone tone) {
    return switch (tone) {
      _SystemTone.info => Icons.bolt_rounded,
      _SystemTone.warning => Icons.warning_amber_rounded,
      _SystemTone.error => Icons.error_outline_rounded,
      _SystemTone.neutral => Icons.fiber_manual_record_rounded,
    };
  }
}

class _ActionPane extends StatelessWidget {
  final Session? session;
  final Color accent;
  final TextEditingController model;
  final Future<void> Function() onSetModel;
  final List<_TranscriptEntry> transcript;

  const _ActionPane({
    required this.session,
    required this.accent,
    required this.model,
    required this.onSetModel,
    required this.transcript,
  });

  @override
  Widget build(BuildContext context) {
    final userCount = transcript
        .where((entry) => entry.kind == _TranscriptEntryKind.user)
        .length;
    final assistantCount = transcript
        .where((entry) => entry.kind == _TranscriptEntryKind.assistant)
        .length;
    final systemCount = transcript
        .where((entry) => entry.kind == _TranscriptEntryKind.system)
        .length;

    return Container(
      padding: const EdgeInsets.all(ColonySpacing.s4),
      decoration: BoxDecoration(
        color: ColonyColors.surface1.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(ColonyRadii.r3),
        border: Border.all(color: ColonyColors.border0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Session Context',
            style: TextStyle(
              fontSize: 12,
              color: ColonyColors.text1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: ColonySpacing.s3),
          _MetricStrip(
            children: [
              _MiniMetric(
                label: 'Prompts',
                value: '$userCount',
                accent: accent,
              ),
              _MiniMetric(
                label: 'Replies',
                value: '$assistantCount',
                accent: ColonyColors.info,
              ),
              _MiniMetric(
                label: 'Events',
                value: '$systemCount',
                accent: ColonyColors.text1,
              ),
            ],
          ),
          const SizedBox(height: ColonySpacing.s4),
          _MetaRow(
            label: 'Provider',
            value: switch (session?.kind) {
              SessionKind.codex => 'Codex',
              SessionKind.claude => 'Claude',
              SessionKind.openclaw => 'OpenClaw',
              SessionKind.generic || null => 'Agent',
            },
          ),
          const SizedBox(height: ColonySpacing.s2),
          _MetaRow(label: 'Host', value: session?.node.id ?? 'unknown'),
          const SizedBox(height: ColonySpacing.s2),
          _MetaRow(label: 'Status', value: 'streaming'),
          const SizedBox(height: ColonySpacing.s4),
          if (session?.kind == SessionKind.codex) ...[
            const Text(
              'Model',
              style: TextStyle(
                fontSize: 12,
                color: ColonyColors.text1,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: ColonySpacing.s2),
            TextField(
              controller: model,
              decoration: const InputDecoration(
                hintText: 'gpt-5.2',
                prefixIcon: Icon(Icons.tune_rounded, size: 16),
              ),
              onSubmitted: (_) => onSetModel(),
            ),
            const SizedBox(height: ColonySpacing.s2),
            FilledButton.icon(
              onPressed: onSetModel,
              icon: const Icon(Icons.sync_alt_rounded, size: 16),
              label: const Text('Apply Model'),
            ),
            const SizedBox(height: ColonySpacing.s4),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(ColonySpacing.s3),
            decoration: BoxDecoration(
              color: ColonyColors.bg1.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(ColonyRadii.r2),
              border: Border.all(color: ColonyColors.border0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.rule_rounded, size: 16, color: accent),
                    const SizedBox(width: ColonySpacing.s2),
                    const Text(
                      'Composer Rules',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ColonySpacing.s2),
                Text(
                  'Enter sends immediately. Keep multi-step requests in one message so the reply stays grouped as a single assistant bubble.',
                  style: TextStyle(
                    fontSize: 12,
                    color: ColonyColors.text1.withValues(alpha: 0.95),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: ColonySpacing.s3),
                Row(
                  children: [
                    Icon(Icons.bolt_rounded, size: 16, color: accent),
                    const SizedBox(width: ColonySpacing.s2),
                    Text(
                      'Structured live transcript enabled',
                      style: TextStyle(
                        fontSize: 12,
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposerPane extends StatelessWidget {
  final TextEditingController controller;
  final Future<void> Function() onSend;
  final Color accent;

  const _ComposerPane({
    required this.controller,
    required this.onSend,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ColonySpacing.s3),
      decoration: BoxDecoration(
        color: ColonyColors.surface1.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(ColonyRadii.r3),
        border: Border.all(color: ColonyColors.border0),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 40,
            height: 40,
            margin: const EdgeInsets.only(bottom: 2),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.38)),
            ),
            child: Icon(Icons.edit_outlined, size: 18, color: accent),
          ),
          const SizedBox(width: ColonySpacing.s3),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: 'Send a prompt to this worker',
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: ColonySpacing.s3),
          FilledButton.icon(
            onPressed: onSend,
            icon: const Icon(Icons.send_rounded, size: 16),
            label: const Text('Send'),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetaRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: ColonyColors.text1),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AvatarChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;

  const _AvatarChip({
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ColonyColors.surface0.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricStrip extends StatelessWidget {
  final List<Widget> children;

  const _MetricStrip({required this.children});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          Expanded(child: children[index]),
          if (index != children.length - 1)
            const SizedBox(width: ColonySpacing.s2),
        ],
      ],
    );
  }
}

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;

  const _MiniMetric({
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ColonySpacing.s3),
      decoration: BoxDecoration(
        color: ColonyColors.bg1.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(ColonyRadii.r2),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: ColonyColors.text1,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

enum _TranscriptEntryKind { user, assistant, system }

enum _SystemTone { neutral, info, warning, error }

class _TranscriptEntry {
  final _TranscriptEntryKind kind;
  final String body;
  final String? label;
  final _SystemTone tone;

  const _TranscriptEntry({
    required this.kind,
    required this.body,
    this.label,
    this.tone = _SystemTone.neutral,
  });
}

List<_TranscriptEntry> _buildTranscriptFromEvents(
  List<ColonyStreamEvent> events,
  Session? session,
) {
  final transcript = <_TranscriptEntry>[];
  final assistantLabel = switch (session?.kind) {
    SessionKind.codex => 'Codex',
    SessionKind.claude => 'Claude',
    SessionKind.openclaw => 'OpenClaw',
    SessionKind.generic || null => 'Agent',
  };

  for (final event in events) {
    final next = _entryFromStreamEvent(event, assistantLabel: assistantLabel);
    if (next == null) continue;

    if (next.kind == _TranscriptEntryKind.assistant &&
        transcript.isNotEmpty &&
        transcript.last.kind == _TranscriptEntryKind.assistant &&
        transcript.last.label == next.label) {
      final previous = transcript.removeLast();
      transcript.add(
        _TranscriptEntry(
          kind: _TranscriptEntryKind.assistant,
          label: next.label,
          body: _mergeAssistantDraft(previous.body, next.body),
        ),
      );
      continue;
    }

    transcript.add(next);
  }

  return transcript;
}

_TranscriptEntry? _entryFromStreamEvent(
  ColonyStreamEvent event, {
  required String assistantLabel,
}) {
  switch (event.kind) {
    case ColonyStreamEventKind.userMessage:
      return _TranscriptEntry(
        kind: _TranscriptEntryKind.user,
        label: event.label ?? 'You',
        body: event.text,
      );
    case ColonyStreamEventKind.assistantMessage:
      final nested = _parseNestedStructuredEntry(
        event.text,
        assistantLabel: event.label ?? assistantLabel,
      );
      return nested ??
          _TranscriptEntry(
            kind: _TranscriptEntryKind.assistant,
            label: event.label ?? assistantLabel,
            body: event.text,
          );
    case ColonyStreamEventKind.systemEvent:
      final nested = _parseNestedStructuredEntry(
        event.text,
        assistantLabel: event.label ?? assistantLabel,
      );
      return nested ??
          _TranscriptEntry(
            kind: _TranscriptEntryKind.system,
            body: event.text,
            tone: _toneFromWire(event.tone),
          );
    case ColonyStreamEventKind.toolCall:
      return _TranscriptEntry(
        kind: _TranscriptEntryKind.system,
        body: event.text,
        tone: _SystemTone.info,
      );
    case ColonyStreamEventKind.warning:
      return _TranscriptEntry(
        kind: _TranscriptEntryKind.system,
        body: event.text,
        tone: _SystemTone.warning,
      );
    case ColonyStreamEventKind.error:
      return _TranscriptEntry(
        kind: _TranscriptEntryKind.system,
        body: event.text,
        tone: _SystemTone.error,
      );
    case ColonyStreamEventKind.processExit:
      return _TranscriptEntry(
        kind: _TranscriptEntryKind.system,
        body: event.text,
        tone: _toneFromWire(event.tone),
      );
    case ColonyStreamEventKind.raw:
      return _parseNestedStructuredEntry(
        event.text,
        assistantLabel: event.label ?? assistantLabel,
      );
  }
}

List<_TranscriptEntry> _buildTranscript(List<String> logs, Session? session) {
  final transcript = <_TranscriptEntry>[];
  var assistantDraft = '';
  final assistantLabel = switch (session?.kind) {
    SessionKind.codex => 'Codex',
    SessionKind.claude => 'Claude',
    SessionKind.openclaw => 'OpenClaw',
    SessionKind.generic || null => 'Agent',
  };

  void flushAssistant() {
    final body = assistantDraft.trim();
    if (body.isEmpty) return;
    transcript.add(
      _TranscriptEntry(
        kind: _TranscriptEntryKind.assistant,
        label: assistantLabel,
        body: body,
      ),
    );
    assistantDraft = '';
  }

  for (final rawLine in logs) {
    final line = rawLine.trimRight();
    if (line.trim().isEmpty) continue;

    final event = _parseLogLine(line, assistantLabel: assistantLabel);
    if (event == null) continue;

    switch (event.kind) {
      case _TranscriptEntryKind.user:
      case _TranscriptEntryKind.system:
        flushAssistant();
        transcript.add(event);
      case _TranscriptEntryKind.assistant:
        assistantDraft = _mergeAssistantDraft(assistantDraft, event.body);
    }
  }

  flushAssistant();
  return transcript;
}

_SystemTone _toneFromWire(String? tone) {
  return switch (tone?.trim()) {
    'info' => _SystemTone.info,
    'warning' => _SystemTone.warning,
    'error' => _SystemTone.error,
    _ => _SystemTone.neutral,
  };
}

_TranscriptEntry? _parseLogLine(String line, {required String assistantLabel}) {
  if (_shouldSuppressLog(line)) return null;

  final nested = _parseNestedStructuredEntry(
    line,
    assistantLabel: assistantLabel,
  );
  if (nested != null) return nested;

  if (line.startsWith('[colony-agent] >>> ')) {
    return _TranscriptEntry(
      kind: _TranscriptEntryKind.user,
      label: 'You',
      body: line.substring('[colony-agent] >>> '.length).trim(),
    );
  }

  if (line.startsWith('[colony-agent] <<<')) {
    return const _TranscriptEntry(
      kind: _TranscriptEntryKind.system,
      body: 'Turn completed',
      tone: _SystemTone.info,
    );
  }

  if (line.startsWith('[colony-agent] model set to ')) {
    return _TranscriptEntry(
      kind: _TranscriptEntryKind.system,
      body: line.substring('[colony-agent] '.length).trim(),
      tone: _SystemTone.info,
    );
  }

  if (line.startsWith('[colony-agent]')) {
    return _TranscriptEntry(
      kind: _TranscriptEntryKind.system,
      body: line.substring('[colony-agent]'.length).trim(),
      tone: _SystemTone.neutral,
    );
  }

  if (_looksLikeDiagnostic(line)) {
    return _TranscriptEntry(
      kind: _TranscriptEntryKind.system,
      body: _compactDiagnostic(line),
      tone: line.contains('ERROR') ? _SystemTone.error : _SystemTone.warning,
    );
  }

  final decoded = _decodeReadableOutput(line);
  if (decoded == null || decoded.isEmpty) return null;
  return _TranscriptEntry(
    kind: _TranscriptEntryKind.assistant,
    label: assistantLabel,
    body: decoded,
  );
}

bool _shouldSuppressLog(String line) {
  return line.startsWith('[oh-my-zsh]') ||
      line.contains('migration 21 was previously applied') ||
      line.contains(
        'state db discrepancy during find_thread_path_by_id_str_in_subdir',
      ) ||
      line.contains('Failed to delete shell snapshot');
}

bool _looksLikeDiagnostic(String line) {
  final timestamped = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}');
  return timestamped.hasMatch(line) &&
      (line.contains(' WARN ') || line.contains(' ERROR '));
}

String _compactDiagnostic(String line) {
  final parts = line.split(RegExp(r'\s{2,}'));
  return parts.isEmpty ? line : parts.last.trim();
}

String? _decodeReadableOutput(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try {
      final decoded = jsonDecode(trimmed);
      final structured = _extractReadableText(decoded);
      if (structured != null && structured.trim().isNotEmpty) {
        return structured.trim();
      }
      final fallback = _extractStructuredEvent(decoded);
      if (fallback != null && fallback.trim().isNotEmpty) {
        return fallback.trim();
      }
      return null;
    } catch (_) {
      if (trimmed.contains('"type"') || trimmed.contains('"item"')) {
        return null;
      }
      return trimmed;
    }
  }

  return trimmed;
}

_TranscriptEntry? _parseNestedStructuredEntry(
  String text, {
  required String assistantLabel,
}) {
  final trimmed = text.trim();
  if (!trimmed.startsWith('{')) return null;
  try {
    return _entryFromDecodedJson(
      jsonDecode(trimmed),
      assistantLabel: assistantLabel,
    );
  } catch (_) {
    return null;
  }
}

_TranscriptEntry? _entryFromDecodedJson(
  dynamic value, {
  required String assistantLabel,
}) {
  if (value is! Map) return null;
  final type = '${value['type'] ?? ''}'.trim();

  if (type == 'item.completed' && value['item'] is Map) {
    return _entryFromDecodedJson(value['item'], assistantLabel: assistantLabel);
  }

  if (type == 'agent_message') {
    final text = _extractReadableText(value['text'] ?? value['content']);
    if (text == null || text.trim().isEmpty) return null;
    return _TranscriptEntry(
      kind: _TranscriptEntryKind.assistant,
      label: assistantLabel,
      body: text.trim(),
    );
  }

  if (type == 'turn.completed') {
    final usage = value['usage'];
    if (usage is Map) {
      final input = usage['input_tokens'];
      final output = usage['output_tokens'];
      return _TranscriptEntry(
        kind: _TranscriptEntryKind.system,
        body: 'Turn completed • input $input • output $output',
        tone: _SystemTone.info,
      );
    }
    return const _TranscriptEntry(
      kind: _TranscriptEntryKind.system,
      body: 'Turn completed',
      tone: _SystemTone.info,
    );
  }

  if (type == 'error') {
    final message = _extractReadableText(value['message'] ?? value['error']);
    return _TranscriptEntry(
      kind: _TranscriptEntryKind.system,
      body: message == null ? 'Agent error' : 'Agent error: $message',
      tone: _SystemTone.error,
    );
  }

  if (type.contains('tool')) {
    final name = '${value['name'] ?? value['tool_name'] ?? 'Tool call'}'.trim();
    return _TranscriptEntry(
      kind: _TranscriptEntryKind.system,
      body: name,
      tone: _SystemTone.info,
    );
  }

  return null;
}

String _mergeAssistantDraft(String current, String next) {
  final normalized = next.trim();
  if (normalized.isEmpty) return current;
  if (current.isEmpty) return normalized;
  if (normalized == current) return current;
  if (normalized.startsWith(current)) return normalized;
  if (current.endsWith(normalized)) return current;
  if (current.contains(normalized) && normalized.length < current.length) {
    return current;
  }
  return '$current\n$normalized';
}

String? _extractReadableText(dynamic value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  if (value is List) {
    final items = value
        .map(_extractReadableText)
        .whereType<String>()
        .where((item) => item.trim().isNotEmpty)
        .toList(growable: false);
    if (items.isEmpty) return null;
    return _dedupeAdjacent(items).join('\n');
  }

  if (value is Map) {
    for (final key in const [
      'delta',
      'text',
      'output_text',
      'completion',
      'content',
      'message',
      'content_block',
      'result',
      'response',
      'part',
    ]) {
      if (!value.containsKey(key)) continue;
      final extracted = _extractReadableText(value[key]);
      if (extracted != null && extracted.trim().isNotEmpty) {
        return extracted.trim();
      }
    }

    final collected = <String>[];
    for (final entry in value.entries) {
      if (entry.key is! String) continue;
      final key = entry.key as String;
      if (!const {
        'type',
        'role',
        'id',
        'model',
        'name',
        'index',
        'timestamp',
      }.contains(key)) {
        continue;
      }
      if (key == 'name' && value['type'] == 'tool_call') {
        final name = '${entry.value}'.trim();
        if (name.isNotEmpty) {
          collected.add('Tool call: $name');
        }
      }
    }
    if (collected.isEmpty) return null;
    return _dedupeAdjacent(collected).join('\n');
  }

  return null;
}

String? _extractStructuredEvent(dynamic value) {
  if (value is! Map) return null;
  final type = '${value['type'] ?? ''}'.trim();
  final name = '${value['name'] ?? value['tool_name'] ?? ''}'.trim();
  final role = '${value['role'] ?? ''}'.trim();

  if (type.contains('error')) {
    final message = _extractReadableText(value['error'] ?? value['message']);
    return message == null ? 'Agent error' : 'Agent error: $message';
  }

  if (type.contains('tool') && name.isNotEmpty) {
    return 'Tool call: $name';
  }

  if (type.isNotEmpty && role.isNotEmpty) {
    return '$role • $type';
  }

  if (type.isNotEmpty) return type;
  return null;
}

List<String> _dedupeAdjacent(List<String> values) {
  final output = <String>[];
  for (final value in values) {
    if (output.isEmpty || output.last != value) {
      output.add(value);
    }
  }
  return output;
}
