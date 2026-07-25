import 'dart:math' as math;

import 'package:flutter/material.dart';

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

  static const double height = 390;
  static const double horizontalMargin = 32;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, height);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final hit = _nearestNote(details.localPosition, size);
            if (hit != null) onNoteSelected(hit.id);
          },
          child: CustomPaint(
            size: size,
            painter: _TabChartPainter(
              chart: chart,
              showTitle: showTitle,
              showTab: showTab,
              showNotation: showNotation,
              selectedNoteId: selectedNoteId,
              leadVocalContrast: leadVocalContrast,
              foreground: colors.onSurface,
              muted: colors.onSurfaceVariant,
              backing: colors.tertiary,
              selection: colors.primaryContainer,
              surface: colors.surface,
            ),
          ),
        );
      },
    );
  }

  TabNote? _nearestNote(Offset tap, Size size) {
    TabNote? best;
    var bestDistance = 28.0;
    for (
      var measureIndex = 0;
      measureIndex < chart.measures.length;
      measureIndex++
    ) {
      for (final note in chart.measures[measureIndex].notes) {
        final position = _notePosition(
          size,
          chart,
          measureIndex,
          note,
          showNotation,
        );
        final distance = (position - tap).distance;
        if (distance < bestDistance) {
          best = note;
          bestDistance = distance;
        }
      }
    }
    return best;
  }
}

Offset _notePosition(
  Size size,
  SongChart chart,
  int measureIndex,
  TabNote note,
  bool showNotation,
) {
  final usableWidth = size.width - TabChartView.horizontalMargin * 2;
  final measureWidth = usableWidth / chart.measures.length;
  final measure = chart.measures[measureIndex];
  final x =
      TabChartView.horizontalMargin +
      measureIndex * measureWidth +
      (note.beat + 0.5) / measure.beats * measureWidth;
  final tabTop = showNotation ? 185.0 : 118.0;
  return Offset(x, tabTop + note.stringIndex * 22);
}

class _TabChartPainter extends CustomPainter {
  _TabChartPainter({
    required this.chart,
    required this.showTitle,
    required this.showTab,
    required this.showNotation,
    required this.selectedNoteId,
    required this.leadVocalContrast,
    required this.foreground,
    required this.muted,
    required this.backing,
    required this.selection,
    required this.surface,
  });

  final SongChart chart;
  final bool showTitle;
  final bool showTab;
  final bool showNotation;
  final String? selectedNoteId;
  final double leadVocalContrast;
  final Color foreground;
  final Color muted;
  final Color backing;
  final Color selection;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = surface);
    if (showTitle) {
      _text(
        canvas,
        '${chart.title}  •  ${chart.artist}',
        const Offset(18, 14),
        foreground,
        15,
        FontWeight.w700,
      );
    }
    _text(canvas, 'Intro', const Offset(32, 56), muted, 13, FontWeight.w600);
    _text(
      canvas,
      chart.tuning.name,
      Offset(size.width - 160, 56),
      muted,
      12,
      FontWeight.w500,
    );

    if (showNotation) _paintNotation(canvas, size);
    if (showTab) _paintTab(canvas, size);
    if (!showNotation && !showTab) {
      _text(
        canvas,
        'Enable tablature, standard notation, or both.',
        Offset(size.width / 2 - 145, 180),
        muted,
        14,
        FontWeight.w500,
      );
    }
  }

  void _paintNotation(Canvas canvas, Size size) {
    const top = 92.0;
    final paint = Paint()
      ..color = muted
      ..strokeWidth = 1;
    for (var line = 0; line < 5; line++) {
      final y = top + line * 10;
      canvas.drawLine(
        const Offset(32, 0) + Offset(0, y),
        Offset(size.width - 32, y),
        paint,
      );
    }

    for (
      var measureIndex = 0;
      measureIndex < chart.measures.length;
      measureIndex++
    ) {
      for (final note in chart.measures[measureIndex].notes) {
        final tabPosition = _notePosition(
          size,
          chart,
          measureIndex,
          note,
          showNotation,
        );
        final midi = note.midiPitch(chart.tuning, capo: chart.capo);
        final y = 135 - (midi - 28) * 2.1;
        final center = Offset(tabPosition.dx, y.clamp(82, 144));
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(-0.28);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: 12, height: 8),
          Paint()..color = foreground,
        );
        canvas.restore();
        canvas.drawLine(
          center + const Offset(5, 0),
          center + const Offset(5, -24),
          Paint()
            ..color = foreground
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  void _paintTab(Canvas canvas, Size size) {
    final tabTop = showNotation ? 185.0 : 118.0;
    const lineGap = 22.0;
    final usableWidth = size.width - TabChartView.horizontalMargin * 2;
    final measureWidth = usableWidth / chart.measures.length;
    final linePaint = Paint()
      ..color = muted.withValues(alpha: 0.72)
      ..strokeWidth = 1;

    for (
      var stringIndex = 0;
      stringIndex < chart.tuning.strings.length;
      stringIndex++
    ) {
      final y = tabTop + stringIndex * lineGap;
      _text(
        canvas,
        chart.tuning.strings[stringIndex].name,
        Offset(10, y - 8),
        muted,
        12,
        FontWeight.w600,
      );
      canvas.drawLine(
        Offset(TabChartView.horizontalMargin, y),
        Offset(size.width - TabChartView.horizontalMargin, y),
        linePaint,
      );
    }

    for (var index = 0; index <= chart.measures.length; index++) {
      final x = TabChartView.horizontalMargin + index * measureWidth;
      canvas.drawLine(
        Offset(x, tabTop),
        Offset(x, tabTop + lineGap * (chart.tuning.strings.length - 1)),
        linePaint
          ..strokeWidth = index == 0 || index == chart.measures.length ? 2 : 1,
      );
      if (index < chart.measures.length) {
        _text(
          canvas,
          chart.measures[index].number.toString(),
          Offset(x + 5, tabTop - 24),
          muted,
          11,
          FontWeight.w500,
        );
      }
    }

    for (
      var measureIndex = 0;
      measureIndex < chart.measures.length;
      measureIndex++
    ) {
      for (final note in chart.measures[measureIndex].notes) {
        final center = _notePosition(
          size,
          chart,
          measureIndex,
          note,
          showNotation,
        );
        final isSelected = note.id == selectedNoteId;
        final text = note.fret.toString();
        final textWidth = math.max(17.0, text.length * 9.0);
        final clearRect = Rect.fromCenter(
          center: center,
          width: textWidth,
          height: 18,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(clearRect, const Radius.circular(4)),
          Paint()..color = isSelected ? selection : surface,
        );
        _text(
          canvas,
          text,
          center - Offset(textWidth / 2 - 4, 9),
          foreground,
          13,
          FontWeight.w700,
        );
        _paintRhythm(canvas, center, note.value);
      }
    }

    final lyricsTop = tabTop + lineGap * chart.tuning.strings.length + 32;
    for (final lyric in chart.lyrics) {
      final measure = chart.measures[lyric.measureIndex];
      final x =
          TabChartView.horizontalMargin +
          lyric.measureIndex * measureWidth +
          (lyric.beat + 0.5) / measure.beats * measureWidth;
      final color = lyric.isBackingVocal
          ? backing
          : foreground.withValues(alpha: leadVocalContrast);
      _text(
        canvas,
        lyric.text,
        Offset(x - lyric.text.length * 3.6, lyricsTop),
        color,
        lyric.isBackingVocal ? 15 : 13,
        lyric.isBackingVocal ? FontWeight.w800 : FontWeight.w500,
      );
    }
  }

  void _paintRhythm(Canvas canvas, Offset center, NoteValue value) {
    final stemTop = center.dy + 14;
    final stemBottom = center.dy + 34;
    final paint = Paint()
      ..color = muted
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(center.dx, stemTop),
      Offset(center.dx, stemBottom),
      paint,
    );
    final beamWidth = switch (value) {
      NoteValue.whole => 0.0,
      NoteValue.half => 6.0,
      NoteValue.quarter => 10.0,
      NoteValue.eighth => 17.0,
      NoteValue.sixteenth => 22.0,
    };
    if (beamWidth > 0) {
      canvas.drawLine(
        Offset(center.dx, stemBottom),
        Offset(center.dx + beamWidth, stemBottom),
        paint,
      );
    }
  }

  void _text(
    Canvas canvas,
    String value,
    Offset offset,
    Color color,
    double size,
    FontWeight weight,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(color: color, fontSize: size, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _TabChartPainter oldDelegate) {
    return oldDelegate.chart != chart ||
        oldDelegate.showTitle != showTitle ||
        oldDelegate.showTab != showTab ||
        oldDelegate.showNotation != showNotation ||
        oldDelegate.selectedNoteId != selectedNoteId ||
        oldDelegate.leadVocalContrast != leadVocalContrast ||
        oldDelegate.foreground != foreground ||
        oldDelegate.surface != surface;
  }
}
