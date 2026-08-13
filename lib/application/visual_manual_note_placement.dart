import 'dart:math' as math;

import '../domain/visual_chart_models.dart';
import '../domain/visual_tab_transform_models.dart';

enum VisualManualNoteType { normal, sustained, deadNote }

String formatVisualManualNoteValue({
  required VisualManualNoteType type,
  int? fret,
}) {
  if (type == VisualManualNoteType.deadNote) return 'X';
  if (fret == null || fret < 0 || fret > 36) {
    throw const FormatException('Manual frets must be between 0 and 36.');
  }
  return type == VisualManualNoteType.sustained ? '($fret)' : '$fret';
}

class VisualManualNotePlacement {
  const VisualManualNotePlacement({
    required this.systemId,
    required this.stringIndex,
    required this.rect,
  });

  final String systemId;
  final int stringIndex;
  final NormalizedRect rect;
}

class VisualManualNoteGradient {
  const VisualManualNoteGradient({
    required this.left,
    required this.right,
    required this.lineY,
    required this.centerX,
  });

  final double left;
  final double right;
  final double lineY;
  final double centerX;
}

VisualManualNotePlacement? placeVisualManualNote({
  required VisualTabAnalysis analysis,
  required double x,
  required double y,
  required String text,
  int? stringOverride,
}) {
  final system = nearestVisualTabSystem(analysis.systems, x: x, y: y);
  if (system == null || system.stringLines.isEmpty) return null;
  final stringIndex = stringOverride ?? nearestSourceString(system, y);
  if (stringIndex < 0 || stringIndex >= system.stringLines.length) return null;
  final size = standardVisualTokenSize(system, text);
  final lineY = sourceStringLineY(system, stringIndex);
  return VisualManualNotePlacement(
    systemId: system.id,
    stringIndex: stringIndex,
    rect: _centeredClampedRect(
      system.rect,
      centerX: x,
      centerY: lineY,
      width: size.$1,
      height: size.$2,
    ),
  );
}

VisualManualNotePlacement moveVisualManualNote({
  required VisualTabSystem system,
  required VisualTabToken token,
  required double centerX,
  required double centerY,
}) {
  final stringIndex = nearestSourceString(system, centerY);
  return VisualManualNotePlacement(
    systemId: system.id,
    stringIndex: stringIndex,
    rect: _centeredClampedRect(
      system.rect,
      centerX: centerX,
      centerY: sourceStringLineY(system, stringIndex),
      width: token.rect.width,
      height: token.rect.height,
    ),
  );
}

VisualTabSystem? nearestVisualTabSystem(
  List<VisualTabSystem> systems, {
  required double x,
  required double y,
}) {
  VisualTabSystem? nearest;
  var bestDistance = double.infinity;
  for (final system in systems) {
    final dx = x < system.rect.left
        ? system.rect.left - x
        : x > system.rect.right
        ? x - system.rect.right
        : 0.0;
    final dy = y < system.rect.top
        ? system.rect.top - y
        : y > system.rect.bottom
        ? y - system.rect.bottom
        : 0.0;
    final distance = dx * dx + dy * dy;
    if (distance < bestDistance) {
      nearest = system;
      bestDistance = distance;
    }
  }
  return nearest;
}

int nearestSourceString(VisualTabSystem system, double y) {
  var topToBottomIndex = 0;
  var bestDistance = double.infinity;
  for (var index = 0; index < system.stringLines.length; index += 1) {
    final distance = (system.stringLines[index] - y).abs();
    if (distance < bestDistance) {
      topToBottomIndex = index;
      bestDistance = distance;
    }
  }
  return system.stringLines.length - 1 - topToBottomIndex;
}

double sourceStringLineY(VisualTabSystem system, int sourceStringIndex) =>
    system.stringLines[system.stringLines.length - 1 - sourceStringIndex];

(double, double) standardVisualTokenSize(VisualTabSystem system, String text) {
  final neighbours = system.tokens
      .where(
        (token) =>
            token.enabled &&
            token.origin == VisualTabTokenOrigin.detected &&
            token.isFretLike,
      )
      .toList();
  final spacing = _medianSpacing(system.stringLines).clamp(0.008, 0.12);
  final height = neighbours.isEmpty
      ? spacing * 0.82
      : _median(
          neighbours.map((token) => token.rect.height).toList(),
        ).clamp(spacing * 0.55, spacing * 1.35);
  final glyphUnits = _glyphUnits(text);
  final unitWidth = neighbours.isEmpty
      ? spacing * 0.58
      : _median(
          neighbours
              .map((token) => token.rect.width / _glyphUnits(token.text))
              .toList(),
        ).clamp(spacing * 0.28, spacing * 0.95);
  return ((unitWidth * glyphUnits).clamp(0.006, 0.12), height);
}

VisualManualNoteGradient manualNoteGradient(
  VisualTabSystem system,
  VisualTabToken token,
) {
  final centerX = (token.rect.left + token.rect.right) / 2;
  final radius = token.rect.width * 4;
  return VisualManualNoteGradient(
    left: math.max(system.rect.left, centerX - radius),
    right: math.min(system.rect.right, centerX + radius),
    lineY: sourceStringLineY(system, token.stringIndex!),
    centerX: centerX,
  );
}

NormalizedRect _centeredClampedRect(
  NormalizedRect bounds, {
  required double centerX,
  required double centerY,
  required double width,
  required double height,
}) {
  final safeWidth = math.min(width, bounds.width);
  final safeHeight = math.min(height, bounds.height);
  final left = (centerX - safeWidth / 2).clamp(
    bounds.left,
    bounds.right - safeWidth,
  );
  final top = (centerY - safeHeight / 2).clamp(
    bounds.top,
    bounds.bottom - safeHeight,
  );
  return NormalizedRect(left, top, left + safeWidth, top + safeHeight);
}

double _glyphUnits(String text) {
  if (text.startsWith('(') && text.endsWith(')')) {
    return math.max(2.2, text.length * 0.72);
  }
  return math.max(1, text.length).toDouble();
}

double _medianSpacing(List<double> values) {
  if (values.length < 2) return 0.03;
  final sorted = [...values]..sort();
  final gaps = <double>[
    for (var index = 1; index < sorted.length; index += 1)
      sorted[index] - sorted[index - 1],
  ];
  return _median(gaps);
}

double _median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}
