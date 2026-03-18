import 'dart:ui';

import 'package:flutter/material.dart';

import '../../bridge/bridge_server_controller.dart';
import '../../design/tokens.dart';
import '../../state/app_state.dart';
import '../bridge/bridge_pairing_dialog.dart';
import '../widgets/bottom_drawer.dart';
import '../widgets/command_bar.dart';
import 'world_canvas.dart';

class WorldScreen extends StatefulWidget {
  final AppState state;
  final BridgeServerController bridgeController;
  const WorldScreen({super.key, required this.state, required this.bridgeController});

  @override
  State<WorldScreen> createState() => _WorldScreenState();
}

class _WorldScreenState extends State<WorldScreen> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        return Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: WorldCanvas(state: widget.state),
              ),

              Positioned(
                left: ColonySpacing.s4,
                right: ColonySpacing.s4,
                top: ColonySpacing.s4,
                child: _TopBar(state: widget.state, bridgeController: widget.bridgeController),
              ),

              Positioned(
                left: ColonySpacing.s4,
                top: 82,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0.55,
                    child: Text(
                      'iso-dots',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: ColonyColors.accentCyan.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ),
              ),

              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: BottomDrawer(state: widget.state),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  final AppState state;
  final BridgeServerController bridgeController;
  const _TopBar({required this.state, required this.bridgeController});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(ColonyRadii.r2),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(ColonySpacing.s2),
          decoration: BoxDecoration(
            color: ColonyColors.surface0.withValues(alpha: 0.75),
            border: Border.all(color: ColonyColors.border0),
            borderRadius: BorderRadius.circular(ColonyRadii.r2),
          ),
          child: Row(
            children: [
              _ModePill(buildMode: state.buildMode),
              const SizedBox(width: ColonySpacing.s2),
              Expanded(
                child: CommandBar(state: state),
              ),
              const SizedBox(width: ColonySpacing.s2),
              _RateLimitChip(rateLimit: state.codexRateLimit),
              const SizedBox(width: ColonySpacing.s2),
              IconButton(
                tooltip: 'Phone Pairing',
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (context) => BridgePairingDialog(controller: bridgeController),
                  );
                },
                icon: const Icon(Icons.phone_iphone, size: 18),
              ),
              const SizedBox(width: ColonySpacing.s2),
              IconButton(
                tooltip: 'Refresh',
                onPressed: () => state.refresh(),
                icon: const Icon(Icons.refresh, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  final bool buildMode;
  const _ModePill({required this.buildMode});

  @override
  Widget build(BuildContext context) {
    final c = buildMode ? ColonyColors.warning : ColonyColors.text1;
    final label = buildMode ? 'BUILD' : 'OPERATE';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ColonyColors.surface1,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.6)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: c,
        ),
      ),
    );
  }
}

class _RateLimitChip extends StatelessWidget {
  final Map<String, dynamic>? rateLimit;
  const _RateLimitChip({required this.rateLimit});

  @override
  Widget build(BuildContext context) {
    final rl = rateLimit;
    if (rl == null) {
      return _chip(context, 'codex', 'rate: --');
    }
    final limits = rl['rateLimits'] as Map<String, dynamic>?;
    final primary = (limits?['primary'] as Map<String, dynamic>?)?['usedPercent'];
    final secondary = (limits?['secondary'] as Map<String, dynamic>?)?['usedPercent'];
    final p = primary is num ? primary.toDouble() : null;
    final s = secondary is num ? secondary.toDouble() : null;

    final text = 'P ${p?.toStringAsFixed(0) ?? '--'}% / S ${s?.toStringAsFixed(0) ?? '--'}%';
    return _chip(context, 'codex', text);
  }

  Widget _chip(BuildContext context, String left, String right) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ColonyColors.surface1,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: ColonyColors.border0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            left,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: ColonyColors.text0,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            right,
            style: const TextStyle(fontSize: 11, color: ColonyColors.text1),
          ),
        ],
      ),
    );
  }
}
