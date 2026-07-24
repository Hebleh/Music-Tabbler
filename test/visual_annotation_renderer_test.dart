import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:music_tabbler/application/visual_annotation_renderer.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';

void main() {
  final source = img.Image(width: 100, height: 50)
    ..clear(img.ColorRgb8(255, 255, 255));
  final sourceBytes = Uint8List.fromList(img.encodePng(source));
  const strokes = [
    VisualAnnotationStroke(
      id: 'stroke',
      points: [NormalizedPoint(0.1, 0.5), NormalizedPoint(0.9, 0.5)],
      colorArgb: 0xFFFF0000,
      width: 0.04,
    ),
  ];

  test('annotations are not flattened unless PDF inclusion is enabled', () {
    final excluded = flattenVisualAnnotations(
      sourceBytes,
      strokes,
      include: false,
    );

    expect(identical(excluded, sourceBytes), isTrue);
    expect(img.decodePng(excluded)!.getPixel(50, 25).r, 255);
    expect(img.decodePng(excluded)!.getPixel(50, 25).g, 255);
  });

  test(
    'enabled annotation flattening changes output without changing source',
    () {
      final included = flattenVisualAnnotations(
        sourceBytes,
        strokes,
        include: true,
      );
      final rendered = img.decodePng(included)!;
      final original = img.decodePng(sourceBytes)!;

      expect(rendered.getPixel(50, 25).r, 255);
      expect(rendered.getPixel(50, 25).g, lessThan(50));
      expect(original.getPixel(50, 25).g, 255);
    },
  );
}
