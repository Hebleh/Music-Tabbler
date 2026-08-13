import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:music_tabbler/application/visual_deskew.dart';
import 'package:music_tabbler/application/visual_image_processor.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';

void main() {
  test('deskew is backward compatible and clamps saved angles', () {
    const original = VisualStrip(
      id: 'strip',
      assetHash: 'hash',
      assetExtension: 'png',
      pixelWidth: 200,
      pixelHeight: 100,
    );
    final legacy = original.toJson()..remove('deskewDegrees');

    expect(VisualStrip.fromJson(legacy).deskewDegrees, 0);
    expect(
      reprojectVisualStripDeskew(original, 20).deskewDegrees,
      maximumDeskewDegrees,
    );
    expect(
      reprojectVisualStripDeskew(original, -20).deskewDegrees,
      -maximumDeskewDegrees,
    );
  });

  test('deskew round trip keeps crop and overlay geometry aligned', () {
    const original = VisualStrip(
      id: 'strip',
      assetHash: 'hash',
      assetExtension: 'png',
      pixelWidth: 1000,
      pixelHeight: 500,
      crop: NormalizedRect(0.1, 0.2, 0.9, 0.8),
      lyricBand: NormalizedRect(0.2, 0.6, 0.8, 0.75),
      highlights: [
        VisualHighlight(
          id: 'highlight',
          rect: NormalizedRect(0.3, 0.55, 0.4, 0.7),
        ),
      ],
      annotations: [
        VisualAnnotationStroke(
          id: 'stroke',
          points: [NormalizedPoint(0.25, 0.25), NormalizedPoint(0.75, 0.75)],
        ),
      ],
    );

    final rotated = reprojectVisualStripDeskew(original, 3.5);
    final reopened = VisualStrip.fromJson(rotated.toJson());
    expect(reopened.deskewDegrees, 3.5);
    expect(reopened.deskewBaseGeometry, isNotNull);
    final restored = reprojectVisualStripDeskew(reopened, 0);

    _expectRectClose(restored.crop, original.crop, 0.002);
    _expectRectClose(restored.lyricBand!, original.lyricBand!, 0.002);
    _expectRectClose(
      restored.highlights.single.rect,
      original.highlights.single.rect,
      0.002,
    );
    for (var index = 0; index < 2; index += 1) {
      expect(
        restored.annotations.single.points[index].x,
        closeTo(original.annotations.single.points[index].x, 0.003),
      );
      expect(
        restored.annotations.single.points[index].y,
        closeTo(original.annotations.single.points[index].y, 0.003),
      );
    }
  });

  test('image processor rotates before applying the normalized crop', () {
    final source = img.Image(width: 100, height: 50);
    img.fill(source, color: img.ColorRgb8(255, 255, 255));
    img.drawLine(
      source,
      x1: 10,
      y1: 25,
      x2: 90,
      y2: 25,
      color: img.ColorRgb8(0, 0, 0),
      thickness: 2,
    );
    const base = VisualStrip(
      id: 'strip',
      assetHash: 'hash',
      assetExtension: 'png',
      pixelWidth: 100,
      pixelHeight: 50,
      crop: NormalizedRect(0.05, 0.1, 0.95, 0.9),
    );
    final strip = reprojectVisualStripDeskew(base, 5);

    final output = img.decodePng(
      const VisualImageProcessor().process(
        Uint8List.fromList(img.encodePng(source)),
        strip,
      ),
    )!;

    expect(output.width, greaterThan(90));
    expect(output.height, greaterThan(35));
    expect(output.any((pixel) => pixel.r < 80), isTrue);
  });
}

void _expectRectClose(
  NormalizedRect actual,
  NormalizedRect expected,
  double tolerance,
) {
  expect(actual.left, closeTo(expected.left, tolerance));
  expect(actual.top, closeTo(expected.top, tolerance));
  expect(actual.right, closeTo(expected.right, tolerance));
  expect(actual.bottom, closeTo(expected.bottom, tolerance));
}
