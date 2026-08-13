import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../application/library_contracts.dart';
import '../../application/visual_analysis_review_session.dart';
import '../../application/visual_image_processor.dart';
import '../../domain/visual_chart_models.dart';
import '../../domain/visual_tab_transform_models.dart';

class AnalysisRowPlaceholder extends StatelessWidget {
  const AnalysisRowPlaceholder({
    super.key,
    required this.rowNumber,
    required this.strip,
    required this.state,
    this.error,
    this.onRetry,
  });

  final int rowNumber;
  final VisualStrip strip;
  final VisualAnalysisRowState state;
  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: AspectRatio(
        aspectRatio: strip.croppedAspectRatio,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (state == VisualAnalysisRowState.analyzing)
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  state == VisualAnalysisRowState.failed
                      ? Icons.error_outline
                      : Icons.hourglass_empty,
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  state == VisualAnalysisRowState.failed
                      ? 'Row $rowNumber failed: $error'
                      : state == VisualAnalysisRowState.analyzing
                      ? 'Row $rowNumber - analyzing locally'
                      : 'Row $rowNumber - waiting for local analysis',
                ),
              ),
              if (onRetry != null)
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry row'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class VisualAnalysisCanvas extends StatefulWidget {
  const VisualAnalysisCanvas({
    super.key,
    required this.library,
    required this.strip,
    required this.analysis,
    required this.selectedTokenIds,
    required this.drawing,
    required this.drawStart,
    required this.drawEnd,
    required this.onTokenTap,
    required this.onDrawStart,
    required this.onDrawUpdate,
    required this.onDrawEnd,
  });

  final ChartLibrary library;
  final VisualStrip strip;
  final VisualTabAnalysis analysis;
  final Set<String> selectedTokenIds;
  final bool drawing;
  final Offset? drawStart;
  final Offset? drawEnd;
  final ValueChanged<String> onTokenTap;
  final ValueChanged<Offset> onDrawStart;
  final ValueChanged<Offset> onDrawUpdate;
  final ValueChanged<NormalizedRect?> onDrawEnd;

  @override
  State<VisualAnalysisCanvas> createState() => VisualAnalysisCanvasState();
}

class VisualAnalysisCanvasState extends State<VisualAnalysisCanvas> {
  late Future<Uint8List> _preview;
  int? _activeDrawPointer;
  Offset? _drawPointerStart;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant VisualAnalysisCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.strip.id != widget.strip.id) _load();
    if (oldWidget.drawing && !widget.drawing) {
      _activeDrawPointer = null;
      _drawPointerStart = null;
    }
  }

  void _load() {
    _preview =
        File(
          widget.library.assetPath(
            widget.strip.assetHash,
            widget.strip.assetExtension,
          ),
        ).readAsBytes().then(
          (bytes) => compute(_renderAnalysisPreview, {
            'bytes': bytes,
            'strip': widget.strip.toJson(),
          }),
        );
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: widget.strip.croppedAspectRatio,
      child: LayoutBuilder(
        builder: (context, constraints) {
          Offset normalize(Offset local) => Offset(
            (local.dx / constraints.maxWidth).clamp(0.0, 1.0),
            (local.dy / constraints.maxHeight).clamp(0.0, 1.0),
          );
          final guide =
              _nearestDrawStringGuide(
                widget.analysis,
                widget.drawEnd ?? widget.drawStart,
              ) ??
              _selectedTokenStringGuide(
                widget.analysis,
                widget.selectedTokenIds,
              );
          final preview = Stack(
            fit: StackFit.expand,
            children: [
              FutureBuilder<Uint8List>(
                future: _preview,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(child: Text('Preview unavailable'));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return Image.memory(snapshot.data!, fit: BoxFit.fill);
                },
              ),
              CustomPaint(
                painter: _AnalysisOverlayPainter(
                  analysis: widget.analysis,
                  selectedTokenIds: widget.selectedTokenIds,
                  drawStart: widget.drawStart,
                  drawEnd: widget.drawEnd,
                ),
              ),
              if (guide != null)
                Positioned(
                  left: guide.systemLeft * constraints.maxWidth,
                  width:
                      (guide.systemRight - guide.systemLeft) *
                      constraints.maxWidth,
                  top: guide.normalizedY * constraints.maxHeight - 2,
                  height: 4,
                  child: IgnorePointer(
                    child: Semantics(
                      label: 'Source string ${guide.sourceStringNumber} guide',
                      child: DecoratedBox(
                        key: ValueKey(
                          'analysis-string-guide-${widget.strip.id}',
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              Colors.deepPurpleAccent.withValues(alpha: 0.72),
                              Colors.yellowAccent,
                              Colors.deepPurpleAccent.withValues(alpha: 0.72),
                              Colors.transparent,
                            ],
                            stops: const [0, 0.28, 0.5, 0.72, 1],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              for (final system in widget.analysis.systems)
                for (final token in system.tokens)
                  Positioned(
                    left: token.rect.left * constraints.maxWidth,
                    top: token.rect.top * constraints.maxHeight,
                    width: token.rect.width * constraints.maxWidth,
                    height: token.rect.height * constraints.maxHeight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: widget.drawing
                          ? null
                          : () => widget.onTokenTap(token.id),
                    ),
                  ),
            ],
          );
          final surfaceKey = ValueKey(
            'analysis-draw-surface-${widget.strip.id}',
          );
          if (!widget.drawing) {
            return KeyedSubtree(key: surfaceKey, child: preview);
          }
          final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
          return Listener(
            key: surfaceKey,
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) {
              if (_activeDrawPointer != null) return;
              _activeDrawPointer = event.pointer;
              _drawPointerStart = event.localPosition;
              widget.onDrawStart(normalize(event.localPosition));
            },
            onPointerMove: (event) {
              if (_activeDrawPointer != event.pointer) return;
              widget.onDrawUpdate(normalize(event.localPosition));
            },
            onPointerUp: (event) {
              if (_activeDrawPointer != event.pointer) return;
              final localStart = _drawPointerStart;
              final start = localStart == null ? null : normalize(localStart);
              final end = normalize(event.localPosition);
              _activeDrawPointer = null;
              _drawPointerStart = null;
              if (start == null) {
                widget.onDrawEnd(null);
                return;
              }
              if ((event.localPosition - localStart!).distance < 6) {
                final rect = _missingTokenTapRect(end, canvasSize);
                widget.onDrawUpdate(Offset(rect.right, rect.bottom));
                widget.onDrawEnd(rect);
                return;
              }
              final left = math.min(start.dx, end.dx);
              final top = math.min(start.dy, end.dy);
              final right = math.max(start.dx, end.dx);
              final bottom = math.max(start.dy, end.dy);
              widget.onDrawEnd(
                right > left && bottom > top
                    ? NormalizedRect(left, top, right, bottom)
                    : null,
              );
            },
            onPointerCancel: (event) {
              if (_activeDrawPointer != event.pointer) return;
              _activeDrawPointer = null;
              _drawPointerStart = null;
              widget.onDrawEnd(null);
            },
            // Claim an actual drag so drawing does not scroll the row list.
            // Pointer events above handle both clicks and drags without adding
            // a competing tap recognizer to the row's InkWell.
            child: GestureDetector(onPanStart: (_) {}, child: preview),
          );
        },
      ),
    );
  }
}

_AnalysisStringGuide? _nearestDrawStringGuide(
  VisualTabAnalysis analysis,
  Offset? position,
) {
  if (position == null) return null;
  _AnalysisStringGuide? nearest;
  var nearestDistance = double.infinity;
  for (final system in analysis.systems) {
    for (var index = 0; index < system.stringLines.length; index += 1) {
      final distance = (system.stringLines[index] - position.dy).abs();
      if (distance >= nearestDistance) continue;
      nearestDistance = distance;
      nearest = _AnalysisStringGuide(
        systemLeft: system.rect.left,
        systemRight: system.rect.right,
        normalizedY: system.stringLines[index],
        sourceStringNumber: system.stringLines.length - index,
      );
    }
  }
  return nearest;
}

_AnalysisStringGuide? _selectedTokenStringGuide(
  VisualTabAnalysis analysis,
  Set<String> selectedTokenIds,
) {
  if (selectedTokenIds.length != 1) return null;
  final selectedId = selectedTokenIds.single;
  for (final system in analysis.systems) {
    for (final token in system.tokens) {
      if (token.id != selectedId || token.stringIndex == null) continue;
      final lineIndex = system.stringLines.length - 1 - token.stringIndex!;
      if (lineIndex < 0 || lineIndex >= system.stringLines.length) return null;
      return _AnalysisStringGuide(
        systemLeft: system.rect.left,
        systemRight: system.rect.right,
        normalizedY: system.stringLines[lineIndex],
        sourceStringNumber: token.stringIndex! + 1,
      );
    }
  }
  return null;
}

class _AnalysisStringGuide {
  const _AnalysisStringGuide({
    required this.systemLeft,
    required this.systemRight,
    required this.normalizedY,
    required this.sourceStringNumber,
  });

  final double systemLeft;
  final double systemRight;
  final double normalizedY;
  final int sourceStringNumber;
}

NormalizedRect _missingTokenTapRect(Offset center, Size canvasSize) {
  const halfExtent = 12.0;
  final halfWidth = halfExtent / math.max(1.0, canvasSize.width);
  final halfHeight = halfExtent / math.max(1.0, canvasSize.height);
  return NormalizedRect(
    center.dx - halfWidth,
    center.dy - halfHeight,
    center.dx + halfWidth,
    center.dy + halfHeight,
  ).clamp();
}

class _AnalysisOverlayPainter extends CustomPainter {
  const _AnalysisOverlayPainter({
    required this.analysis,
    required this.selectedTokenIds,
    required this.drawStart,
    required this.drawEnd,
  });

  final VisualTabAnalysis analysis;
  final Set<String> selectedTokenIds;
  final Offset? drawStart;
  final Offset? drawEnd;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.lightBlueAccent.withValues(alpha: 0.72)
      ..strokeWidth = 1.4;
    for (final system in analysis.systems) {
      for (final y in system.stringLines) {
        canvas.drawLine(
          Offset(system.rect.left * size.width, y * size.height),
          Offset(system.rect.right * size.width, y * size.height),
          linePaint,
        );
      }
      final riskGaps = system.connectedNotationRisks
          .map((risk) => risk.gapIndex)
          .toSet();
      for (final gapIndex in riskGaps) {
        if (gapIndex < 0 || gapIndex + 1 >= system.stringLines.length) {
          continue;
        }
        final seamY =
            (system.stringLines[gapIndex] + system.stringLines[gapIndex + 1]) /
            2;
        _drawDashedLine(
          canvas,
          Offset(system.rect.left * size.width, seamY * size.height),
          Offset(system.rect.right * size.width, seamY * size.height),
          Paint()
            ..color = Colors.redAccent.withValues(alpha: 0.48)
            ..strokeWidth = 1.2,
        );
      }
      for (
        var riskIndex = 0;
        riskIndex < system.connectedNotationRisks.length;
        riskIndex += 1
      ) {
        final risk = system.connectedNotationRisks[riskIndex];
        final color = switch (risk.side) {
          VisualConnectedComponentSide.unresolved => Colors.redAccent,
          VisualConnectedComponentSide.upper => Colors.deepPurpleAccent,
          VisualConnectedComponentSide.lower => Colors.amberAccent,
        };
        final sourceRect = Rect.fromLTRB(
          risk.rect.left * size.width,
          risk.rect.top * size.height,
          risk.rect.right * size.width,
          risk.rect.bottom * size.height,
        );
        final rect = sourceRect.inflate(3);
        canvas.drawRect(
          rect,
          Paint()
            ..color = color.withValues(alpha: 0.86)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );
        _drawRiskMarker(
          canvas,
          size,
          rect,
          markerY: system.rect.top * size.height - 13,
          number: riskIndex + 1,
          color: color,
        );
      }
      for (final token in system.tokens) {
        final selected = selectedTokenIds.contains(token.id);
        final color = selected
            ? Colors.yellowAccent
            : switch (token.kind) {
                VisualTabTokenKind.fret => Colors.lightGreenAccent,
                VisualTabTokenKind.deadNote => Colors.cyanAccent,
                VisualTabTokenKind.measureNumber => Colors.orangeAccent,
                VisualTabTokenKind.ambiguous => Colors.redAccent,
              };
        final rect = Rect.fromLTRB(
          token.rect.left * size.width,
          token.rect.top * size.height,
          token.rect.right * size.width,
          token.rect.bottom * size.height,
        );
        canvas.drawRect(
          rect,
          Paint()..color = color.withValues(alpha: token.enabled ? 0.22 : 0.08),
        );
        canvas.drawRect(
          rect,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = selected ? 2.5 : 1.3,
        );
      }
    }
    if (drawStart != null && drawEnd != null) {
      final rect = Rect.fromPoints(
        Offset(drawStart!.dx * size.width, drawStart!.dy * size.height),
        Offset(drawEnd!.dx * size.width, drawEnd!.dy * size.height),
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = Colors.yellowAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AnalysisOverlayPainter oldDelegate) => true;
}

String visualRiskLocationLabel(
  VisualConnectedNotationRisk risk,
  int riskIndex,
) =>
    'Marker ${riskIndex + 1} · between strings ${risk.gapIndex + 1} and ${risk.gapIndex + 2}';

void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
  const dashWidth = 8.0;
  const dashGap = 5.0;
  var x = start.dx;
  while (x < end.dx) {
    canvas.drawLine(
      Offset(x, start.dy),
      Offset(math.min(x + dashWidth, end.dx), end.dy),
      paint,
    );
    x += dashWidth + dashGap;
  }
}

void _drawRiskMarker(
  Canvas canvas,
  Size size,
  Rect riskRect, {
  required double markerY,
  required int number,
  required Color color,
}) {
  const radius = 8.0;
  final center = Offset(
    riskRect.center.dx.clamp(radius, size.width - radius),
    markerY.clamp(radius, size.height - radius),
  );
  canvas.drawLine(
    Offset(center.dx, center.dy + radius),
    Offset(riskRect.center.dx, riskRect.top),
    Paint()
      ..color = color.withValues(alpha: 0.72)
      ..strokeWidth = 1,
  );
  canvas.drawCircle(center, radius, Paint()..color = color);
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5,
  );
  final label = TextPainter(
    text: TextSpan(
      text: '$number',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 9,
        fontWeight: FontWeight.w700,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  label.paint(canvas, center - Offset(label.width / 2, label.height / 2));
}

Uint8List _renderAnalysisPreview(Map<String, Object?> request) {
  final strip = VisualStrip.fromJson(
    (request['strip']! as Map).cast<String, Object?>(),
  );
  return const VisualImageProcessor().process(
    request['bytes']! as Uint8List,
    strip,
    maxWidth: 1800,
  );
}
