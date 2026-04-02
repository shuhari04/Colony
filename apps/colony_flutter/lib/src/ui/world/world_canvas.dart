import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/building.dart';
import '../../model/board.dart';
import '../../state/app_state.dart';

class WorldCanvas extends StatefulWidget {
  final AppState state;

  const WorldCanvas({super.key, required this.state});

  @override
  State<WorldCanvas> createState() => _WorldCanvasState();
}

class _WorldCanvasState extends State<WorldCanvas>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  final TransformationController _tc = TransformationController();
  final GlobalKey _viewerKey = GlobalKey();
  bool _didInitTransform = false;

  static const _sceneSize = Size(2400, 1800);

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _tc.dispose();
    super.dispose();
  }

  void _frameInitialCamera(Size viewport) {
    final target = Offset(viewport.width * 0.5, viewport.height * 0.42);
    final focus = Offset(_sceneSize.width * 0.5, _sceneSize.height * 0.34);
    final shift = target - focus;
    _tc.value = Matrix4.identity()
      ..translateByDouble(shift.dx, shift.dy, 0, 1)
      ..scaleByDouble(0.9, 0.9, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final geometry = _BoardGeometry.fromSize(_sceneSize);
            final draftBuilding = widget.state.draftBuildingId == null
                ? null
                : widget.state.boardBuildingById(widget.state.draftBuildingId!);

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_didInitTransform) return;
              _didInitTransform = true;
              _frameInitialCamera(
                Size(constraints.maxWidth, constraints.maxHeight),
              );
            });

            return Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF04060B),
                    ColonyColors.bg0,
                    Color(0xFF09111F),
                  ],
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _BackgroundPainter(pulse: _pulse.value),
                    ),
                  ),
                  Positioned.fill(
                    child: InteractiveViewer(
                      key: _viewerKey,
                      transformationController: _tc,
                      constrained: false,
                      boundaryMargin: const EdgeInsets.all(1200),
                      minScale: 0.45,
                      maxScale: 2.4,
                      panEnabled: true,
                      scaleEnabled: true,
                      trackpadScrollCausesScale: false,
                      child: SizedBox(
                        width: _sceneSize.width,
                        height: _sceneSize.height,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () => widget.state.handleBackgroundTap(),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _BoardPainter(
                                    geometry: geometry,
                                    buildings: widget.state.boardBuildings,
                                    selectedBuildingId:
                                        widget.state.selection.kind ==
                                            SelectionKind.building
                                        ? widget.state.selection.id
                                        : null,
                                    draftBuilding: draftBuilding,
                                    draftLegal: draftBuilding == null
                                        ? true
                                        : widget.state
                                              .isPlacementLegalForBuilding(
                                                draftBuilding,
                                              ),
                                    assigningWorkerId:
                                        widget.state.assigningWorkerId,
                                    workers: widget.state.boardWorkers,
                                    pulse: _pulse.value,
                                  ),
                                ),
                              ),
                              for (final building
                                  in widget.state.boardBuildings)
                                _buildBuildingNode(
                                  building,
                                  geometry,
                                  _pulse.value,
                                ),
                              for (final worker in widget.state.boardWorkers)
                                _buildWorkerNode(worker, geometry),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.state.lastError != null)
                    Positioned(
                      left: ColonySpacing.s4,
                      right: ColonySpacing.s4,
                      bottom: 116,
                      child: _ErrorToast(message: widget.state.lastError!),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBuildingNode(
    PlacedBuilding building,
    _BoardGeometry geometry,
    double pulse,
  ) {
    final isDraft = widget.state.draftBuildingId == building.id;
    final breathing = isDraft;
    final pulseOpacity = breathing
        ? (0.72 + math.sin(pulse * math.pi * 2) * 0.18).clamp(0.52, 0.94)
        : 1.0;
    final spriteSize = _spriteSizeFor(building.kind);
    final anchor = geometry.anchorForBuilding(building);
    final top =
        anchor.dy -
        spriteSize.height +
        _floorOffsetFor(building.kind) +
        geometry.tileH;
    final left = anchor.dx - spriteSize.width / 2;

    return Positioned(
      left: left,
      top: top,
      width: spriteSize.width,
      height: spriteSize.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _onBuildingTap(building),
        onPanUpdate: widget.state.draftBuildingId == building.id
            ? (details) =>
                  _updateDraftFromGlobal(details.globalPosition, geometry)
            : null,
        onLongPressStart: (_) => widget.state.beginMovingBuilding(building.id),
        onLongPressMoveUpdate: (details) =>
            _updateDraftFromGlobal(details.globalPosition, geometry),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: pulseOpacity,
                child: Transform.scale(
                  scale: _spriteScaleFor(building.kind),
                  child: Image.asset(
                    widget.state.assetPathForBuilding(building),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            Positioned(
              top: -28,
              left: spriteSize.width / 2 - 40,
              width: 80,
              child: AnimatedOpacity(
                duration: Duration(
                  milliseconds: building.finishVisible ? 220 : 180,
                ),
                curve: Curves.easeOutCubic,
                opacity: building.finishVisible ? 1 : 0,
                child: Image.asset(
                  'assets/colony_res/finish.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkerNode(PlacedWorker worker, _BoardGeometry geometry) {
    final offset = geometry.anchorForWorker(
      worker,
      widget.state.boardBuildings,
      widget.state.boardWorkers,
    );
    final selectedAddress = widget.state.selection.kind == SelectionKind.session
        ? widget.state.selection.id
        : null;
    final selected =
        selectedAddress != null && worker.sessionAddress == selectedAddress;
    final assigning = widget.state.assigningWorkerId == worker.id;
    final color = _workerColor(worker.provider);

    return Positioned(
      left: offset.dx - 18,
      top: offset.dy - 18,
      width: 36,
      height: 36,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.state.beginWorkerAssignment(worker.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: selected || assigning ? 0.95 : 0.88),
            border: Border.all(
              color: (selected || assigning
                  ? Colors.white
                  : color.withValues(alpha: 0.35)),
              width: selected || assigning ? 2 : 1,
            ),
            boxShadow: [...ColonyShadows.glowSmall(color)],
          ),
          child: Center(
            child: Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: ColonyColors.surface0,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _updateDraftFromGlobal(Offset globalPosition, _BoardGeometry geometry) {
    if (widget.state.draftBuildingId == null) return;
    final renderBox =
        _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final local = renderBox.globalToLocal(globalPosition);
    final scenePoint = _tc.toScene(local);
    final point = geometry.gridFromScene(scenePoint);
    widget.state.updateDraftBuildingOrigin(point);
  }

  Future<void> _onBuildingTap(PlacedBuilding building) async {
    await widget.state.handleBuildingTap(building.id);
  }

  Size _spriteSizeFor(BoardBuildingKind kind) {
    return switch (kind) {
      BoardBuildingKind.buildingWorkspace => const Size(208, 200),
      BoardBuildingKind.buildingAltA => const Size(194, 184),
      BoardBuildingKind.buildingAltB => const Size(194, 184),
      BoardBuildingKind.server => const Size(188, 178),
      BoardBuildingKind.kanban => const Size(180, 170),
      BoardBuildingKind.machine => const Size(260, 210),
      BoardBuildingKind.workflowLine => const Size(560, 180),
    };
  }

  double _floorOffsetFor(BoardBuildingKind kind) {
    return switch (kind) {
      BoardBuildingKind.workflowLine => 42,
      BoardBuildingKind.machine => 34,
      _ => 26,
    };
  }

  double _spriteScaleFor(BoardBuildingKind kind) {
    return switch (kind) {
      BoardBuildingKind.workflowLine => 1.02,
      BoardBuildingKind.machine => 0.98,
      _ => 1,
    };
  }

  Color _workerColor(AgentProvider provider) {
    return switch (provider) {
      AgentProvider.codex => ColonyColors.accentCyan,
      AgentProvider.claude => ColonyColors.info,
      AgentProvider.openclaw => ColonyColors.success,
      AgentProvider.other || AgentProvider.none => ColonyColors.text1,
    };
  }
}

class _BoardGeometry {
  final Size viewport;
  final double tileW;
  final double tileH;
  final Offset origin;

  const _BoardGeometry({
    required this.viewport,
    required this.tileW,
    required this.tileH,
    required this.origin,
  });

  factory _BoardGeometry.fromSize(Size size) {
    final tileW = math.min(
      70.0,
      math.max(40.0, (size.width - 280) / AppState.boardDimension),
    );
    final tileH = tileW * 0.55;
    final origin = Offset(size.width * 0.5, math.max(140, size.height * 0.16));
    return _BoardGeometry(
      viewport: size,
      tileW: tileW,
      tileH: tileH,
      origin: origin,
    );
  }

  Offset screenForCell(GridPoint point) {
    return Offset(
      origin.dx + (point.x - point.y) * tileW / 2,
      origin.dy + (point.x + point.y) * tileH / 2,
    );
  }

  GridPoint gridFromScene(Offset point) {
    final dx = point.dx - origin.dx;
    final dy = point.dy - origin.dy;
    final gx = ((dx / (tileW / 2)) + (dy / (tileH / 2))) / 2;
    final gy = ((dy / (tileH / 2)) - (dx / (tileW / 2))) / 2;
    return GridPoint(
      x: gx.round().clamp(0, AppState.boardDimension - 1),
      y: gy.round().clamp(0, AppState.boardDimension - 1),
    );
  }

  Offset anchorForBuilding(PlacedBuilding building) {
    final cells = _footprintCells(
      building,
    ).map(screenForCell).toList(growable: false);
    final avgX =
        cells.fold<double>(0, (sum, item) => sum + item.dx) / cells.length;
    final avgY =
        cells.fold<double>(0, (sum, item) => sum + item.dy) / cells.length;
    return Offset(avgX, avgY + tileH * 0.3);
  }

  List<GridPoint> _footprintCells(PlacedBuilding building) {
    final length = switch (building.kind) {
      BoardBuildingKind.machine => 2,
      BoardBuildingKind.workflowLine => 5,
      _ => 1,
    };
    final expandOnX = building.orientation == BoardOrientation.r;
    return [
      for (var index = 0; index < length; index++)
        GridPoint(
          x: expandOnX ? building.origin.x + index : building.origin.x,
          y: expandOnX ? building.origin.y : building.origin.y + index,
        ),
    ];
  }

  Offset anchorForWorker(
    PlacedWorker worker,
    List<PlacedBuilding> buildings,
    List<PlacedWorker> workers,
  ) {
    final home = buildings
        .where((building) => building.id == worker.homeBuildingId)
        .firstOrNull;
    final target = worker.assignedBuildingId == null
        ? null
        : buildings
              .where((building) => building.id == worker.assignedBuildingId)
              .firstOrNull;
    final basis = target ?? home;
    if (basis == null) return origin;
    final anchor = anchorForBuilding(basis);
    final siblings = workers
        .where((item) {
          final itemBasis = item.assignedBuildingId ?? item.homeBuildingId;
          return itemBasis ==
              (worker.assignedBuildingId ?? worker.homeBuildingId);
        })
        .toList(growable: false);
    final index = siblings
        .indexWhere((item) => item.id == worker.id)
        .clamp(0, 6);
    final dx = ((index % 3) - 1) * 18.0;
    final dy = (index ~/ 3) * -14.0;
    return Offset(anchor.dx + dx, anchor.dy - (target == null ? 18 : 42) + dy);
  }
}

class _BackgroundPainter extends CustomPainter {
  final double pulse;

  const _BackgroundPainter({required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    final starPaint = Paint()
      ..color = ColonyColors.info.withValues(alpha: 0.08);
    for (var x = 0.0; x < size.width; x += 84) {
      for (var y = 0.0; y < size.height; y += 72) {
        final wobble = math.sin((x + y) / 120 + pulse * math.pi * 2) * 2;
        canvas.drawCircle(Offset(x + 28, y + 20 + wobble), 1.6, starPaint);
      }
    }
    final glow = Paint()
      ..shader =
          RadialGradient(
            colors: [
              ColonyColors.accentCyan.withValues(alpha: 0.12),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.5, size.height * 0.35),
              radius: size.width * 0.4,
            ),
          );
    canvas.drawRect(Offset.zero & size, glow);
  }

  @override
  bool shouldRepaint(covariant _BackgroundPainter oldDelegate) {
    return oldDelegate.pulse != pulse;
  }
}

class _BoardPainter extends CustomPainter {
  final _BoardGeometry geometry;
  final List<PlacedBuilding> buildings;
  final String? selectedBuildingId;
  final PlacedBuilding? draftBuilding;
  final bool draftLegal;
  final String? assigningWorkerId;
  final List<PlacedWorker> workers;
  final double pulse;

  const _BoardPainter({
    required this.geometry,
    required this.buildings,
    required this.selectedBuildingId,
    required this.draftBuilding,
    required this.draftLegal,
    required this.assigningWorkerId,
    required this.workers,
    required this.pulse,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final boardRect = Path();
    boardRect.addPolygon([
      geometry.screenForCell(const GridPoint(x: 0, y: 0)) +
          Offset(0, -geometry.tileH / 2),
      geometry.screenForCell(
            const GridPoint(x: AppState.boardDimension - 1, y: 0),
          ) +
          Offset(geometry.tileW / 2, geometry.tileH / 2),
      geometry.screenForCell(
            const GridPoint(
              x: AppState.boardDimension - 1,
              y: AppState.boardDimension - 1,
            ),
          ) +
          Offset(0, geometry.tileH * 1.4),
      geometry.screenForCell(
            const GridPoint(x: 0, y: AppState.boardDimension - 1),
          ) +
          Offset(-geometry.tileW / 2, geometry.tileH / 2),
    ], true);

    final floorFill = Paint()
      ..shader = LinearGradient(
        colors: [
          ColonyColors.surface2.withValues(alpha: 0.84),
          ColonyColors.bg1.withValues(alpha: 0.98),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(boardRect.getBounds());
    canvas.drawPath(boardRect, floorFill);

    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = ColonyColors.accentCyan.withValues(alpha: 0.18);
    canvas.drawPath(boardRect, edgePaint);

    final occupied = <String, Color>{};
    for (final building in buildings) {
      final color = switch (building.kind) {
        BoardBuildingKind.machine => _accentForProvider(
          building.provider,
        ).withValues(alpha: 0.18),
        BoardBuildingKind.server => ColonyColors.success.withValues(
          alpha: 0.16,
        ),
        BoardBuildingKind.buildingWorkspace =>
          ColonyColors.accentCyan.withValues(alpha: 0.16),
        BoardBuildingKind.buildingAltA => ColonyColors.info.withValues(
          alpha: 0.12,
        ),
        BoardBuildingKind.buildingAltB => ColonyColors.warning.withValues(
          alpha: 0.12,
        ),
        BoardBuildingKind.kanban => ColonyColors.text1.withValues(alpha: 0.12),
        BoardBuildingKind.workflowLine => ColonyColors.warning.withValues(
          alpha: 0.14,
        ),
      };
      final footprint = geometry._footprintCells(building);
      for (final cell in footprint) {
        occupied['${cell.x}:${cell.y}'] = color;
      }
    }

    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = ColonyColors.border1.withValues(alpha: 0.28);

    for (var y = 0; y < AppState.boardDimension; y++) {
      for (var x = 0; x < AppState.boardDimension; x++) {
        final cell = GridPoint(x: x, y: y);
        final center = geometry.screenForCell(cell);
        final tile = _diamond(center, geometry.tileW, geometry.tileH);
        final key = '$x:$y';
        final fillColor = occupied[key];
        if (fillColor != null) {
          canvas.drawPath(tile, Paint()..color = fillColor);
        } else {
          canvas.drawPath(
            tile,
            Paint()..color = ColonyColors.surface1.withValues(alpha: 0.18),
          );
        }
        canvas.drawPath(tile, gridPaint);
      }
    }

    if (draftBuilding != null) {
      final footprint = geometry._footprintCells(draftBuilding!);
      final color = draftLegal
          ? ColonyColors.accentCyan.withValues(alpha: 0.26)
          : ColonyColors.danger.withValues(alpha: 0.32);
      for (final cell in footprint) {
        if (cell.x < 0 ||
            cell.x >= AppState.boardDimension ||
            cell.y < 0 ||
            cell.y >= AppState.boardDimension) {
          continue;
        }
        final center = geometry.screenForCell(cell);
        canvas.drawPath(
          _diamond(center, geometry.tileW, geometry.tileH),
          Paint()..color = color,
        );
      }
    }

    final activeBuilding = draftBuilding;
    if (activeBuilding != null) {
      final footprint = geometry._footprintCells(activeBuilding);
      final pulseAlpha = 0.55 + math.sin(pulse * math.pi * 2) * 0.18;
      final strokeColor = (draftBuilding != null && !draftLegal)
          ? ColonyColors.danger.withValues(alpha: pulseAlpha.clamp(0.3, 0.85))
          : Colors.white.withValues(alpha: pulseAlpha.clamp(0.35, 0.92));
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = strokeColor;
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
        ..color = strokeColor.withValues(
          alpha: pulseAlpha.clamp(0.35, 0.92) * 0.28,
        );
      for (final cell in footprint) {
        if (cell.x < 0 ||
            cell.x >= AppState.boardDimension ||
            cell.y < 0 ||
            cell.y >= AppState.boardDimension) {
          continue;
        }
        final center = geometry.screenForCell(cell);
        final diamond = _diamond(center, geometry.tileW, geometry.tileH);
        canvas.drawPath(diamond, glow);
        canvas.drawPath(diamond, stroke);
      }
    }

    if (assigningWorkerId != null) {
      final shimmer = 0.35 + math.sin(pulse * math.pi * 2) * 0.08;
      for (final building in buildings.where(
        (item) => item.kind != BoardBuildingKind.machine,
      )) {
        final anchor = geometry.anchorForBuilding(building);
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = ColonyColors.warning.withValues(alpha: shimmer);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: anchor, width: 140, height: 64),
            const Radius.circular(18),
          ),
          paint,
        );
      }
    }
  }

  Path _diamond(Offset center, double tileW, double tileH) {
    return Path()
      ..moveTo(center.dx, center.dy - tileH / 2)
      ..lineTo(center.dx + tileW / 2, center.dy)
      ..lineTo(center.dx, center.dy + tileH / 2)
      ..lineTo(center.dx - tileW / 2, center.dy)
      ..close();
  }

  Color _accentForProvider(AgentProvider provider) {
    return switch (provider) {
      AgentProvider.codex => ColonyColors.accentCyan,
      AgentProvider.claude => ColonyColors.info,
      AgentProvider.openclaw => ColonyColors.success,
      AgentProvider.other || AgentProvider.none => ColonyColors.text1,
    };
  }

  @override
  bool shouldRepaint(covariant _BoardPainter oldDelegate) {
    return oldDelegate.geometry != geometry ||
        oldDelegate.buildings != buildings ||
        oldDelegate.selectedBuildingId != selectedBuildingId ||
        oldDelegate.draftBuilding != draftBuilding ||
        oldDelegate.draftLegal != draftLegal ||
        oldDelegate.assigningWorkerId != assigningWorkerId ||
        oldDelegate.workers != workers ||
        oldDelegate.pulse != pulse;
  }
}

class _ErrorToast extends StatelessWidget {
  final String message;

  const _ErrorToast({required this.message});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ColonyRadii.r2),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: ColonyColors.surface0.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(ColonyRadii.r2),
              border: Border.all(
                color: ColonyColors.danger.withValues(alpha: 0.72),
              ),
              boxShadow: ColonyShadows.glowMedium(ColonyColors.danger),
            ),
            child: Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ColonyColors.text0,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
