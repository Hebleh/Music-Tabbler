import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/application/highlight_geometry.dart';
import 'package:music_tabbler/application/text_recognition_service.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';
import 'package:music_tabbler/features/import/visual_strip_preview.dart';

void main() {
  test('crop-local highlight coordinates round-trip to the source asset', () {
    const crop = NormalizedRect(0.1, 0.25, 0.9, 0.75);
    const local = NormalizedRect(0.2, 0.3, 0.4, 0.6);

    final asset = cropLocalRectToAsset(local, crop);
    final roundTrip = assetRectToCropLocal(asset, crop)!;

    expect(roundTrip.left, closeTo(local.left, 0.000001));
    expect(roundTrip.top, closeTo(local.top, 0.000001));
    expect(roundTrip.right, closeTo(local.right, 0.000001));
    expect(roundTrip.bottom, closeTo(local.bottom, 0.000001));
  });

  test('different crops of one asset use different OCR cache entries', () {
    const first = VisualStrip(
      id: 'first',
      assetHash: 'shared',
      assetExtension: 'png',
      pixelWidth: 1000,
      pixelHeight: 800,
      crop: NormalizedRect(0, 0, 1, 0.4),
    );
    const second = VisualStrip(
      id: 'second',
      assetHash: 'shared',
      assetExtension: 'png',
      pixelWidth: 1000,
      pixelHeight: 800,
      crop: NormalizedRect(0, 0.4, 1, 0.8),
    );

    expect(
      textRecognitionCacheKey(first),
      isNot(textRecognitionCacheKey(second)),
    );
    expect(textRecognitionCacheKey(first), textRecognitionCacheKey(first));
  });

  test('preview height is deterministic before and after image loading', () {
    expect(visualStripPreviewHeight(1200, 12), 100);
    expect(visualStripPreviewHeight(1200, 20), 90);
    expect(visualStripPreviewHeight(1200, 2), 320);
  });
}
