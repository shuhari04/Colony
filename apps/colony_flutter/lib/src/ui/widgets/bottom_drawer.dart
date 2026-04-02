import 'dart:ui';

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../state/app_state.dart';
import '../drawer/building_drawer.dart';
import '../drawer/session_drawer.dart';

class BottomDrawer extends StatefulWidget {
  final AppState state;
  const BottomDrawer({super.key, required this.state});

  @override
  State<BottomDrawer> createState() => _BottomDrawerState();
}

class _BottomDrawerState extends State<BottomDrawer> {
  static const _snap = <double>[0.1, 0.42, 0.58, 0.92];
  double _factor = 0.1;
  bool _dragging = false;

  double _targetForSelection(Selection s) {
    return switch (s.kind) {
      SelectionKind.none => 0.1,
      SelectionKind.building => 0.42,
      SelectionKind.session => 0.58,
    };
  }

  @override
  void initState() {
    super.initState();
    _factor = _targetForSelection(widget.state.selection);
  }

  @override
  void didUpdateWidget(covariant BottomDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_dragging) return;
    if (oldWidget.state.selection.kind != widget.state.selection.kind ||
        oldWidget.state.selection.id != widget.state.selection.id) {
      final target = _targetForSelection(widget.state.selection);
      if ((_factor - target).abs() > 0.001) {
        setState(() => _factor = target);
      }
    }
  }

  double _snapTo(double factor) {
    var best = _snap.first;
    var bestD = (factor - best).abs();
    for (final s in _snap.skip(1)) {
      final d = (factor - s).abs();
      if (d < bestD) {
        best = s;
        bestD = d;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final h = mq.size.height;
    final bottom = mq.padding.bottom;
    final minPx = 92.0 + bottom;
    final maxPx = (h * _snap.last).clamp(minPx, h);
    final px = (h * _factor).clamp(minPx, maxPx);

    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedContainer(
        duration: _dragging ? Duration.zero : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        height: px,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(ColonyRadii.r3),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              decoration: BoxDecoration(
                color: ColonyColors.surface0.withValues(alpha: 0.82),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(ColonyRadii.r3),
                ),
                border: Border.all(color: ColonyColors.border0),
                boxShadow: ColonyShadows.panel,
              ),
              child: Column(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragStart: (_) =>
                        setState(() => _dragging = true),
                    onVerticalDragUpdate: (d) {
                      final next = (_factor - d.delta.dy / h).clamp(
                        _snap.first,
                        _snap.last,
                      );
                      setState(() => _factor = next);
                    },
                    onVerticalDragEnd: (_) {
                      final snapped = _snapTo(_factor);
                      setState(() {
                        _dragging = false;
                        _factor = snapped;
                      });
                    },
                    child: _DrawerHeader(
                      state: widget.state,
                      factor: _factor,
                      onSnap: (value) => setState(() => _factor = value),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        ColonySpacing.s4,
                        0,
                        ColonySpacing.s4,
                        ColonySpacing.s4 + bottom,
                      ),
                      child: _contentForSelection(widget.state.selection),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _contentForSelection(Selection s) {
    final state = widget.state;
    return switch (s.kind) {
      SelectionKind.none => const _DrawerEmpty(),
      SelectionKind.building => BuildingDrawer(state: state, buildingId: s.id),
      SelectionKind.session => SessionDrawer(state: state, address: s.id),
    };
  }
}

class _DrawerHeader extends StatelessWidget {
  final AppState state;
  final double factor;
  final ValueChanged<double> onSnap;

  const _DrawerHeader({
    required this.state,
    required this.factor,
    required this.onSnap,
  });

  @override
  Widget build(BuildContext context) {
    final selectedBuilding = state.boardBuildingById(state.selection.id);
    final title = switch (state.selection.kind) {
      SelectionKind.none => 'Inspector',
      SelectionKind.building =>
        selectedBuilding == null ? 'Building' : state.titleForBuildingKind(selectedBuilding.kind),
      SelectionKind.session =>
        state.sessionByAddress(state.selection.id)?.name ?? state.selection.id,
    };
    final subtitle = switch (state.selection.kind) {
      SelectionKind.none =>
        'Select a world, building, or worker to inspect it.',
      SelectionKind.building =>
        'Binding, worker control, and building configuration.',
      SelectionKind.session => 'Live output, controls, and prompt composer.',
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(
        ColonySpacing.s4,
        10,
        ColonySpacing.s4,
        ColonySpacing.s3,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: ColonyColors.border0.withValues(alpha: 0.8),
          ),
        ),
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: ColonyColors.border1,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: ColonySpacing.s3),
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: ColonyColors.text1,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Wrap(
                spacing: ColonySpacing.s2,
                children: [
                  _DrawerSnapButton(
                    label: 'Peek',
                    active: factor == 0.1,
                    onTap: () => onSnap(0.1),
                  ),
                  _DrawerSnapButton(
                    label: 'Half',
                    active: factor == 0.42 || factor == 0.58,
                    onTap: () => onSnap(0.58),
                  ),
                  _DrawerSnapButton(
                    label: 'Read',
                    active: factor == 0.92,
                    onTap: () => onSnap(0.92),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DrawerSnapButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _DrawerSnapButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? ColonyColors.accentCyan.withValues(alpha: 0.16)
              : ColonyColors.bg1.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? ColonyColors.accentCyan.withValues(alpha: 0.5)
                : ColonyColors.border0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: active ? ColonyColors.accentCyan : ColonyColors.text1,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _DrawerEmpty extends StatelessWidget {
  const _DrawerEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(ColonySpacing.s5),
        decoration: BoxDecoration(
          color: ColonyColors.bg1.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(ColonyRadii.r3),
          border: Border.all(color: ColonyColors.border0),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.explore_outlined, size: 28, color: ColonyColors.text1),
            SizedBox(height: ColonySpacing.s3),
            Text(
              'Select a village object',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: ColonySpacing.s2),
            Text(
              'Choose a world plate, town hall, hut, or worker to inspect live state and run actions.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: ColonyColors.text1,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
