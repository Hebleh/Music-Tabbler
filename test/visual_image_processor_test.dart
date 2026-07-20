import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
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
}
