import 'dart:ui';

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../state/app_state.dart';
import '../drawer/project_drawer.dart';
import '../drawer/session_drawer.dart';

class BottomDrawer extends StatefulWidget {
  final AppState state;
  const BottomDrawer({super.key, required this.state});

  @override
  State<BottomDrawer> createState() => _BottomDrawerState();
}

class _BottomDrawerState extends State<BottomDrawer> {
  static const _snap = <double>[0.08, 0.42, 0.52, 0.92];
  double _factor = 0.08;
  bool _dragging = false;

  double _targetForSelection(Selection s) {
    return switch (s.kind) {
      SelectionKind.none => 0.08,
      SelectionKind.project => 0.42,
      SelectionKind.session => 0.52,
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
    if (oldWidget.state.selection.kind != widget.state.selection.kind) {
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

    // Keep a usable minimum height even on small windows.
    final minPx = 72.0 + bottom;
    final maxPx = (h * 0.92).clamp(minPx, h);
    final px = (h * _factor).clamp(minPx, maxPx);

    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedContainer(
        duration: _dragging ? Duration.zero : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        height: px,
        padding: EdgeInsets.fromLTRB(
          ColonySpacing.s4,
          0,
          ColonySpacing.s4,
          ColonySpacing.s4 + bottom,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(ColonyRadii.r3),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              decoration: BoxDecoration(
                color: ColonyColors.surface0.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(ColonyRadii.r3),
                border: Border.all(color: ColonyColors.border0),
              ),
              child: Column(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragStart: (_) => setState(() => _dragging = true),
                    onVerticalDragUpdate: (d) {
                      final next = (_factor - d.delta.dy / h).clamp(_snap.first, _snap.last);
                      setState(() => _factor = next);
                    },
                    onVerticalDragEnd: (_) {
                      final snapped = _snapTo(_factor);
                      setState(() {
                        _dragging = false;
                        _factor = snapped;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 10),
                      child: Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: ColonyColors.border0,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: ColonySpacing.s4),
                      child: _contentForSelection(widget.state.selection),
                    ),
                  ),
                  const SizedBox(height: ColonySpacing.s3),
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
      SelectionKind.project => ProjectDrawer(state: state, projectId: s.id),
      SelectionKind.session => SessionDrawer(state: state, address: s.id),
    };
  }
}

class _DrawerEmpty extends StatelessWidget {
  const _DrawerEmpty();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: Row(
        children: const [
          Icon(Icons.map_outlined, color: ColonyColors.text1),
          SizedBox(width: 12),
          Text('Select a building or agent', style: TextStyle(color: ColonyColors.text1)),
        ],
      ),
    );
  }
}
