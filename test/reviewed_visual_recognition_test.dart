import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/application/reviewed_visual_recognition.dart';
import 'package:music_tabbler/application/semantic_recognition_service.dart';
import 'package:music_tabbler/domain/music_models.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';
import 'package:music_tabbler/domain/visual_tab_transform_models.dart';

void main() {
  test('reviewed visual bars become separate semantic measures', () {
    final inputs = reviewedVisualRecognitionInputs(
      record: _record(
        barLines: const [0, 0.25, 0.5, 0.75, 1],
        tokens: const [
          VisualTabToken(
            id: 'first',
            text: '3',
            rect: NormalizedRect(0.10, 0.30, 0.12, 0.34),
            kind: VisualTabTokenKind.fret,
            stringIndex: 0,
          ),
          VisualTabToken(
            id: 'second',
            text: '5',
            rect: NormalizedRect(0.40, 0.45, 0.42, 0.49),
            kind: VisualTabTokenKind.fret,
            stringIndex: 1,
          ),
          VisualTabToken(
            id: 'third',
            text: '7',
            rect: NormalizedRect(0.60, 0.60, 0.62, 0.64),
            kind: VisualTabTokenKind.fret,
            stringIndex: 2,
          ),
          VisualTabToken(
            id: 'fourth',
            text: '9',
            rect: NormalizedRect(0.90, 0.75, 0.92, 0.79),
            kind: VisualTabTokenKind.fret,
            stringIndex: 3,
          ),
        ],
      ),
      tuning: BassTuning.beadg,
    );

    expect(inputs, isNotNull);
    expect(inputs, hasLength(4));
    final result = const SemanticRecognitionService().propose(
      chartId: 'split',
      title: 'Split',
      artist: '',
      strips: inputs!,
      tuning: BassTuning.beadg,
    );
    expect(result.chart.measures, hasLength(4));
    expect(result.chart.measures.map((measure) => measure.notes.single.fret), [
      3,
      5,
      7,
      12,
    ]);
    for (final measure in result.chart.measures) {
      expect(measure.notes.single.position.value, inInclusiveRange(0.0, 4.0));
    }
  });

  test('reviewed visual recognition preserves routing and source geometry', () {
    final inputs = reviewedVisualRecognitionInputs(
      record: _record(
        barLines: const [0.1, 0.6, 0.9],
        tokens: const [
          VisualTabToken(
            id: 'routed',
            text: '(0)',
            rect: NormalizedRect(0.20, 0.70, 0.24, 0.74),
            kind: VisualTabTokenKind.fret,
            stringIndex: 3,
          ),
          VisualTabToken(
            id: 'dead',
            text: 'X',
            rect: NormalizedRect(0.70, 0.30, 0.73, 0.34),
            kind: VisualTabTokenKind.deadNote,
            stringIndex: 0,
          ),
        ],
        crop: const NormalizedRect(0.1, 0.2, 0.9, 0.8),
      ),
      tuning: BassTuning.beadg,
    );

    expect(inputs, hasLength(4));
    final candidates = inputs!
        .expand((input) => input.reviewedFretCandidates!)
        .toList();
    expect(candidates, hasLength(2));
    expect(candidates.first.fret, 3);
    expect(candidates.first.stringIndex, 4);
    expect(candidates.first.sourceRect.left, closeTo(0.26, 0.001));
    expect(candidates.last.deadNote, isTrue);
    expect(candidates.last.stringIndex, 1);
  });
}

VisualTabTransformRecord _record({
  required List<double> barLines,
  required List<VisualTabToken> tokens,
  NormalizedRect crop = const NormalizedRect.full(),
}) {
  final strip = VisualStrip(
    id: 'row',
    assetHash: 'asset',
    assetExtension: 'png',
    pixelWidth: 1000,
    pixelHeight: 200,
    crop: crop,
  );
  final analysis = VisualTabAnalysis(
    stripId: strip.id,
    sourceType: VisualTabSourceType.positionedPdf,
    systems: [
      VisualTabSystem(
        id: 'system',
        rect: const NormalizedRect.full(),
        stringLines: const [0.3, 0.4, 0.5, 0.6],
        barLines: barLines,
        tokens: tokens,
      ),
    ],
  );
  final configuration = VisualTabTransformConfiguration(
    sourceLabels: ['E', 'A', 'D', 'G'],
    sourceOpenMidis: const [28, 33, 38, 43],
    sourceCapo: 0,
    targetLabels: ['B', 'E', 'A', 'D', 'G'],
    targetOpenMidis: const [23, 28, 33, 38, 43],
    targetCapo: 0,
    globalPitchChange: 0,
    routes: [
      VisualStringRoute(sourceString: 0, targetString: 1, fretOffset: 0),
      VisualStringRoute(sourceString: 1, targetString: 2, fretOffset: 0),
      VisualStringRoute(sourceString: 2, targetString: 3, fretOffset: 0),
      VisualStringRoute(sourceString: 3, targetString: 4, fretOffset: 3),
    ],
  );
  return VisualTabTransformRecord(
    id: 'transform',
    appliedAt: DateTime.utc(2026),
    baseStrips: [strip],
    configuration: configuration.toJson(),
    analyses: [analysis.toJson()],
  );
}
