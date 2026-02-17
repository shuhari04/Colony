import 'dart:ui';

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../model/entities.dart';
import '../../state/app_state.dart';
import '../dialogs/new_session_dialog.dart';

class WorldCanvas extends StatefulWidget {
  final AppState state;
  const WorldCanvas({super.key, required this.state});

  @override
  State<WorldCanvas> createState() => _WorldCanvasState();
}

class _WorldCanvasState extends State<WorldCanvas> {
  final TransformationController _tc = TransformationController();
  bool _didInitTransform = false;

  static const _sceneSize = Size(4000, 3000);
  static const _tileW = 96.0;
  static const _tileH = 48.0;
  static const _cubeW = 112.0;

  Offset _origin() => Offset(_sceneSize.width * 0.5, _sceneSize.height * 0.40);

  Offset _isoToScreen(double x, double y) {
    final o = _origin();
    final sx = (x - y) * (_tileW / 2.0);
    final sy = (x + y) * (_tileH / 2.0);
    return Offset(o.dx + sx, o.dy + sy);
  }

  (double dx, double dy) _screenDeltaToWorldDelta(Offset ds) {
    final dx = (ds.dy / _tileH) + (ds.dx / _tileW);
    final dy = (ds.dy / _tileH) - (ds.dx / _tileW);
    return (dx, dy);
  }

  @override
  void initState() {
    super.initState();
    // Defer initial camera framing until we know the viewport size.
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;

    return LayoutBuilder(
      builder: (context, c) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_didInitTransform) return;
          _didInitTransform = true;
          final viewport = Size(c.maxWidth, c.maxHeight);
          _frameInitialCamera(viewport);
        });

        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [ColonyColors.bg1, ColonyColors.bg0],
            ),
          ),
          child: InteractiveViewer(
            transformationController: _tc,
            constrained: false,
            boundaryMargin: const EdgeInsets.all(1200),
            minScale: 0.35,
            maxScale: 2.5,
            panEnabled: !state.buildMode,
            scaleEnabled: true,
            child: SizedBox(
              width: _sceneSize.width,
              height: _sceneSize.height,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _WorldPainter(origin: _origin(), tileW: _tileW, tileH: _tileH),
                    ),
                  ),
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () {
                        if (state.buildMode) {
                          state.toggleBuildMode(false);
                          return;
                        }
                        state.clearSelection();
                      },
                    ),
                  ),
                  for (final p in state.projects) _buildProjectWidget(p),
                  for (final p in state.projects) _buildHutWidget(p),
                  for (final s in state.sessions) _buildSessionWidget(s),
                  if (state.lastError != null) _buildError(state.lastError!),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _frameInitialCamera(Size viewport) {
    final o = _origin();
    // Put origin slightly above center so bases sit in a comfortable viewing area.
    final target = Offset(viewport.width * 0.5, viewport.height * 0.52);
    final t = target - o;
    _tc.value = Matrix4.identity()
      ..translateByDouble(t.dx, t.dy, 0, 1)
      ..scaleByDouble(1.05, 1.05, 1.0, 1.0);
  }

  Widget _buildProjectWidget(Project p) {
    final state = widget.state;
    final pos = _isoToScreen(p.x, p.y);
    final selected = state.selection.kind == SelectionKind.project && state.selection.id == p.id;
    return Positioned(
      left: pos.dx - _cubeW * 0.65,
      top: pos.dy - _cubeW * 0.95,
      width: _cubeW * 1.3,
      height: _cubeW * 1.25,
      child: _IsoCubeTile(
        label: p.name,
        accent: ColonyColors.accentCyan,
        selected: selected,
        showDragBadge: state.buildMode,
        onTap: () {
          if (state.buildMode) return;
          state.selectProject(p);
        },
        onLongPress: () => state.toggleBuildMode(true),
        onDragUpdate: (ds) {
          if (!state.buildMode) return;
          final (dx, dy) = _screenDeltaToWorldDelta(ds);
          state.moveProject(p.id, dx, dy);
        },
      ),
    );
  }

  Widget _buildHutWidget(Project base) {
    final state = widget.state;
    final pos = _isoToScreen(base.x - 1.4, base.y + 1.2);
    return Positioned(
      left: pos.dx - 70,
      top: pos.dy - 88,
      width: 140,
      height: 130,
      child: _IsoCubeTile(
        label: 'Hut',
        sublabel: '+ new agent',
        accent: ColonyColors.success,
        selected: false,
        icon: Icons.add,
        showDragBadge: state.buildMode,
        onTap: () async {
          if (state.buildMode) return;
          final res = await showDialog<NewSessionResult>(
            context: context,
            builder: (context) => const NewSessionDialog(),
          );
          if (res == null) return;
          await state.startNewSession(res.kind, res.name, model: res.model, nodeId: base.nodeId);
        },
        onLongPress: () => state.toggleBuildMode(true),
        onDragUpdate: (_) {},
      ),
    );
  }

  Widget _buildSessionWidget(Session s) {
    final state = widget.state;
    final pos = _isoToScreen(s.x, s.y);
    final selected = state.selection.kind == SelectionKind.session && state.selection.id == s.address;
    final c = switch (s.kind) {
      SessionKind.codex => ColonyColors.accentCyan,
      SessionKind.claude => ColonyColors.info,
      SessionKind.generic => ColonyColors.text1,
    };

    return Positioned(
      left: pos.dx - 62,
      top: pos.dy - 88,
      width: 140,
      height: 120,
      child: _IsoCubeTile(
        label: s.name,
        sublabel: s.kind == SessionKind.codex ? 'codex' : (s.kind == SessionKind.claude ? 'claude' : 'agent'),
        accent: c,
        selected: selected,
        showDragBadge: state.buildMode,
        onTap: () {
          if (state.buildMode) return;
          state.selectSession(s);
        },
        onLongPress: () => state.toggleBuildMode(true),
        onDragUpdate: (ds) {
          if (!state.buildMode) return;
          final (dx, dy) = _screenDeltaToWorldDelta(ds);
          state.moveSession(s.address, dx, dy);
        },
      ),
    );
  }

  Widget _buildError(String msg) {
    return Positioned(
      left: ColonySpacing.s4,
      right: ColonySpacing.s4,
      bottom: 110,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ColonyRadii.r2),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: ColonyColors.surface0.withValues(alpha: 0.8),
              border: Border.all(color: ColonyColors.danger.withValues(alpha: 0.75)),
              borderRadius: BorderRadius.circular(ColonyRadii.r2),
              boxShadow: ColonyShadows.glowSmall(ColonyColors.danger),
            ),
            child: Text(
              msg,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: ColonyColors.text0, fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }
}

class _WorldPainter extends CustomPainter {
  final Offset origin;
  final double tileW;
  final double tileH;

  _WorldPainter({required this.origin, required this.tileW, required this.tileH});

  @override
  void paint(Canvas canvas, Size size) {
    // Light vignette to keep the center readable.
    final vignette = Paint()
      ..shader = RadialGradient(
        colors: [
          ColonyColors.bg1.withValues(alpha: 0.0),
          ColonyColors.bg0.withValues(alpha: 0.55),
        ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: origin, radius: 1400));
    canvas.drawRect(Offset.zero & size, vignette);

    // 45-degree dot matrix (isometric lattice). Dots get slightly dimmer with distance.
    const span = 46;
    final base = Paint()..style = PaintingStyle.fill;
    for (var x = -span; x <= span; x++) {
      for (var y = -span; y <= span; y++) {
        final sx = origin.dx + (x - y) * (tileW / 2.0);
        final sy = origin.dy + (x + y) * (tileH / 2.0);
        final p = Offset(sx, sy);
        final d = (p - origin).distance;
        final t = (d / 1400.0).clamp(0.0, 1.0);
        final a = lerpDouble(0.62, 0.12, t)!;
        final r = lerpDouble(2.15, 1.20, t)!;

        // Subtle accent "constellation" to stop the ground reading as flat black.
        final isAccent = ((x + y) % 17 == 0) || ((x - y) % 23 == 0);
        final c = isAccent ? ColonyColors.accentCyan.withValues(alpha: a * 0.65) : ColonyColors.border0.withValues(alpha: a);
        base.color = c;
        canvas.drawCircle(p, r, base);
      }
    }

    // A faint "runway" axis to aid orientation.
    final axis = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = ColonyColors.border0.withValues(alpha: 0.22);
    canvas.drawLine(origin + const Offset(-1200, 0), origin + const Offset(1200, 0), axis);
  }

  @override
  bool shouldRepaint(covariant _WorldPainter oldDelegate) {
    return oldDelegate.origin != origin || oldDelegate.tileW != tileW || oldDelegate.tileH != tileH;
  }
}

class _IsoCubeTile extends StatelessWidget {
  final String label;
  final String? sublabel;
  final IconData? icon;
  final Color accent;
  final bool selected;
  final bool showDragBadge;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final void Function(Offset screenDelta) onDragUpdate;

  const _IsoCubeTile({
    required this.label,
    this.sublabel,
    this.icon,
    required this.accent,
    required this.selected,
    required this.showDragBadge,
    required this.onTap,
    required this.onLongPress,
    required this.onDragUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      onPanUpdate: showDragBadge ? (d) => onDragUpdate(d.delta) : null,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _IsoCubePainter(accent: accent, selected: selected),
            ),
          ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 16, color: ColonyColors.text0),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: ColonyColors.text0),
                      ),
                    ),
                  ],
                ),
                if (sublabel != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    sublabel!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: ColonyColors.text1),
                  ),
                ],
              ],
            ),
          ),
          if (showDragBadge)
            Positioned(
              right: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: ColonyColors.surface1.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: ColonyColors.warning.withValues(alpha: 0.6)),
                ),
                child: const Text(
                  'drag',
                  style: TextStyle(fontSize: 11, color: ColonyColors.warning, fontWeight: FontWeight.w800),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _IsoCubePainter extends CustomPainter {
  final Color accent;
  final bool selected;

  _IsoCubePainter({required this.accent, required this.selected});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.5;
    final baseY = h * 0.62;

    final tileW = w * 0.62;
    final tileH = tileW * 0.5;
    final z = tileW * 0.42;

    final pTop = Offset(cx, baseY - z);
    final pR = Offset(cx + tileW / 2, baseY - z + tileH / 2);
    final pB = Offset(cx, baseY - z + tileH);
    final pL = Offset(cx - tileW / 2, baseY - z + tileH / 2);

    final pR2 = pR + Offset(0, z);
    final pB2 = pB + Offset(0, z);
    final pL2 = pL + Offset(0, z);

    final top = Path()..addPolygon([pTop, pR, pB, pL], true);
    final left = Path()..addPolygon([pL, pB, pB2, pL2], true);
    final right = Path()..addPolygon([pR, pB, pB2, pR2], true);

    final topFill = Paint()..color = accent.withValues(alpha: 0.18);
    final leftFill = Paint()..color = ColonyColors.surface1.withValues(alpha: 0.78);
    final rightFill = Paint()..color = ColonyColors.surface0.withValues(alpha: 0.78);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = (selected ? accent : ColonyColors.border0).withValues(alpha: selected ? 0.85 : 0.65);

    if (selected) {
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = accent.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawPath(top, glow);
      canvas.drawPath(left, glow);
      canvas.drawPath(right, glow);
    }

    canvas.drawPath(left, leftFill);
    canvas.drawPath(right, rightFill);
    canvas.drawPath(top, topFill);

    canvas.drawPath(left, stroke);
    canvas.drawPath(right, stroke);
    canvas.drawPath(top, stroke);

    // A tiny top highlight so it reads as "glass" instead of flat.
    final hi = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = ColonyColors.text0.withValues(alpha: 0.08);
    canvas.drawLine(pTop + const Offset(0, 2), pR + const Offset(-6, 3), hi);
  }

  @override
  bool shouldRepaint(covariant _IsoCubePainter oldDelegate) {
    return oldDelegate.accent != accent || oldDelegate.selected != selected;
  }
}
