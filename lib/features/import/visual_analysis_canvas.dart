import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../application/library_contracts.dart';
import '../../application/visual_analysis_review_session.dart';
import '../../application/visual_manual_note_placement.dart';
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
    required this.addingNote,
    required this.onTokenTap,
    required this.onAddNote,
    required this.onManualDragStart,
    required this.onManualDragUpdate,
    required this.onManualDragEnd,
    required this.onManualDragCancel,
  });

  final ChartLibrary library;
  final VisualStrip strip;
  final VisualTabAnalysis analysis;
  final Set<String> selectedTokenIds;
  final bool addingNote;
  final ValueChanged<String> onTokenTap;
  final ValueChanged<Offset> onAddNote;
  final ValueChanged<String> onManualDragStart;
  final void Function(String id, Offset normalizedDelta) onManualDragUpdate;
  final ValueChanged<String> onManualDragEnd;
  final ValueChanged<String> onManualDragCancel;

  @override
  State<VisualAnalysisCanvas> createState() => VisualAnalysisCanvasState();
}

class VisualAnalysisCanvasState extends State<VisualAnalysisCanvas> {
  late Future<Uint8List> _preview;
  Offset? _hoverPosition;
  String? _draggingTokenId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant VisualAnalysisCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.strip.id != widget.strip.id) _load();
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
      child: FutureBuilder<Uint8List>(
        future: _preview,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Preview unavailable'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              Offset normalize(Offset local) => Offset(
                (local.dx / constraints.maxWidth).clamp(0.0, 1.0),
                (local.dy / constraints.maxHeight).clamp(0.0, 1.0),
              );
              return MouseRegion(
                cursor: widget.addingNote
                    ? SystemMouseCursors.precise
                    : MouseCursor.defer,
                onHover: widget.addingNote
                    ? (event) => setState(
                        () => _hoverPosition = normalize(event.localPosition),
                      )
                    : null,
                onExit: (_) => setState(() => _hoverPosition = null),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: widget.addingNote
                      ? (details) =>
                            widget.onAddNote(normalize(details.localPosition))
                      : null,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(snapshot.data!, fit: BoxFit.fill),
                      VisualAnalysisOverlay(
                        analysis: widget.analysis,
                        selectedTokenIds: widget.selectedTokenIds,
                        provisionalPlacement:
                            widget.addingNote && _hoverPosition != null
                            ? placeVisualManualNote(
                                analysis: widget.analysis,
                                x: _hoverPosition!.dx,
                                y: _hoverPosition!.dy,
                                text: '0',
                              )
                            : null,
                        draggingTokenId: _draggingTokenId,
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
                              onTap: widget.addingNote
                                  ? null
                                  : () => widget.onTokenTap(token.id),
                              onPanStart:
                                  !widget.addingNote &&
                                      token.origin ==
                                          VisualTabTokenOrigin.manual
                                  ? (_) {
                                      setState(
                                        () => _draggingTokenId = token.id,
                                      );
                                      widget.onManualDragStart(token.id);
                                    }
                                  : null,
                              onPanUpdate:
                                  !widget.addingNote &&
                                      token.origin ==
                                          VisualTabTokenOrigin.manual
                                  ? (details) => widget.onManualDragUpdate(
                                      token.id,
                                      Offset(
                                        details.delta.dx / constraints.maxWidth,
                                        details.delta.dy /
                                            constraints.maxHeight,
                                      ),
                                    )
                                  : null,
                              onPanEnd:
                                  !widget.addingNote &&
                                      token.origin ==
                                          VisualTabTokenOrigin.manual
                                  ? (_) {
                                      setState(() => _draggingTokenId = null);
                                      widget.onManualDragEnd(token.id);
                                    }
                                  : null,
                              onPanCancel:
                                  !widget.addingNote &&
                                      token.origin ==
                                          VisualTabTokenOrigin.manual
                                  ? () {
                                      setState(() => _draggingTokenId = null);
                                      widget.onManualDragCancel(token.id);
                                    }
                                  : null,
                            ),
                          ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class VisualAnalysisOverlay extends StatelessWidget {
  const VisualAnalysisOverlay({
    super.key,
    required this.analysis,
    this.selectedTokenIds = const {},
    this.provisionalPlacement,
    this.draggingTokenId,
  });

  final VisualTabAnalysis analysis;
  final Set<String> selectedTokenIds;
  final VisualManualNotePlacement? provisionalPlacement;
  final String? draggingTokenId;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _AnalysisOverlayPainter(
        analysis: analysis,
        selectedTokenIds: selectedTokenIds,
        provisionalPlacement: provisionalPlacement,
        draggingTokenId: draggingTokenId,
      ),
    );
  }
}

class _AnalysisOverlayPainter extends CustomPainter {
  const _AnalysisOverlayPainter({
    required this.analysis,
    required this.selectedTokenIds,
    required this.provisionalPlacement,
    required this.draggingTokenId,
  });

  final VisualTabAnalysis analysis;
  final Set<String> selectedTokenIds;
  final VisualManualNotePlacement? provisionalPlacement;
  final String? draggingTokenId;

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
        final active = selected || draggingTokenId == token.id;
        if (token.origin == VisualTabTokenOrigin.manual &&
            token.stringIndex != null) {
          _drawManualGradient(
            canvas,
            size,
            manualNoteGradient(system, token),
            active: active,
          );
        }
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
        if (token.origin == VisualTabTokenOrigin.manual) {
          _drawManualTokenText(canvas, rect, token.text, color);
        }
      }
    }
    final provisional = provisionalPlacement;
    if (provisional != null) {
      final system = analysis.systems.firstWhere(
        (candidate) => candidate.id == provisional.systemId,
      );
      final token = VisualTabToken(
        id: 'provisional',
        text: '0',
        rect: provisional.rect,
        kind: VisualTabTokenKind.fret,
        stringIndex: provisional.stringIndex,
        origin: VisualTabTokenOrigin.manual,
      );
      _drawManualGradient(
        canvas,
        size,
        manualNoteGradient(system, token),
        active: true,
      );
      final rect = Rect.fromLTRB(
        token.rect.left * size.width,
        token.rect.top * size.height,
        token.rect.right * size.width,
        token.rect.bottom * size.height,
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

void _drawManualGradient(
  Canvas canvas,
  Size size,
  VisualManualNoteGradient gradient, {
  required bool active,
}) {
  final left = gradient.left * size.width;
  final right = gradient.right * size.width;
  final center = gradient.centerX * size.width;
  final y = gradient.lineY * size.height;
  final alpha = active ? 0.42 : 0.18;
  final paint = Paint()
    ..shader = LinearGradient(
      colors: [
        Colors.transparent,
        Colors.lightBlueAccent.withValues(alpha: alpha),
        Colors.transparent,
      ],
      stops: [
        0,
        ((center - left) / math.max(1, right - left)).clamp(0.0, 1.0),
        1,
      ],
    ).createShader(Rect.fromLTRB(left, y - 4, right, y + 4));
  canvas.drawRect(Rect.fromLTRB(left, y - 4, right, y + 4), paint);
}

void _drawManualTokenText(Canvas canvas, Rect rect, String text, Color accent) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: Colors.white,
        backgroundColor: Colors.black.withValues(alpha: 0.72),
        fontSize: math.max(8, rect.height * 0.82),
        fontWeight: FontWeight.w700,
      ),
    ),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: math.max(1, rect.width));
  painter.paint(
    canvas,
    Offset(
      rect.center.dx - painter.width / 2,
      rect.center.dy - painter.height / 2,
    ),
  );
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
