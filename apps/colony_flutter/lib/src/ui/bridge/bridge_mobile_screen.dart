import 'package:flutter/material.dart';

import '../../bridge/bridge_client_controller.dart';
import '../../bridge/bridge_models.dart';
import '../../bridge/qr_scan_channel.dart';
import '../../design/tokens.dart';

class BridgeMobileScreen extends StatefulWidget {
  final BridgeClientController controller;
  const BridgeMobileScreen({super.key, required this.controller});

  @override
  State<BridgeMobileScreen> createState() => _BridgeMobileScreenState();
}

class _BridgeMobileScreenState extends State<BridgeMobileScreen> {
  final TextEditingController _composer = TextEditingController();
  final TextEditingController _url = TextEditingController();
  final TextEditingController _workspace = TextEditingController();
  final TextEditingController _token = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncFields);
    _syncFields();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFields);
    _composer.dispose();
    _url.dispose();
    _workspace.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        return Scaffold(
          backgroundColor: ColonyColors.bg0,
          appBar: AppBar(
            backgroundColor: ColonyColors.surface0,
            title: const Text('Colony iPhone Bridge'),
            actions: [
              IconButton(
                tooltip: 'Scan QR',
                onPressed: _presentScanner,
                icon: const Icon(Icons.qr_code_scanner),
              ),
              IconButton(
                tooltip: 'Connect',
                onPressed: _connect,
                icon: const Icon(Icons.link),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                _connectionPanel(controller),
                if (controller.bannerText != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: ColonyColors.surface1,
                      borderRadius: BorderRadius.circular(ColonyRadii.r2),
                      border: Border.all(color: ColonyColors.border0),
                    ),
                    child: Text(controller.bannerText!, style: const TextStyle(color: ColonyColors.text1)),
                  ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: controller.messages.map(_messageBubble).toList(growable: false),
                  ),
                ),
                _composerBar(controller),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _connectionPanel(BridgeClientController controller) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ColonyColors.surface0,
        borderRadius: BorderRadius.circular(ColonyRadii.r2),
        border: Border.all(color: ColonyColors.border0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 9, height: 9, decoration: BoxDecoration(color: _statusColor(controller), shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Text(controller.connectionLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton(onPressed: _connect, child: const Text('Connect')),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            decoration: const InputDecoration(labelText: 'Bridge URL'),
            onChanged: (value) => controller.baseUrlString = value,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _workspace,
            decoration: const InputDecoration(labelText: 'Workspace'),
            onChanged: (value) => controller.workingDirectory = value,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _token,
            decoration: const InputDecoration(labelText: 'Token'),
            onChanged: (value) => controller.token = value,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<BridgeExecutionMode>(
            initialValue: controller.executionMode,
            items: BridgeExecutionMode.values
                .map(
                  (mode) => DropdownMenuItem(
                    value: mode,
                    child: Text(bridgeExecutionModeTitle(mode)),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value == null) return;
              controller.executionMode = value;
            },
            decoration: const InputDecoration(labelText: 'Execution Mode'),
          ),
          if (controller.lastError != null) ...[
            const SizedBox(height: 10),
            Text(controller.lastError!, style: const TextStyle(color: ColonyColors.danger, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _messageBubble(BridgeChatMessage message) {
    final isUser = message.role == BridgeRole.user;
    final isStatus = message.role == BridgeRole.status;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: isStatus ? ColonyColors.surface1 : (isUser ? ColonyColors.accentCyan.withValues(alpha: 0.16) : ColonyColors.surface0),
          borderRadius: BorderRadius.circular(ColonyRadii.r2),
          border: Border.all(color: ColonyColors.border0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.content, style: const TextStyle(color: ColonyColors.text0, height: 1.35)),
            if ((message.metadata ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(message.metadata!, style: const TextStyle(fontSize: 11, color: ColonyColors.text1)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _composerBar(BridgeClientController controller) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: const BoxDecoration(color: ColonyColors.surface0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _composer,
              minLines: 1,
              maxLines: 5,
              decoration: InputDecoration(hintText: controller.composerPlaceholder),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: controller.canSend ? _send : null,
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  Future<void> _presentScanner() async {
    final value = await QrScanChannel.scan();
    if (value == null || value.isEmpty) return;
    await widget.controller.applyPairingCode(value);
    _syncFields();
  }

  Future<void> _connect() async {
    await widget.controller.refreshSession(forceReconnect: true);
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    _composer.clear();
    await widget.controller.sendMessage(text);
  }

  void _syncFields() {
    _url.text = widget.controller.baseUrlString;
    _workspace.text = widget.controller.workingDirectory;
    _token.text = widget.controller.token;
    if (mounted) {
      setState(() {});
    }
  }

  Color _statusColor(BridgeClientController controller) {
    return switch (controller.connectionLabel) {
      'Connected' => ColonyColors.success,
      'Running' => ColonyColors.warning,
      'Retrying' => ColonyColors.warning,
      _ => ColonyColors.text1,
    };
  }
}
