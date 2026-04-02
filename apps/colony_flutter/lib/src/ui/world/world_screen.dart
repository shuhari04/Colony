import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../bridge/bridge_server_controller.dart';
import '../../design/tokens.dart';
import '../../domain/building.dart';
import '../../model/board.dart';
import '../../state/app_state.dart';
import '../bridge/bridge_pairing_dialog.dart';
import '../dialogs/server_config_dialog.dart';
import '../widgets/bottom_drawer.dart';
import '../widgets/command_bar.dart';
import 'world_canvas.dart';

class WorldScreen extends StatefulWidget {
  final AppState state;
  final BridgeServerController bridgeController;
  const WorldScreen({
    super.key,
    required this.state,
    required this.bridgeController,
  });

  @override
  State<WorldScreen> createState() => _WorldScreenState();
}

class _WorldScreenState extends State<WorldScreen> {
  bool _inventoryOpen = false;
  final FocusNode _keyboardFocus = FocusNode(debugLabel: 'world-screen');

  @override
  void dispose() {
    _keyboardFocus.dispose();
    super.dispose();
  }

  Future<void> _confirmDeleteSelectedBuilding() async {
    final selection = widget.state.selection;
    if (selection.kind != SelectionKind.building) return;
    final building = widget.state.boardBuildingById(selection.id);
    if (building == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ColonyColors.surface0,
        title: const Text('Delete Building'),
        content: Text(
          'Delete ${_displayTitleForBuilding(building)} from the board?',
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
    if (confirmed != true) return;
    await widget.state.deleteBuilding(building.id);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        final selectedBuilding =
            widget.state.selection.kind == SelectionKind.building
            ? widget.state.boardBuildingById(widget.state.selection.id)
            : null;
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.backspace): () async {
              await _confirmDeleteSelectedBuilding();
            },
            const SingleActivator(LogicalKeyboardKey.delete): () async {
              await _confirmDeleteSelectedBuilding();
            },
          },
          child: Focus(
            autofocus: true,
            focusNode: _keyboardFocus,
            child: Scaffold(
              body: Stack(
                children: [
                  Positioned.fill(child: WorldCanvas(state: widget.state)),
                  Positioned(
                    left: ColonySpacing.s4,
                    right: ColonySpacing.s4,
                    top: ColonySpacing.s4,
                    child: _TopBar(
                      state: widget.state,
                      bridgeController: widget.bridgeController,
                    ),
                  ),
                  Positioned(
                    left: ColonySpacing.s4,
                    right: ColonySpacing.s4,
                    bottom: 0,
                    child: BottomDrawer(state: widget.state),
                  ),
                  if (selectedBuilding != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 116 + MediaQuery.paddingOf(context).bottom,
                      child: Center(
                        child: _BuildingActionHud(
                          state: widget.state,
                          building: selectedBuilding,
                        ),
                      ),
                    ),
                  Positioned(
                    right: ColonySpacing.s4,
                    bottom: 104,
                    child: _InventoryDock(
                      open: _inventoryOpen,
                      state: widget.state,
                      onToggle: () =>
                          setState(() => _inventoryOpen = !_inventoryOpen),
                      onPlaced: () => setState(() => _inventoryOpen = false),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _displayTitleForBuilding(PlacedBuilding building) {
    if (building.kind == BoardBuildingKind.machine) {
      final provider = widget.state.providerLabel(building.provider);
      if (provider.isNotEmpty) {
        return '${provider[0].toUpperCase()}${provider.substring(1)} Machine';
      }
      return 'Machine';
    }
    return widget.state.titleForBuildingKind(building.kind);
  }
}

class _BuildingActionHud extends StatelessWidget {
  final AppState state;
  final PlacedBuilding building;

  const _BuildingActionHud({required this.state, required this.building});

  @override
  Widget build(BuildContext context) {
    final accent = _buildingAccent(building);
    final actions = _actionsFor(context);

    return IgnorePointer(
      ignoring: false,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: ColonyColors.surface0.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: accent.withValues(alpha: 0.38)),
                boxShadow: [
                  ...ColonyShadows.panel,
                  ...ColonyShadows.glowSmall(accent),
                ],
              ),
              child: Text(
                _displayTitle(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            const SizedBox(height: ColonySpacing.s3),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: ColonySpacing.s3,
              runSpacing: ColonySpacing.s3,
              children: [
                for (final action in actions) _HudActionButton(action: action),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<_HudAction> _actionsFor(BuildContext context) {
    final workers = state.workersOwnedByMachine(building.id);
    final actions = <_HudAction>[
      _HudAction(
        label: 'Move',
        icon: Icons.open_with_rounded,
        accent: ColonyColors.text1,
        onTap: () async {
          state.beginMovingBuilding(building.id);
        },
      ),
    ];

    switch (building.kind) {
      case BoardBuildingKind.buildingWorkspace:
      case BoardBuildingKind.buildingAltA:
      case BoardBuildingKind.buildingAltB:
        actions.insert(
          0,
          _HudAction(
            label: (building.workspacePath ?? '').isEmpty
                ? 'Workspace'
                : 'Change',
            icon: Icons.folder_open_rounded,
            accent: ColonyColors.accentCyan,
            onTap: () => state.bindWorkspaceForBuilding(building.id),
          ),
        );
        break;
      case BoardBuildingKind.server:
        actions.insert(
          0,
          _HudAction(
            label: 'Configure',
            icon: Icons.settings_ethernet_rounded,
            accent: ColonyColors.success,
            onTap: () async {
              final result = await showDialog<ServerConfigDialogResult>(
                context: context,
                builder: (context) => ServerConfigDialog(
                  initial: state.boardBuildingById(building.id)?.serverConfig,
                ),
              );
              if (result == null) return;
              await state.configureServerBuilding(
                building.id,
                alias: result.alias,
                host: result.host,
                password: result.password,
              );
            },
          ),
        );
        break;
      case BoardBuildingKind.machine:
        actions.insert(
          0,
          _HudAction(
            label: 'New Worker',
            icon: Icons.add_circle_outline_rounded,
            accent: _buildingAccent(building),
            onTap: () => state.createWorkerForMachine(building.id),
          ),
        );
        if (workers.isNotEmpty) {
          actions.insert(
            1,
            _HudAction(
              label: 'Assign',
              icon: Icons.send_rounded,
              accent: ColonyColors.warning,
              onTap: () async {
                state.beginWorkerAssignment(workers.last.id);
              },
            ),
          );
          final latestSession = workers.last.sessionAddress == null
              ? null
              : state.sessionByAddress(workers.last.sessionAddress!);
          if (latestSession != null) {
            actions.insert(
              2,
              _HudAction(
                label: 'Open Chat',
                icon: Icons.chat_bubble_outline_rounded,
                accent: ColonyColors.info,
                onTap: () async {
                  state.selectSession(latestSession);
                },
              ),
            );
          }
        }
        break;
      case BoardBuildingKind.kanban:
      case BoardBuildingKind.workflowLine:
        break;
    }

    return actions;
  }

  String _displayTitle() {
    if (building.kind == BoardBuildingKind.machine) {
      return '${_capitalize(state.providerLabel(building.provider))} Machine';
    }
    return state.titleForBuildingKind(building.kind);
  }

  Color _buildingAccent(PlacedBuilding current) {
    return switch (current.kind) {
      BoardBuildingKind.buildingWorkspace => ColonyColors.accentCyan,
      BoardBuildingKind.buildingAltA => ColonyColors.info,
      BoardBuildingKind.buildingAltB => ColonyColors.warning,
      BoardBuildingKind.server => ColonyColors.success,
      BoardBuildingKind.kanban => ColonyColors.text1,
      BoardBuildingKind.machine => switch (current.provider) {
        AgentProvider.codex => ColonyColors.accentCyan,
        AgentProvider.claude => ColonyColors.info,
        AgentProvider.openclaw => ColonyColors.success,
        AgentProvider.other || AgentProvider.none => ColonyColors.text1,
      },
      BoardBuildingKind.workflowLine => ColonyColors.warning,
    };
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }
}

class _HudAction {
  final String label;
  final IconData icon;
  final Color accent;
  final Future<void> Function() onTap;

  const _HudAction({
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
  });
}

class _HudActionButton extends StatelessWidget {
  final _HudAction action;

  const _HudActionButton({required this.action});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          await action.onTap();
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 96,
          height: 96,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                ColonyColors.surface0.withValues(alpha: 0.94),
                ColonyColors.bg1.withValues(alpha: 0.94),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: action.accent.withValues(alpha: 0.42)),
            boxShadow: [
              ...ColonyShadows.panel,
              ...ColonyShadows.glowSmall(action.accent.withValues(alpha: 0.8)),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(action.icon, size: 28, color: action.accent),
              const SizedBox(height: 10),
              Text(
                action.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: action.accent,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final AppState state;
  final BridgeServerController bridgeController;
  const _TopBar({required this.state, required this.bridgeController});

  @override
  Widget build(BuildContext context) {
    final worldCount = 1;
    final sessionCount = state.sessions.length;
    final buildingCount = state.boardBuildings.length;
    final machineCount = state.boardBuildings
        .where((building) => building.kind == BoardBuildingKind.machine)
        .length;

    return ClipRRect(
      borderRadius: BorderRadius.circular(ColonyRadii.r3),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.all(ColonySpacing.s2),
          decoration: BoxDecoration(
            color: ColonyColors.surface0.withValues(alpha: 0.82),
            border: Border.all(color: ColonyColors.border0),
            borderRadius: BorderRadius.circular(ColonyRadii.r3),
            boxShadow: ColonyShadows.panel,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const _BrandBlock(),
                  const SizedBox(width: ColonySpacing.s3),
                  Expanded(
                    child: _StatusStrip(
                      buildMode: state.buildMode,
                      worldCount: worldCount,
                      sessionCount: sessionCount,
                      buildingCount: buildingCount,
                      machineCount: machineCount,
                    ),
                  ),
                  const Spacer(),
                  _RateLimitChip(rateLimit: state.codexRateLimit),
                  const SizedBox(width: ColonySpacing.s2),
                  IconButton(
                    tooltip: 'Phone Pairing',
                    onPressed: () {
                      showDialog<void>(
                        context: context,
                        builder: (context) =>
                            BridgePairingDialog(controller: bridgeController),
                      );
                    },
                    icon: const Icon(Icons.phone_iphone_rounded, size: 18),
                  ),
                  const SizedBox(width: ColonySpacing.s1),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: () => state.refresh(),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: ColonySpacing.s2),
              CommandBar(state: state),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandBlock extends StatelessWidget {
  const _BrandBlock();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            ColonyColors.accentCyan.withValues(alpha: 0.16),
            ColonyColors.info.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(ColonyRadii.r2),
        border: Border.all(color: ColonyColors.border1.withValues(alpha: 0.7)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'COLONY',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          SizedBox(height: 2),
          Text(
            'Spatial control plane for agents',
            style: TextStyle(fontSize: 11, color: ColonyColors.text1),
          ),
        ],
      ),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  final bool buildMode;
  final int worldCount;
  final int sessionCount;
  final int buildingCount;
  final int machineCount;

  const _StatusStrip({
    required this.buildMode,
    required this.worldCount,
    required this.sessionCount,
    required this.buildingCount,
    required this.machineCount,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _StatusPill(
            label: buildMode ? 'Placement Mode' : 'Operate Mode',
            value: buildMode ? 'drag and commit' : 'live control',
            color: buildMode ? ColonyColors.warning : ColonyColors.accentCyan,
          ),
          const SizedBox(width: ColonySpacing.s2),
          _StatusPill(
            label: 'Board',
            value: '$worldCount active',
            color: ColonyColors.info,
          ),
          const SizedBox(width: ColonySpacing.s2),
          _StatusPill(
            label: 'Workers',
            value: '$sessionCount active',
            color: ColonyColors.success,
          ),
          const SizedBox(width: ColonySpacing.s2),
          _StatusPill(
            label: 'Buildings',
            value: '$buildingCount placed • $machineCount machine',
            color: buildingCount == 0
                ? ColonyColors.text1
                : ColonyColors.warning,
          ),
        ],
      ),
    );
  }
}

class _InventoryDock extends StatelessWidget {
  final bool open;
  final AppState state;
  final VoidCallback onToggle;
  final VoidCallback onPlaced;

  const _InventoryDock({
    required this.open,
    required this.state,
    required this.onToggle,
    required this.onPlaced,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: open ? 412 : 68,
      padding: const EdgeInsets.all(ColonySpacing.s2),
      decoration: BoxDecoration(
        color: ColonyColors.surface0.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(ColonyRadii.r3),
        border: Border.all(color: ColonyColors.border0),
        boxShadow: ColonyShadows.panel,
      ),
      child: open
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Repository',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: onToggle,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: ColonySpacing.s2),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 452),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const gap = ColonySpacing.s2;
                      final tileWidth = (constraints.maxWidth - gap) / 2;
                      return SingleChildScrollView(
                        child: Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [
                            for (final item in AppState.inventoryItems)
                              _InventoryRow(
                                state: state,
                                width: tileWidth,
                                item: item,
                                onTap: () async {
                                  await state.beginInventoryPlacement(item);
                                  onPlaced();
                                },
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            )
          : IconButton(
              tooltip: 'Repository',
              onPressed: onToggle,
              icon: const Icon(Icons.inventory_2_rounded),
            ),
    );
  }
}

class _InventoryRow extends StatelessWidget {
  final AppState state;
  final double width;
  final BoardInventoryItem item;
  final VoidCallback onTap;

  const _InventoryRow({
    required this.state,
    required this.width,
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ColonyRadii.r2),
      child: Container(
        width: width,
        padding: const EdgeInsets.all(ColonySpacing.s3),
        decoration: BoxDecoration(
          color: ColonyColors.bg1.withValues(alpha: 0.74),
          borderRadius: BorderRadius.circular(ColonyRadii.r2),
          border: Border.all(color: ColonyColors.border0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 122,
              width: double.infinity,
              decoration: BoxDecoration(
                color: ColonyColors.surface1.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _accentFor(item).withValues(alpha: 0.24),
                ),
              ),
              padding: const EdgeInsets.all(2),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Center(
                      child: Transform.scale(
                        scale: 1.18,
                        child: Image.asset(
                          state.assetPathForInventoryItem(item),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  if (item.kind == BoardBuildingKind.machine)
                    Positioned(
                      left: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: ColonyColors.surface0.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: _accentFor(item).withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          state.providerLabel(item.provider),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: _accentFor(item),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: ColonySpacing.s2),
            Text(
              item.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              item.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: ColonyColors.text1),
            ),
          ],
        ),
      ),
    );
  }

  Color _accentFor(BoardInventoryItem item) {
    return switch (item.kind) {
      BoardBuildingKind.buildingWorkspace => ColonyColors.accentCyan,
      BoardBuildingKind.buildingAltA => ColonyColors.info,
      BoardBuildingKind.buildingAltB => ColonyColors.warning,
      BoardBuildingKind.server => ColonyColors.success,
      BoardBuildingKind.kanban => ColonyColors.text1,
      BoardBuildingKind.machine => switch (item.provider) {
        AgentProvider.codex => ColonyColors.accentCyan,
        AgentProvider.claude => ColonyColors.info,
        AgentProvider.openclaw => ColonyColors.success,
        AgentProvider.other || AgentProvider.none => ColonyColors.text1,
      },
      BoardBuildingKind.workflowLine => ColonyColors.warning,
    };
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatusPill({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: ColonyColors.bg1.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 11),
          children: [
            TextSpan(
              text: '$label ',
              style: const TextStyle(
                color: ColonyColors.text1,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(color: color, fontWeight: FontWeight.w800),
            ),
          ],
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
      return const _RateLimitShell(
        accent: ColonyColors.text1,
        label: 'Codex Rate',
        value: 'unavailable',
        primaryRemaining: null,
        secondaryRemaining: null,
      );
    }

    final limits = rl['rateLimits'] as Map<String, dynamic>?;
    final primary =
        (limits?['primary'] as Map<String, dynamic>?)?['usedPercent'];
    final secondary =
        (limits?['secondary'] as Map<String, dynamic>?)?['usedPercent'];
    final reset = rl['resetsAt'] ?? rl['resetAt'];
    final p = primary is num ? primary.toDouble() : null;
    final s = secondary is num ? secondary.toDouble() : null;
    final pRemaining = p == null ? null : (100 - p).clamp(0, 100).toDouble();
    final sRemaining = s == null ? null : (100 - s).clamp(0, 100).toDouble();
    final lowestRemaining = [
      pRemaining ?? 100,
      sRemaining ?? 100,
    ].reduce((a, b) => a < b ? a : b);
    final accent = lowestRemaining <= 15
        ? ColonyColors.warning
        : lowestRemaining <= 35
        ? ColonyColors.info
        : ColonyColors.accentCyan;

    final value =
        'P ${pRemaining?.toStringAsFixed(0) ?? '--'}%  S ${sRemaining?.toStringAsFixed(0) ?? '--'}% left';
    final detail = reset == null ? null : '$reset';

    return _RateLimitShell(
      accent: accent,
      label: 'Codex Rate',
      value: value,
      detail: detail,
      primaryRemaining: pRemaining,
      secondaryRemaining: sRemaining,
    );
  }
}

class _RateLimitShell extends StatelessWidget {
  final Color accent;
  final String label;
  final String value;
  final String? detail;
  final double? primaryRemaining;
  final double? secondaryRemaining;

  const _RateLimitShell({
    required this.accent,
    required this.label,
    required this.value,
    this.detail,
    required this.primaryRemaining,
    required this.secondaryRemaining,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: ColonyColors.bg1.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(ColonyRadii.r2),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
        boxShadow: accent == ColonyColors.warning
            ? ColonyShadows.glowSmall(accent)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: ColonyColors.text1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: accent,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          _RateMeterRow(
            label: 'Primary',
            remaining: primaryRemaining,
            accent: accent,
          ),
          const SizedBox(height: 4),
          _RateMeterRow(
            label: 'Secondary',
            remaining: secondaryRemaining,
            accent: ColonyColors.info,
          ),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(
              detail!,
              style: const TextStyle(fontSize: 10, color: ColonyColors.muted0),
            ),
          ],
        ],
      ),
    );
  }
}

class _RateMeterRow extends StatelessWidget {
  final String label;
  final double? remaining;
  final Color accent;

  const _RateMeterRow({
    required this.label,
    required this.remaining,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final progress = ((remaining ?? 0) / 100).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 54,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: ColonyColors.text1,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: remaining == null ? null : progress,
              minHeight: 6,
              backgroundColor: ColonyColors.surface2,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 42,
          child: Text(
            remaining == null ? '--' : '${remaining!.toStringAsFixed(0)}%',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 10,
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
