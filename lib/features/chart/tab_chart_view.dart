import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../application/semantic_layout.dart';
import '../../domain/music_models.dart';

class TabChartView extends StatelessWidget {
  const TabChartView({
    super.key,
    required this.chart,
    required this.showTitle,
    required this.showTab,
    required this.showNotation,
    required this.selectedNoteId,
    required this.leadVocalContrast,
    required this.onNoteSelected,
  });

  final SongChart chart;
  final bool showTitle;
  final bool showTab;
  final bool showNotation;
  final String? selectedNoteId;
  final double leadVocalContrast;
  final ValueChanged<String> onNoteSelected;

  static const _engine = SemanticLayoutEngine();

  @override
  Widget build(BuildContext context) {
    final plan = _engine.build(
      chart,
      showTitle: showTitle,
      showTab: showTab,
      showNotation: showNotation,
    );
    final colors = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: plan.width / plan.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = constraints.maxWidth / plan.width;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              final point = details.localPosition / scale;
              SemanticNoteTarget? best;
              var bestDistance = 28.0;
              for (final target in plan.noteTargets) {
                final distance = (Offset(target.x, target.y) - point).distance;
                if (distance < bestDistance) {
                  best = target;
                  bestDistance = distance;
                }
              }
              if (best != null) onNoteSelected(best.noteId);
            },
            child: CustomPaint(
              painter: _SemanticPlanPainter(
                plan: plan,
                selectedNoteId: selectedNoteId,
                foreground: colors.onSurface,
                muted: colors.onSurfaceVariant,
                backing: colors.tertiary,
                selection: colors.primaryContainer,
                surface: colors.surface,
                leadVocalContrast: leadVocalContrast,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SemanticPlanPainter extends CustomPainter {
  const _SemanticPlanPainter({
    required this.plan,
    required this.selectedNoteId,
    required this.foreground,
    required this.muted,
    required this.backing,
    required this.selection,
    required this.surface,
    required this.leadVocalContrast,
  });

  final SemanticLayoutPlan plan;
  final String? selectedNoteId;
  final Color foreground;
  final Color muted;
  final Color backing;
  final Color selection;
  final Color surface;
  final double leadVocalContrast;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / plan.width, size.height / plan.height);
    canvas
      ..drawRect(Offset.zero & size, Paint()..color = surface)
      ..save()
      ..scale(scale);
    final selected = selectedNoteId;
    if (selected != null) {
      for (final target in plan.noteTargets.where(
        (target) => target.noteId == selected,
      )) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(target.x, target.y),
              width: 22,
              height: 18,
            ),
            const Radius.circular(4),
          ),
          Paint()..color = selection,
        );
      }
    }
    for (final primitive in plan.primitives) {
      switch (primitive) {
        case SemanticLinePrimitive():
          canvas.drawLine(
            Offset(primitive.x1, primitive.y1),
            Offset(primitive.x2, primitive.y2),
            Paint()
              ..color = primitive.role == SemanticLineRole.rhythm
                  ? foreground
                  : muted.withValues(alpha: 0.72)
              ..strokeWidth = primitive.width,
          );
        case SemanticEllipsePrimitive():
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(primitive.x, primitive.y),
              width: primitive.width,
              height: primitive.height,
            ),
            Paint()..color = foreground,
          );
        case SemanticTextPrimitive():
          _paintText(canvas, primitive);
      }
    }
    canvas.restore();
  }

  void _paintText(Canvas canvas, SemanticTextPrimitive primitive) {
    final color = switch (primitive.role) {
      SemanticTextRole.backingLyric => backing,
      SemanticTextRole.lyric => foreground.withValues(alpha: leadVocalContrast),
      SemanticTextRole.metadata ||
      SemanticTextRole.measureNumber ||
      SemanticTextRole.technique => muted,
      _ => foreground,
    };
    final weight = switch (primitive.role) {
      SemanticTextRole.title ||
      SemanticTextRole.fret ||
      SemanticTextRole.backingLyric ||
      SemanticTextRole.section => FontWeight.w700,
      _ => FontWeight.w500,
    };
    final painter = TextPainter(
      text: TextSpan(
        text: primitive.text,
        style: TextStyle(
          color: color,
          fontSize: primitive.size,
          fontWeight: weight,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    painter.paint(canvas, Offset(primitive.x, primitive.y));
  }

  @override
  bool shouldRepaint(covariant _SemanticPlanPainter oldDelegate) =>
      oldDelegate.plan != plan ||
      oldDelegate.selectedNoteId != selectedNoteId ||
      oldDelegate.foreground != foreground ||
      oldDelegate.muted != muted ||
      oldDelegate.backing != backing ||
      oldDelegate.selection != selection ||
      oldDelegate.surface != surface ||
      oldDelegate.leadVocalContrast != leadVocalContrast;
}
