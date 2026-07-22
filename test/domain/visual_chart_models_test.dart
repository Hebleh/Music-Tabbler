import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';

void main() {
  test(
    'visual chart JSON preserves nondestructive crop and lyric overlays',
    () {
      final now = DateTime.utc(2026, 7, 20);
      final draft = VisualChartDraft(
        id: 'chart_1',
        title: 'Stage Song',
        artist: 'Band',
        createdAt: now,
        updatedAt: now,
        globalTreatment: VisualTreatment.invert,
        strips: const [
          VisualStrip(
            id: 'strip_1',
            assetHash: 'abc',
            assetExtension: 'png',
            pixelWidth: 1000,
            pixelHeight: 300,
            sourceAssetHash: 'original',
            crop: NormalizedRect(0.1, 0.2, 0.9, 0.8),
            lyricBand: NormalizedRect(0.1, 0.6, 0.9, 0.8),
            lyricContrast: 1.5,
            highlights: [
              VisualHighlight(
                id: 'highlight_1',
                rect: NormalizedRect(0.2, 0.62, 0.4, 0.76),
              ),
            ],
          ),
        ],
      );

      final decoded = VisualChartDraft.decode(draft.encode());

      expect(decoded.title, 'Stage Song');
      expect(decoded.globalTreatment, VisualTreatment.invert);
      expect(decoded.exportDensity, VisualExportDensity.original);
      expect(decoded.strips.single.crop.left, 0.1);
      expect(decoded.strips.single.lyricContrast, 1.5);
      expect(decoded.strips.single.highlights.single.id, 'highlight_1');
    },
  );

  test('visual chart JSON preserves a selected export density', () {
    final now = DateTime.utc(2026, 7, 22);
    final draft = VisualChartDraft(
      id: 'chart',
      title: 'Song',
      artist: '',
      createdAt: now,
      updatedAt: now,
      exportDensity: VisualExportDensity.stageReadable,
    );

    expect(
      VisualChartDraft.decode(draft.encode()).exportDensity,
      VisualExportDensity.stageReadable,
    );
  });

  test('schema-v1 drafts without export density retain MVP behavior', () {
    final now = DateTime.utc(2026, 7, 20);
    final json = VisualChartDraft(
      id: 'legacy',
      title: 'Legacy',
      artist: '',
      createdAt: now,
      updatedAt: now,
    ).toJson()..remove('exportDensity');

    expect(
      VisualChartDraft.fromJson(json).exportDensity,
      VisualExportDensity.original,
    );
  });

  test(
    'whole-tab treatment can be cleared without changing strip treatment',
    () {
      final now = DateTime.utc(2026, 7, 20);
      final draft = VisualChartDraft(
        id: 'chart',
        title: 'Song',
        artist: '',
        createdAt: now,
        updatedAt: now,
        globalTreatment: VisualTreatment.grayscale,
        strips: const [
          VisualStrip(
            id: 'strip',
            assetHash: 'hash',
            assetExtension: 'png',
            pixelWidth: 100,
            pixelHeight: 50,
            treatment: VisualTreatment.highContrast,
          ),
        ],
      );

      final cleared = draft.copyWith(clearGlobalTreatment: true);

      expect(cleared.globalTreatment, isNull);
      expect(cleared.strips.single.treatment, VisualTreatment.highContrast);
    },
  );
}
