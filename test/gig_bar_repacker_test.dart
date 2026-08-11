import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:music_tabbler/application/gig_bar_repacker.dart';
import 'package:music_tabbler/application/performance_deck.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';

void main() {
  test('repackages a live row into bars without changing the source deck', () {
    final bytes = _threeBarRow();
    final sourceElement = PerformanceDeckElement(
      kind: PerformanceElementKind.strip,
      entryIndex: 0,
      entryId: 'song',
      chartVariantId: 'variant',
      sourceStripId: 'strip',
      sourceRowRect: const NormalizedRect(0, 0.2, 1, 0.4),
      rowIndex: 0,
      width: 600,
      height: 120,
      imageBytes: bytes,
      annotations: const [
        VisualAnnotationStroke(
          id: 'stroke',
          points: [NormalizedPoint(0.08, 0.5), NormalizedPoint(0.18, 0.5)],
        ),
      ],
    );
    final source = PerformanceDeck(
      setlistId: 'set',
      setlistName: 'Gig',
      density: VisualExportDensity.stageReadable,
      pageWidth: 840,
      pageHeight: 595,
      margin: 5,
      gap: 4,
      pages: [
        PerformanceDeckPage(id: 'page', index: 0, elements: [sourceElement]),
      ],
    );

    final live = repackGigDeckIntoBars(source);
    final bars = live.pages.single.elements;

    expect(source.pages.single.elements, hasLength(1));
    expect(bars, hasLength(3));
    expect(bars.every((bar) => bar.sourceStripId == 'strip'), isTrue);
    expect(bars.first.sourceRowRect!.left, 0);
    expect(bars.last.sourceRowRect!.right, 1);
    expect(
      bars.fold<double>(0, (total, bar) => total + bar.width),
      600,
      reason: 'Bar crops should tile the original row without overlap gaps.',
    );
    for (var index = 1; index < bars.length; index += 1) {
      expect(
        bars[index - 1].sourceRowRect!.right,
        closeTo(bars[index].sourceRowRect!.left, 1 / 600),
      );
    }
    expect(bars.first.annotations, hasLength(1));
    expect(bars.skip(1).every((bar) => bar.annotations.isEmpty), isTrue);
  });

  test('keeps uncertain image rows whole', () {
    final blank = img.Image(width: 300, height: 80);
    img.fill(blank, color: img.ColorRgb8(255, 255, 255));
    final element = PerformanceDeckElement(
      kind: PerformanceElementKind.strip,
      entryIndex: 0,
      entryId: 'song',
      width: 300,
      height: 80,
      imageBytes: Uint8List.fromList(img.encodePng(blank)),
    );
    final source = PerformanceDeck(
      setlistId: 'set',
      setlistName: 'Gig',
      density: VisualExportDensity.stageReadable,
      pageWidth: 840,
      pageHeight: 595,
      margin: 5,
      gap: 4,
      pages: [
        PerformanceDeckPage(id: 'page', index: 0, elements: [element]),
      ],
    );

    expect(repackGigDeckIntoBars(source).pages.single.elements, [element]);
  });

  test('splits rows whose opening and closing bars touch the crop edges', () {
    final bytes = _threeBarRow(edgeAligned: true);
    final element = PerformanceDeckElement(
      kind: PerformanceElementKind.strip,
      entryIndex: 0,
      entryId: 'song',
      width: 600,
      height: 120,
      imageBytes: bytes,
    );
    final source = PerformanceDeck(
      setlistId: 'set',
      setlistName: 'Gig',
      density: VisualExportDensity.stageReadable,
      pageWidth: 840,
      pageHeight: 595,
      margin: 5,
      gap: 4,
      pages: [
        PerformanceDeckPage(id: 'page', index: 0, elements: [element]),
      ],
    );

    expect(repackGigDeckIntoBars(source).pages.single.elements, hasLength(3));
  });
}

Uint8List _threeBarRow({bool edgeAligned = false}) {
  final image = img.Image(width: 600, height: 120);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  for (var line = 0; line < 4; line += 1) {
    final y = 36 + line * 12;
    img.drawLine(
      image,
      x1: 20,
      y1: y,
      x2: 580,
      y2: y,
      color: img.ColorRgb8(0, 0, 0),
    );
  }
  for (final x in [
    if (edgeAligned) 1 else 20,
    210,
    400,
    if (edgeAligned) 598 else 580,
  ]) {
    img.drawLine(
      image,
      x1: x,
      y1: 36,
      x2: x,
      y2: 72,
      color: img.ColorRgb8(0, 0, 0),
    );
  }
  return Uint8List.fromList(img.encodePng(image));
}
