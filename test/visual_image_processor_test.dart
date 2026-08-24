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
    expect(output.getPixel(30, 20).a, 255);
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

  test('invert plus high contrast expands a grey tonal range', () {
    final source = img.Image(width: 2, height: 1);
    source.setPixelRgb(0, 0, 90, 90, 90);
    source.setPixelRgb(1, 0, 170, 170, 170);
    const strip = VisualStrip(
      id: 'strip',
      assetHash: 'hash',
      assetExtension: 'png',
      pixelWidth: 2,
      pixelHeight: 1,
      treatment: VisualTreatment.invertedHighContrast,
    );

    final output = img.decodePng(
      const VisualImageProcessor().process(
        Uint8List.fromList(img.encodePng(source)),
        strip,
      ),
    )!;

    final spread = (output.getPixel(0, 0).r - output.getPixel(1, 0).r).abs();
    expect(spread, greaterThan(80));
  });

  test('batch export preserves strip order and precomputes aspect ratios', () {
    final source = img.Image(width: 200, height: 100);
    img.fill(source, color: img.ColorRgb8(255, 255, 255));
    final batches = const VisualImageProcessor().processForExportBatch(
      Uint8List.fromList(img.encodePng(source)),
      const [
        VisualStrip(
          id: 'left',
          assetHash: 'hash',
          assetExtension: 'png',
          pixelWidth: 200,
          pixelHeight: 100,
          crop: NormalizedRect(0, 0, 0.5, 1),
        ),
        VisualStrip(
          id: 'wide',
          assetHash: 'hash',
          assetExtension: 'png',
          pixelWidth: 200,
          pixelHeight: 100,
        ),
      ],
    );

    expect(batches, hasLength(2));
    expect(batches[0].single.aspectRatio, closeTo(1, 0.001));
    expect(batches[1].single.aspectRatio, closeTo(2, 0.001));
    expect(batches[0].single.sourceRect, isNotNull);
    expect(batches[0].single.sourceRect.left, 0);
    expect(batches[0].single.sourceRect.right, 1);
  });

  test(
    'wide rows split into safe horizontal segments for readable density',
    () {
      final source = img.Image(width: 2400, height: 100);
      img.fill(source, color: img.ColorRgb8(255, 255, 255));
      for (var x = 0; x < source.width; x++) {
        for (final y in [30, 40, 50, 60]) {
          source.setPixelRgb(x, y, 80, 80, 80);
        }
      }
      // Dense note-shaped regions make the midpoint less desirable than the
      // surrounding blank measure space.
      img.fillRect(
        source,
        x1: 1170,
        y1: 10,
        x2: 1230,
        y2: 90,
        color: img.ColorRgb8(0, 0, 0),
      );

      final rows = const VisualImageProcessor().processForExportBatch(
        Uint8List.fromList(img.encodePng(source)),
        const [
          VisualStrip(
            id: 'wide',
            assetHash: 'hash',
            assetExtension: 'png',
            pixelWidth: 2400,
            pixelHeight: 100,
          ),
        ],
        maximumRowAspectRatio: 19.2,
      ).single;

      expect(rows, hasLength(2));
      expect(
        rows,
        everyElement(
          predicate<ProcessedExportImage>((row) => row.aspectRatio <= 19.2),
        ),
      );
      expect(rows.first.sourceRect.left, 0);
      expect(rows.last.sourceRect.right, 1);
      expect(rows.first.sourceRect.right, rows.last.sourceRect.left);
    },
  );

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

  test('export batches retain source row coordinates for annotations', () {
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

    final batches = const VisualImageProcessor()
        .processForExportBatch(Uint8List.fromList(img.encodePng(source)), [
          VisualStrip(
            id: 'strip',
            assetHash: 'hash',
            assetExtension: 'png',
            pixelWidth: 400,
            pixelHeight: 500,
          ),
        ]);

    expect(batches.single, hasLength(2));
    expect(batches.single.first.sourceRect.top, lessThan(0.1));
    expect(batches.single.first.sourceRect.bottom, lessThan(0.5));
    expect(batches.single.last.sourceRect.top, greaterThan(0.4));
    expect(batches.single.last.sourceRect.bottom, lessThan(0.8));
  });

  test('density threshold changes only safe detected blank-band splits', () {
    final source = img.Image(width: 600, height: 240);
    img.fill(source, color: img.ColorRgb8(255, 255, 255));
    img.fillRect(
      source,
      x1: 20,
      y1: 25,
      x2: 580,
      y2: 70,
      color: img.ColorRgb8(0, 0, 0),
    );
    img.fillRect(
      source,
      x1: 20,
      y1: 165,
      x2: 580,
      y2: 210,
      color: img.ColorRgb8(0, 0, 0),
    );
    final bytes = Uint8List.fromList(img.encodePng(source));

    final original = const VisualImageProcessor().compactForExport(bytes);
    final stage = const VisualImageProcessor().compactForExport(
      bytes,
      splitDetectedRowsBelowAspectRatio: 3.5,
    );

    expect(original, hasLength(1));
    expect(stage, hasLength(2));
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

  test(
    'row detection separates repeated staff systems without clipping lyrics',
    () {
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
    },
  );

  test('row detection separates subtle staff systems on a noisy dark page', () {
    final source = img.Image(width: 1200, height: 700);
    img.fill(source, color: img.ColorRgb8(28, 28, 30));

    for (final top in [90, 300, 510]) {
      for (var line = 0; line < 4; line += 1) {
        img.fillRect(
          source,
          x1: 45,
          y1: top + line * 10,
          x2: 1150,
          y2: top + line * 10 + 1,
          color: img.ColorRgb8(82, 82, 85),
        );
      }
      for (var word = 0; word < 8; word += 1) {
        img.fillRect(
          source,
          x1: 80 + word * 125,
          y1: top + 58,
          x2: 92 + word * 125,
          y2: top + 62,
          color: img.ColorRgb8(58, 58, 61),
        );
      }
    }

    final rows = const HorizontalRowDetector().detect(
      Uint8List.fromList(img.encodePng(source)),
    );

    expect(rows, hasLength(3));
  });

  test('page-aware proposals exclude title/footer and suggest staff sides', () {
    final source = img.Image(width: 1000, height: 900);
    img.fill(source, color: img.ColorRgb8(250, 250, 250));
    img.fillRect(
      source,
      x1: 250,
      y1: 35,
      x2: 750,
      y2: 55,
      color: img.ColorRgb8(20, 20, 20),
    );
    for (final top in [180, 430, 680]) {
      for (var line = 0; line < 4; line += 1) {
        img.fillRect(
          source,
          x1: 90,
          y1: top + line * 12,
          x2: 910,
          y2: top + line * 12 + 1,
          color: img.ColorRgb8(30, 30, 30),
        );
      }
      img.fillRect(
        source,
        x1: 160,
        y1: top + 65,
        x2: 840,
        y2: top + 70,
        color: img.ColorRgb8(90, 90, 90),
      );
    }
    img.fillRect(
      source,
      x1: 490,
      y1: 865,
      x2: 510,
      y2: 875,
      color: img.ColorRgb8(30, 30, 30),
    );

    final proposal = const HorizontalRowDetector().detectPageAware(
      Uint8List.fromList(img.encodePng(source)),
    );

    expect(proposal.rows, hasLength(3));
    expect(proposal.rows.first.top, greaterThan(0.08));
    expect(proposal.rows.last.bottom, lessThan(0.95));
    expect(proposal.masterLeft, closeTo(0.09, 0.04));
    expect(proposal.masterRight, closeTo(0.91, 0.04));
  });

  test('page-aware side crops stop immediately after outer staff ink', () {
    final source = img.Image(width: 1000, height: 760);
    img.fill(source, color: img.ColorRgb8(250, 250, 250));
    for (final top in [120, 340, 560]) {
      for (var line = 0; line < 4; line += 1) {
        img.fillRect(
          source,
          x1: 100,
          y1: top + line * 12,
          x2: 902,
          y2: top + line * 12 + 1,
          color: img.ColorRgb8(25, 25, 25),
        );
      }
      img.fillRect(
        source,
        x1: 76,
        y1: top,
        x2: 82,
        y2: top + 36,
        color: img.ColorRgb8(25, 25, 25),
      );
      img.fillRect(
        source,
        x1: 900,
        y1: top,
        x2: 902,
        y2: top + 36,
        color: img.ColorRgb8(25, 25, 25),
      );
    }
    // A cross-row sustain can begin just outside the first bar line and below
    // the staff-band scan. It is real notation and must survive the side crop.
    img.drawLine(
      source,
      x1: 68,
      y1: 392,
      x2: 104,
      y2: 398,
      color: img.ColorRgb8(25, 25, 25),
      thickness: 2,
    );

    final proposal = const HorizontalRowDetector().detectPageAware(
      Uint8List.fromList(img.encodePng(source)),
    );

    expect(proposal.rows, hasLength(3));
    expect(
      proposal.masterLeft * source.width,
      inInclusiveRange(64, 67),
      reason:
          'The cross-row sustain must survive with only a two-pixel '
          'anti-aliasing edge.',
    );
    expect(proposal.masterRight * source.width, inInclusiveRange(903, 906));
    expect(
      proposal.rows.every(
        (row) =>
            row.right * source.width >= 903 && row.right * source.width <= 906,
      ),
      isTrue,
      reason: 'The final bar line needs only a minimal anti-aliasing edge.',
    );
  });

  test('page-aware side crops ignore distant page-side labels', () {
    final source = img.Image(width: 1000, height: 760);
    img.fill(source, color: img.ColorRgb8(250, 250, 250));
    for (final top in [120, 340, 560]) {
      for (var line = 0; line < 4; line += 1) {
        img.fillRect(
          source,
          x1: 100,
          y1: top + line * 12,
          x2: 900,
          y2: top + line * 12 + 1,
          color: img.ColorRgb8(25, 25, 25),
        );
      }
      img.fillRect(
        source,
        x1: 8,
        y1: top + 55,
        x2: 35,
        y2: top + 65,
        color: img.ColorRgb8(25, 25, 25),
      );
      img.fillRect(
        source,
        x1: 965,
        y1: top + 55,
        x2: 992,
        y2: top + 65,
        color: img.ColorRgb8(25, 25, 25),
      );
    }

    final proposal = const HorizontalRowDetector().detectPageAware(
      Uint8List.fromList(img.encodePng(source)),
    );

    expect(proposal.rows, hasLength(3));
    expect(proposal.masterLeft * source.width, inInclusiveRange(90, 102));
    expect(proposal.masterRight * source.width, inInclusiveRange(900, 908));
  });

  test('stage density refuses an unprepared portrait page', () {
    final source = img.Image(width: 600, height: 900);
    img.fill(source, color: img.ColorRgb8(250, 250, 250));
    img.fillRect(
      source,
      x1: 120,
      y1: 200,
      x2: 480,
      y2: 240,
      color: img.ColorRgb8(20, 20, 20),
    );

    expect(
      () => const VisualImageProcessor().processForExportBatch(
        Uint8List.fromList(img.encodePng(source)),
        const [
          VisualStrip(
            id: 'portrait',
            assetHash: 'hash',
            assetExtension: 'png',
            pixelWidth: 600,
            pixelHeight: 900,
          ),
        ],
        maximumRowAspectRatio: 14,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Split into rows'),
        ),
      ),
    );
  });

  test('stage density compacts a prepared portrait page into staff rows', () {
    final source = img.Image(width: 1000, height: 900);
    img.fill(source, color: img.ColorRgb8(250, 250, 250));
    for (final top in [180, 430, 680]) {
      for (var line = 0; line < 4; line += 1) {
        img.fillRect(
          source,
          x1: 90,
          y1: top + line * 12,
          x2: 910,
          y2: top + line * 12 + 1,
          color: img.ColorRgb8(30, 30, 30),
        );
      }
      img.fillRect(
        source,
        x1: 160,
        y1: top + 65,
        x2: 840,
        y2: top + 70,
        color: img.ColorRgb8(90, 90, 90),
      );
    }

    final rows = const VisualImageProcessor().processForExportBatch(
      Uint8List.fromList(img.encodePng(source)),
      const [
        VisualStrip(
          id: 'portrait',
          assetHash: 'hash',
          assetExtension: 'png',
          pixelWidth: 1000,
          pixelHeight: 900,
        ),
      ],
      maximumRowAspectRatio: 14,
    ).single;

    expect(rows, hasLength(3));
    expect(
      rows,
      everyElement(
        predicate<ProcessedExportImage>(
          (row) => row.aspectRatio > 4 && row.aspectRatio <= 14,
        ),
      ),
    );
  });

  test('stage density trims horizontal whitespace around a prepared row', () {
    final source = img.Image(width: 1000, height: 140);
    img.fill(source, color: img.ColorRgb8(250, 250, 250));
    for (var line = 0; line < 4; line += 1) {
      img.drawLine(
        source,
        x1: 180,
        y1: 40 + line * 12,
        x2: 760,
        y2: 40 + line * 12,
        color: img.ColorRgb8(20, 20, 20),
      );
    }

    final output = const VisualImageProcessor()
        .processForExportBatch(
          Uint8List.fromList(img.encodePng(source)),
          const [
            VisualStrip(
              id: 'wide-row',
              assetHash: 'hash',
              assetExtension: 'png',
              pixelWidth: 1000,
              pixelHeight: 140,
            ),
          ],
          maximumRowAspectRatio: 100,
        )
        .single
        .single;
    final decoded = img.decodePng(output.bytes)!;

    expect(decoded.width, lessThan(700));
    expect(decoded.width, greaterThan(560));
  });
}
