import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../domain/visual_chart_models.dart';
import 'performance_deck.dart';
import 'visual_tab_analysis_service.dart';

/// Creates a live-Gig-only deck whose visual rows are cropped into bars.
///
/// The source deck, saved strips, PDF layout, and preview layout are not
/// changed. Uncertain rows remain whole rather than being destructively split.
PerformanceDeck repackGigDeckIntoBars(PerformanceDeck deck) {
  return deck.copyWith(
    pages: [
      for (final page in deck.pages)
        PerformanceDeckPage(
          id: page.id,
          index: page.index,
          elements: [
            for (final element in page.elements)
              ..._splitElementIntoBars(element),
          ],
        ),
    ],
  );
}

Map<String, Object?> repackGigDeckMessage(Map<String, Object?> message) =>
    repackGigDeckIntoBars(PerformanceDeck.fromMessage(message)).toMessage();

List<PerformanceDeckElement> _splitElementIntoBars(
  PerformanceDeckElement element,
) {
  final bytes = element.imageBytes;
  if (element.kind != PerformanceElementKind.strip ||
      bytes == null ||
      bytes.isEmpty) {
    return [element];
  }
  final source = img.decodeImage(bytes);
  if (source == null || source.width < 80 || source.height < 24) {
    return [element];
  }
  final image = img.bakeOrientation(source);
  final geometry = _bestSingleSystemGeometry(bytes);
  if (geometry == null) return [element];
  final detectedBoundaries = _cleanBarBoundaries(
    geometry.barLines,
    minimumGap: 0.025,
  );
  // Row detection intentionally crops immediately outside the opening and
  // closing bar lines. Treat those detected outer lines as the crop endpoints
  // and keep only the lines between them as split points. Without canonical
  // endpoints, an edge-aligned three-bar row retained only its two internal
  // lines and was incorrectly left whole in Gig mode.
  if (detectedBoundaries.length < 3) return [element];
  final boundaries = [
    0.0,
    ...detectedBoundaries.sublist(1, detectedBoundaries.length - 1),
    1.0,
  ];
  if (boundaries.length < 3) return [element];

  final segments = <NormalizedRect>[];
  for (var index = 0; index < boundaries.length - 1; index += 1) {
    final left = boundaries[index];
    final right = boundaries[index + 1];
    if (right - left < 0.055) continue;
    segments.add(NormalizedRect(left, 0, right, 1));
  }
  if (segments.length < 2) return [element];

  return [
    for (final segment in segments) _cropElement(element, image, segment),
  ];
}

VisualTabSystemGeometry? _bestSingleSystemGeometry(Uint8List bytes) {
  final geometry = detectVisualTabGeometryAnyStringCount(
    bytes,
    crop: const NormalizedRect.full(),
  );
  if (geometry.systems.length != 1) return null;
  final candidate = geometry.systems.single;
  return candidate.barLines.length >= 3 ? candidate : null;
}

List<double> _cleanBarBoundaries(
  List<double> values, {
  required double minimumGap,
}) {
  final sorted = values.where((value) => value >= 0 && value <= 1).toList()
    ..sort();
  final cleaned = <double>[];
  for (final value in sorted) {
    if (cleaned.isEmpty || value - cleaned.last >= minimumGap) {
      cleaned.add(value);
    } else {
      cleaned[cleaned.length - 1] = (cleaned.last + value) / 2;
    }
  }
  return cleaned;
}

PerformanceDeckElement _cropElement(
  PerformanceDeckElement element,
  img.Image image,
  NormalizedRect segment,
) {
  final sourceLeft = (segment.left * image.width).floor();
  final sourceRight = (segment.right * image.width).ceil();
  final cropLeft = math.max(0, sourceLeft);
  final cropRight = math.min(image.width, sourceRight);
  final cropped = img.copyCrop(
    image,
    x: cropLeft,
    y: 0,
    width: cropRight - cropLeft,
    height: image.height,
  );
  final actualLeft = cropLeft / image.width;
  final actualRight = cropRight / image.width;
  final actualWidth = actualRight - actualLeft;
  final sourceRow = element.sourceRowRect ?? const NormalizedRect.full();
  final barSourceRow = NormalizedRect(
    sourceRow.left + actualLeft * sourceRow.width,
    sourceRow.top,
    sourceRow.left + actualRight * sourceRow.width,
    sourceRow.bottom,
  ).clamp();

  return PerformanceDeckElement(
    kind: element.kind,
    entryIndex: element.entryIndex,
    entryId: element.entryId,
    chartVariantId: element.chartVariantId,
    sourceStripId: element.sourceStripId,
    sourceRowRect: barSourceRow,
    title: element.title,
    artist: element.artist,
    rowIndex: element.rowIndex,
    width: cropped.width.toDouble(),
    height: cropped.height.toDouble(),
    imageBytes: Uint8List.fromList(img.encodePng(cropped, level: 3)),
    annotations: _annotationsForSegment(
      element.annotations,
      left: actualLeft,
      right: actualRight,
      widthScale: 1 / actualWidth,
    ),
    annotationsVisible: element.annotationsVisible,
    includeAnnotationsInPdf: element.includeAnnotationsInPdf,
  );
}

List<VisualAnnotationStroke> _annotationsForSegment(
  List<VisualAnnotationStroke> annotations, {
  required double left,
  required double right,
  required double widthScale,
}) {
  final result = <VisualAnnotationStroke>[];
  for (final stroke in annotations) {
    final points = [
      for (final point in stroke.points)
        if (point.x >= left && point.x <= right)
          NormalizedPoint(
            (point.x - left) * widthScale,
            point.y,
            pressure: point.pressure,
          ).clamp(),
    ];
    if (points.length < 2) continue;
    result.add(
      VisualAnnotationStroke(
        id: stroke.id,
        points: List.unmodifiable(points),
        colorArgb: stroke.colorArgb,
        width: stroke.width,
      ),
    );
  }
  return List.unmodifiable(result);
}
