import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/building.dart';
import '../../domain/worker.dart';
import '../../model/board.dart';
import '../../state/app_state.dart';
import '../dialogs/server_config_dialog.dart';

class BuildingDrawer extends StatelessWidget {
  final AppState state;
  final String buildingId;

  const BuildingDrawer({
    super.key,
    required this.state,
    required this.buildingId,
  });

  @override
  Widget build(BuildContext context) {
    final building = state.boardBuildingById(buildingId);
    if (building == null) {
      return const _EmptyNotice(
        icon: Icons.domain_disabled_outlined,
        title: 'Building missing',
        body: 'This building is no longer on the board.',
      );
    }

    final workers = state.workersOwnedByMachine(building.id);
    final accent = _accentForBuilding(building);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(ColonySpacing.s4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accent.withValues(alpha: 0.18),
                  ColonyColors.surface1.withValues(alpha: 0.96),
                ],
              ),
              borderRadius: BorderRadius.circular(ColonyRadii.r3),
              border: Border.all(color: accent.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: ColonyColors.surface0.withValues(alpha: 0.76),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.35),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(13),
                        child: Image.asset(
                          state.assetPathForBuilding(building),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(width: ColonySpacing.s3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.titleForBuildingKind(building.kind),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            state.subtitleForBuilding(building),
                            style: const TextStyle(
                              fontSize: 12,
                              color: ColonyColors.text1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _Badge(
                      label: '(${building.origin.x}, ${building.origin.y})',
                      color: accent,
                    ),
                  ],
                ),
                const SizedBox(height: ColonySpacing.s4),
                Wrap(
                  spacing: ColonySpacing.s2,
                  runSpacing: ColonySpacing.s2,
                  children: [
                    _MetricCard(
                      label: 'Footprint',
                      value:
                          '${state.footprintFor(building).length} tile${state.footprintFor(building).length == 1 ? '' : 's'}',
                      accent: accent,
                    ),
                    _MetricCard(
                      label: 'Workers',
                      value: '${workers.length}',
                      accent: ColonyColors.success,
                    ),
                    _MetricCard(
                      label: 'Finish',
                      value: building.finishVisible ? 'Visible' : 'Idle',
                      accent: building.finishVisible
                          ? ColonyColors.warning
                          : ColonyColors.text1,
                    ),
                  ],
                ),
                const SizedBox(height: ColonySpacing.s4),
                Wrap(
                  spacing: ColonySpacing.s2,
                  runSpacing: ColonySpacing.s2,
                  children: _actionsFor(context, building, workers),
                ),
              ],
            ),
          ),
          const SizedBox(height: ColonySpacing.s4),
          if (building.kind == BoardBuildingKind.machine) ...[
            const Text(
              'Workers',
              style: TextStyle(
                fontSize: 12,
                color: ColonyColors.text1,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: ColonySpacing.s2),
            if (workers.isEmpty)
              const _EmptyNotice(
                icon: Icons.bubble_chart_outlined,
                title: 'No workers yet',
                body:
                    'Create a worker from this machine, then click the worker ball on the board to assign it.',
              )
            else
              ...workers.map(
                (worker) => _WorkerRow(state: state, worker: worker),
              ),
          ],
          if (building.kind == BoardBuildingKind.server &&
              building.serverConfig != null) ...[
            const SizedBox(height: ColonySpacing.s4),
            const Text(
              'Remote Config',
              style: TextStyle(
                fontSize: 12,
                color: ColonyColors.text1,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: ColonySpacing.s2),
            _ServerBlock(config: building.serverConfig!),
          ],
        ],
      ),
    );
  }

  List<Widget> _actionsFor(
    BuildContext context,
    PlacedBuilding building,
    List<PlacedWorker> workers,
  ) {
    final deleteAction = OutlinedButton.icon(
      onPressed: () => _confirmDeleteBuilding(context, building),
      icon: const Icon(Icons.delete_outline_rounded, size: 16),
      label: const Text('Delete'),
      style: OutlinedButton.styleFrom(
        foregroundColor: ColonyColors.danger,
        side: BorderSide(color: ColonyColors.danger.withValues(alpha: 0.55)),
      ),
    );

    final actions = switch (building.kind) {
      BoardBuildingKind.buildingWorkspace ||
      BoardBuildingKind.buildingAltA ||
      BoardBuildingKind.buildingAltB => [
        FilledButton.tonalIcon(
          onPressed: () => state.bindWorkspaceForBuilding(building.id),
          icon: const Icon(Icons.folder_open_rounded, size: 16),
          label: Text(
            (building.workspacePath ?? '').isEmpty
                ? 'Choose Workspace'
                : 'Change Workspace',
          ),
        ),
      ],
      BoardBuildingKind.machine => [
        FilledButton.tonalIcon(
          onPressed: () => state.createWorkerForMachine(building.id),
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('New Worker'),
        ),
        if (workers.isNotEmpty)
          FilledButton.tonalIcon(
            onPressed: () => state.beginWorkerAssignment(workers.first.id),
            icon: const Icon(Icons.send_to_mobile_rounded, size: 16),
            label: const Text('Assign Latest'),
          ),
      ],
      BoardBuildingKind.server => [
        FilledButton.tonalIcon(
          onPressed: () async {
            final existing = building.serverConfig;
            final result = await showDialog<ServerConfigDialogResult>(
              context: context,
              builder: (context) => ServerConfigDialog(initial: existing),
            );
            if (result == null) return;
            await state.configureServerBuilding(
              building.id,
              alias: result.alias,
              host: result.host,
              password: result.password,
            );
          },
          icon: const Icon(Icons.settings_ethernet_rounded, size: 16),
          label: const Text('Configure'),
        ),
      ],
      BoardBuildingKind.kanban || BoardBuildingKind.workflowLine => <Widget>[],
    };

    return [...actions, deleteAction];
  }

  Future<void> _confirmDeleteBuilding(
    BuildContext context,
    PlacedBuilding building,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ColonyColors.surface0,
        title: const Text('Delete Building'),
        content: Text(
          'Delete ${state.titleForBuildingKind(building.kind)} from the board?',
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
      await state.deleteBuilding(building.id);
    }
  }

  Color _accentForBuilding(PlacedBuilding building) {
    return switch (building.kind) {
      BoardBuildingKind.buildingWorkspace => ColonyColors.accentCyan,
      BoardBuildingKind.buildingAltA => ColonyColors.info,
      BoardBuildingKind.buildingAltB => ColonyColors.warning,
      BoardBuildingKind.server => ColonyColors.success,
      BoardBuildingKind.kanban => ColonyColors.text1,
      BoardBuildingKind.machine => switch (building.provider) {
        AgentProvider.codex => ColonyColors.accentCyan,
        AgentProvider.claude => ColonyColors.info,
        AgentProvider.openclaw => ColonyColors.success,
        AgentProvider.other || AgentProvider.none => ColonyColors.text1,
      },
      BoardBuildingKind.workflowLine => ColonyColors.warning,
    };
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 136,
      padding: const EdgeInsets.all(ColonySpacing.s3),
      decoration: BoxDecoration(
        color: ColonyColors.bg1.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: ColonyColors.text1),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

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

class _WorkerRow extends StatelessWidget {
  final AppState state;
  final PlacedWorker worker;

  const _WorkerRow({required this.state, required this.worker});

  @override
  Widget build(BuildContext context) {
    final session = worker.sessionAddress == null
        ? null
        : state.sessionByAddress(worker.sessionAddress!);
    final color = switch (worker.provider) {
      AgentProvider.codex => ColonyColors.accentCyan,
      AgentProvider.claude => ColonyColors.info,
      AgentProvider.openclaw => ColonyColors.success,
      AgentProvider.other || AgentProvider.none => ColonyColors.text1,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(ColonySpacing.s3),
      decoration: BoxDecoration(
        color: ColonyColors.bg1.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(ColonyRadii.r2),
        border: Border.all(color: ColonyColors.border0),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.18),
              border: Border.all(color: color.withValues(alpha: 0.42)),
            ),
          ),
          const SizedBox(width: ColonySpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session?.name ?? worker.id,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  switch (worker.status) {
                    WorkerStatus.idle => 'Idle',
                    WorkerStatus.routing => 'Routing',
                    WorkerStatus.working => 'Working',
                    WorkerStatus.blocked => 'Blocked',
                    WorkerStatus.done => 'Done',
                  },
                  style: const TextStyle(
                    fontSize: 11,
                    color: ColonyColors.text1,
                  ),
                ),
              ],
            ),
          ),
          if (session != null)
            TextButton(
              onPressed: () => state.selectSession(session),
              child: const Text('Open'),
            ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: () => state.beginWorkerAssignment(worker.id),
            child: const Text('Assign'),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Delete worker',
            onPressed: () => _confirmDeleteWorker(context),
            color: ColonyColors.danger,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteWorker(BuildContext context) async {
    final label = worker.sessionAddress ?? worker.id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ColonyColors.surface0,
        title: const Text('Delete Worker'),
        content: Text(
          'Delete $label? This will stop its session if one is attached.',
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
      await state.deleteWorker(worker.id);
    }
  }
}

class _ServerBlock extends StatelessWidget {
  final ServerConfig config;

  const _ServerBlock({required this.config});

  @override
  Widget build(BuildContext context) {
    final color = switch (config.status) {
      'connected' => ColonyColors.success,
      'connecting' => ColonyColors.warning,
      'failed' => ColonyColors.danger,
      _ => ColonyColors.text1,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ColonySpacing.s3),
      decoration: BoxDecoration(
        color: ColonyColors.bg1.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(ColonyRadii.r2),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            config.alias,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            config.host,
            style: const TextStyle(fontSize: 12, color: ColonyColors.text1),
          ),
          const SizedBox(height: 8),
          _Badge(label: config.status, color: color),
          if ((config.error ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              config.error!,
              style: const TextStyle(fontSize: 11, color: ColonyColors.text1),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyNotice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _EmptyNotice({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ColonySpacing.s4),
      decoration: BoxDecoration(
        color: ColonyColors.bg1.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(ColonyRadii.r2),
        border: Border.all(color: ColonyColors.border0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: ColonyColors.text1),
          const SizedBox(height: ColonySpacing.s2),
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(fontSize: 12, color: ColonyColors.text1),
          ),
        ],
      ),
    );
  }
}
