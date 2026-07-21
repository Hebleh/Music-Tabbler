import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:music_tabbler/application/horizontal_row_detector.dart';
import 'package:music_tabbler/application/visual_image_processor.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';

void main() {
  test(
    'processor applies normalized crop without changing the stored source',
    () {
      final source = img.Image(width: 100, height: 50);
      img.fill(source, color: img.ColorRgb8(255, 255, 255));
      final originalBytes = Uint8List.fromList(img.encodePng(source));
      const strip = VisualStrip(
        id: 'strip',
        assetHash: 'hash',
        assetExtension: 'png',
        pixelWidth: 100,
        pixelHeight: 50,
        crop: NormalizedRect(0.25, 0, 0.75, 1),
      );

      final output = const VisualImageProcessor().process(originalBytes, strip);
      final decoded = img.decodePng(output)!;

      expect(decoded.width, 50);
      expect(decoded.height, 50);
      expect(img.decodePng(originalBytes)!.width, 100);
    },
  );

  test('backing-vocal highlight changes only the requested region', () {
    final source = img.Image(width: 100, height: 40);
    img.fill(source, color: img.ColorRgb8(255, 255, 255));
    final bytes = Uint8List.fromList(img.encodePng(source));
    const strip = VisualStrip(
      id: 'strip',
      assetHash: 'hash',
      assetExtension: 'png',
      pixelWidth: 100,
      pixelHeight: 40,
      highlights: [
        VisualHighlight(
          id: 'highlight',
          rect: NormalizedRect(0.2, 0.25, 0.4, 0.75),
        ),
      ],
    );

    final output = img.decodePng(
      const VisualImageProcessor().process(bytes, strip),
    )!;

    expect(output.getPixel(5, 5).g, 255);
    expect(output.getPixel(30, 20).b, lessThan(255));
  });

  test('preview processing bounds width after cropping', () {
    final source = img.Image(width: 2400, height: 1200);
    img.fill(source, color: img.ColorRgb8(255, 255, 255));
    final bytes = Uint8List.fromList(img.encodePng(source));
    const strip = VisualStrip(
      id: 'strip',
      assetHash: 'hash',
      assetExtension: 'png',
      pixelWidth: 2400,
      pixelHeight: 1200,
      crop: NormalizedRect(0, 0.25, 1, 0.75),
    );

    final output = img.decodePng(
      const VisualImageProcessor().process(bytes, strip, maxWidth: 600),
    )!;

    expect(output.width, 600);
    expect(output.height, 150);
  });

  test('export compaction splits a tall image only across a blank band', () {
    final source = img.Image(width: 400, height: 500);
    img.fill(source, color: img.ColorRgb8(255, 255, 255));
    img.fillRect(
      source,
      x1: 20,
      y1: 40,
      x2: 380,
      y2: 110,
      color: img.ColorRgb8(0, 0, 0),
    );
    img.fillRect(
      source,
      x1: 20,
      y1: 270,
      x2: 380,
      y2: 340,
      color: img.ColorRgb8(0, 0, 0),
    );

    final segments = const VisualImageProcessor().compactForExport(
      Uint8List.fromList(img.encodePng(source)),
    );

    expect(segments, hasLength(2));
    expect(
      segments.map((bytes) => img.decodePng(bytes)!.height),
      everyElement(lessThan(250)),
    );
  });

  test('row detection keeps faint lyrics inside their notation row', () {
    final source = img.Image(width: 800, height: 600);
    img.fill(source, color: img.ColorRgb8(20, 20, 20));
    img.fillRect(
      source,
      x1: 20,
      y1: 50,
      x2: 780,
      y2: 100,
      color: img.ColorRgb8(150, 150, 150),
    );
    img.fillRect(
      source,
      x1: 150,
      y1: 106,
      x2: 300,
      y2: 111,
      color: img.ColorRgb8(29, 29, 29),
    );
    img.fillRect(
      source,
      x1: 20,
      y1: 230,
      x2: 780,
      y2: 285,
      color: img.ColorRgb8(150, 150, 150),
    );

    final rows = const HorizontalRowDetector().detect(
      Uint8List.fromList(img.encodePng(source)),
    );

    expect(rows, hasLength(2));
    expect(rows.first.bottom * source.height, greaterThan(111));
    expect(rows.last.top * source.height, lessThan(230));
  });

  test('row detection does not split notation groups across a narrow gap', () {
    final source = img.Image(width: 600, height: 500);
    img.fill(source, color: img.ColorRgb8(245, 245, 245));
    img.fillRect(
      source,
      x1: 10,
      y1: 60,
      x2: 590,
      y2: 90,
      color: img.ColorRgb8(30, 30, 30),
    );
    img.fillRect(
      source,
      x1: 10,
      y1: 108,
      x2: 590,
      y2: 130,
      color: img.ColorRgb8(30, 30, 30),
    );
    img.fillRect(
      source,
      x1: 10,
      y1: 260,
      x2: 590,
      y2: 300,
      color: img.ColorRgb8(30, 30, 30),
    );

    final rows = const HorizontalRowDetector().detect(
      Uint8List.fromList(img.encodePng(source)),
    );

    expect(rows, hasLength(2));
    expect(rows.first.bottom * source.height, greaterThan(130));
  });

  test('row detection separates repeated staff systems without clipping lyrics', () {
    final source = img.Image(width: 1000, height: 720);
    img.fill(source, color: img.ColorRgb8(250, 250, 250));

    for (final top in [70, 280, 490]) {
      for (var line = 0; line < 4; line++) {
        img.fillRect(
          source,
          x1: 40,
          y1: top + line * 12,
          x2: 960,
          y2: top + line * 12 + 1,
          color: img.ColorRgb8(45, 45, 45),
        );
      }
      img.fillRect(
        source,
        x1: 180,
        y1: top + 62,
        x2: 820,
        y2: top + 67,
        color: img.ColorRgb8(150, 150, 150),
      );
    }

    final rows = const HorizontalRowDetector().detect(
      Uint8List.fromList(img.encodePng(source)),
    );

    expect(rows, hasLength(3));
    expect(rows[0].bottom * source.height, greaterThan(137));
    expect(rows[1].top * source.height, lessThan(280));
    expect(rows[1].bottom * source.height, greaterThan(347));
    expect(rows[2].top * source.height, lessThan(490));
  });
}
