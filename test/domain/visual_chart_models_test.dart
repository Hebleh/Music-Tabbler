import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';

void main() {
  test('split master crop controls survive strip persistence', () {
    const strip = VisualStrip(
      id: 'split-row',
      assetHash: 'asset',
      assetExtension: 'png',
      pixelWidth: 1200,
      pixelHeight: 800,
      splitMasterLeft: 0.12,
      splitMasterRight: 0.91,
    );

    final restored = VisualStrip.fromJson(strip.toJson());
    expect(restored.splitMasterLeft, 0.12);
    expect(restored.splitMasterRight, 0.91);

    final legacy = strip.toJson()
      ..remove('splitMasterLeft')
      ..remove('splitMasterRight');
    final migrated = VisualStrip.fromJson(legacy);
    expect(migrated.splitMasterLeft, isNull);
    expect(migrated.splitMasterRight, isNull);
  });

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
            annotations: [
              VisualAnnotationStroke(
                id: 'stroke_1',
                points: [
                  NormalizedPoint(0.25, 0.3),
                  NormalizedPoint(0.75, 0.7),
                ],
                colorArgb: 0xFF00FF00,
                width: 0.006,
              ),
            ],
            annotationsVisible: false,
            includeAnnotationsInPdf: true,
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
      expect(decoded.strips.single.annotations.single.id, 'stroke_1');
      expect(decoded.strips.single.annotations.single.points.last.x, 0.75);
      expect(decoded.strips.single.annotations.single.points.last.pressure, 1);
      expect(decoded.strips.single.annotations.single.colorArgb, 0xFF00FF00);
      expect(decoded.strips.single.annotations.single.width, 0.006);
      expect(decoded.strips.single.annotationsVisible, isFalse);
      expect(decoded.strips.single.includeAnnotationsInPdf, isTrue);
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
    final json =
        VisualChartDraft(
            id: 'legacy',
            title: 'Legacy',
            artist: '',
            createdAt: now,
            updatedAt: now,
          ).toJson()
          ..['schemaVersion'] = 1
          ..remove('exportDensity')
          ..remove('visualTabTransform');

    expect(
      VisualChartDraft.fromJson(json).exportDensity,
      VisualExportDensity.original,
    );
  });

  test('visual transform record preserves immutable base strips and audit', () {
    final now = DateTime.utc(2026, 7, 28);
    final draft = VisualChartDraft(
      id: 'transformed',
      title: 'Song',
      artist: '',
      createdAt: now,
      updatedAt: now,
      strips: const [
        VisualStrip(
          id: 'output',
          assetHash: 'output-hash',
          assetExtension: 'png',
          pixelWidth: 200,
          pixelHeight: 50,
        ),
      ],
      visualTabTransform: VisualTabTransformRecord(
        id: 'transform',
        appliedAt: now,
        baseStrips: const [
          VisualStrip(
            id: 'base',
            assetHash: 'base-hash',
            assetExtension: 'png',
            pixelWidth: 200,
            pixelHeight: 40,
          ),
        ],
        configuration: const {
          'sourceLabels': ['E', 'A', 'D', 'G'],
        },
        analyses: const [
          {'stripId': 'base'},
        ],
        audit: const ['Applied +1.'],
      ),
    );

    final restored = VisualChartDraft.decode(draft.encode());

    expect(restored.visualTabTransform!.baseStrips.single.id, 'base');
    expect(restored.visualTabTransform!.audit.single, 'Applied +1.');
    expect(restored.allReferencedStrips.map((strip) => strip.id), [
      'output',
      'base',
    ]);
  });

  test('schema-v1 strips without annotations retain safe defaults', () {
    final strip =
        const VisualStrip(
            id: 'legacy-strip',
            assetHash: 'hash',
            assetExtension: 'png',
            pixelWidth: 100,
            pixelHeight: 50,
          ).toJson()
          ..remove('annotations')
          ..remove('annotationsVisible')
          ..remove('includeAnnotationsInPdf');

    final restored = VisualStrip.fromJson(strip);

    expect(restored.annotations, isEmpty);
    expect(restored.annotationsVisible, isTrue);
    expect(restored.includeAnnotationsInPdf, isFalse);
  });

  test(
    'legacy annotation points default pressure and new pressure persists',
    () {
      final legacy = NormalizedPoint.fromJson({'x': 0.25, 'y': 0.75});
      final pressured = NormalizedPoint.fromJson({
        'x': 0.5,
        'y': 0.5,
        'pressure': 0.4,
      });

      expect(legacy.pressure, 1);
      expect(pressured.pressure, 0.4);
      expect(pressured.toJson()['pressure'], 0.4);
    },
  );

  test('local provenance persists and URL intake is normalized offline', () {
    final now = DateTime.utc(2026, 7, 24);
    final url = normalizeSourceUrl(
      ' HTTPS://WWW.SONGSTERR.COM/a/wsa/test-tab-s123 ',
    );
    final draft = VisualChartDraft(
      id: 'source',
      title: 'Song',
      artist: 'Artist',
      createdAt: now,
      updatedAt: now,
      provenance: SourceProvenance(
        url: url,
        provider: inferSourceProvider(url),
        versionName: 'Bass tab',
        importMethod: ProvenanceImportMethod.screenshot,
        notes: 'Manually captured',
      ),
    );

    final restored = VisualChartDraft.decode(draft.encode()).provenance!;

    expect(url, 'https://www.songsterr.com/a/wsa/test-tab-s123');
    expect(restored.provider, 'Songsterr');
    expect(restored.versionName, 'Bass tab');
    expect(restored.notes, 'Manually captured');
    expect(
      () => normalizeSourceUrl('file:///private/chart.pdf'),
      throwsFormatException,
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
