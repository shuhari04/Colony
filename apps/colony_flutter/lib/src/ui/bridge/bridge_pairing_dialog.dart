import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../bridge/bridge_server_controller.dart';
import '../../design/tokens.dart';

class BridgePairingDialog extends StatefulWidget {
  final BridgeServerController controller;
  const BridgePairingDialog({super.key, required this.controller});

  @override
  State<BridgePairingDialog> createState() => _BridgePairingDialogState();
}

class _BridgePairingDialogState extends State<BridgePairingDialog> {
  late final TextEditingController _workspace;
  late final TextEditingController _port;
  late final TextEditingController _token;

  @override
  void initState() {
    super.initState();
    _workspace = TextEditingController(text: widget.controller.workspacePath);
    _port = TextEditingController(text: widget.controller.bridgePort);
    _token = TextEditingController(text: widget.controller.bridgeToken);
  }

  @override
  void dispose() {
    _workspace.dispose();
    _port.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final pairingJson = controller.pairingPayload.toPrettyJson();
        return AlertDialog(
          backgroundColor: ColonyColors.surface0,
          surfaceTintColor: ColonyColors.surface0,
          title: const Text('Phone Pairing'),
          content: SizedBox(
            width: 760,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _statusRow(controller),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(ColonyRadii.r2),
                        ),
                        child: QrImageView(
                          data: pairingJson,
                          size: 168,
                          backgroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _readonlyRow('Local URL', controller.localBridgeUrl),
                            const SizedBox(height: 8),
                            _readonlyRow('Token', controller.bridgeToken),
                            const SizedBox(height: 8),
                            _readonlyRow('Mode', controller.bridgeReachable ? 'Bridge online' : 'Bridge offline'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _workspace,
                    decoration: const InputDecoration(labelText: 'Workspace'),
                    onChanged: (value) => controller.workspacePath = value,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _port,
                          decoration: const InputDecoration(labelText: 'Port'),
                          onChanged: (value) => controller.bridgePort = value,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _token,
                          decoration: const InputDecoration(labelText: 'Pairing Token'),
                          onChanged: (value) => controller.bridgeToken = value,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: () async {
                          await controller.persistSettings();
                          if (!mounted) return;
                          setState(() {});
                        },
                        icon: const Icon(Icons.save_outlined, size: 16),
                        label: const Text('Save'),
                      ),
                      FilledButton.icon(
                        onPressed: controller.lifecycle == BridgeLifecycle.running ? null : () => controller.startBridge(),
                        icon: const Icon(Icons.play_arrow, size: 16),
                        label: const Text('Start Bridge'),
                      ),
                      OutlinedButton.icon(
                        onPressed: controller.lifecycle == BridgeLifecycle.stopped ? null : () => controller.stopBridge(),
                        icon: const Icon(Icons.stop, size: 16),
                        label: const Text('Stop'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await controller.generateBridgeToken();
                          _token.text = controller.bridgeToken;
                        },
                        icon: const Icon(Icons.vpn_key_outlined, size: 16),
                        label: const Text('New Token'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: pairingJson));
                        },
                        icon: const Icon(Icons.copy_outlined, size: 16),
                        label: const Text('Copy Pairing JSON'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text('Pairing JSON', style: TextStyle(fontSize: 12, color: ColonyColors.text1)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: ColonyColors.bg1.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(ColonyRadii.r2),
                      border: Border.all(color: ColonyColors.border0),
                    ),
                    child: SelectableText(
                      pairingJson,
                      style: const TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 12,
                        color: ColonyColors.text0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Bridge Logs', style: TextStyle(fontSize: 12, color: ColonyColors.text1)),
                  const SizedBox(height: 8),
                  Container(
                    height: 180,
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: ColonyColors.bg1.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(ColonyRadii.r2),
                      border: Border.all(color: ColonyColors.border0),
                    ),
                    child: ListView(
                      children: controller.logs
                          .map(
                            (line) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                line,
                                style: const TextStyle(
                                  fontFamily: 'JetBrains Mono',
                                  fontSize: 11,
                                  color: ColonyColors.text0,
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
          ],
        );
      },
    );
  }

  Widget _statusRow(BridgeServerController controller) {
    final color = switch (controller.lifecycle) {
      BridgeLifecycle.running => ColonyColors.success,
      BridgeLifecycle.starting || BridgeLifecycle.stopping => ColonyColors.warning,
      BridgeLifecycle.failed => ColonyColors.danger,
      BridgeLifecycle.stopped => ColonyColors.text1,
    };
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Text(controller.statusNote, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _readonlyRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: ColonyColors.text1)),
        const SizedBox(height: 4),
        SelectableText(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
