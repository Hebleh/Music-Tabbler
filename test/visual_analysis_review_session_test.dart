import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/application/visual_analysis_review_session.dart';
import 'package:music_tabbler/application/visual_tab_analysis_service.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';
import 'package:music_tabbler/domain/visual_tab_transform_models.dart';

void main() {
  test('review session coordinates completion, failure, and retry', () async {
    final analyzer = _Analyzer();
    final session = VisualAnalysisReviewSession(
      analyzer: analyzer,
      strips: const [
        VisualStrip(
          id: 'good',
          assetHash: 'a',
          assetExtension: 'png',
          pixelWidth: 100,
          pixelHeight: 20,
        ),
        VisualStrip(
          id: 'retry',
          assetHash: 'b',
          assetExtension: 'png',
          pixelWidth: 100,
          pixelHeight: 20,
        ),
      ],
      sourceStringCount: 4,
    );

    await session.analyzeIndex(0);
    await session.analyzeIndex(1);

    expect(session.processed, 1);
    expect(session.processingComplete, isFalse);
    expect(session.rowStates[1], VisualAnalysisRowState.failed);
    expect(session.rowErrors[1], isA<StateError>());

    await session.analyzeIndex(1, preferPositionedPdf: false);

    expect(session.processed, 2);
    expect(session.processingComplete, isTrue);
    expect(session.blockedRows, isEmpty);
    expect(analyzer.preferences, [true, true, false]);
  });
}

class _Analyzer implements VisualTabAnalyzer {
  final List<bool> preferences = [];
  var failedOnce = false;

  @override
  Future<VisualTabAnalysis> analyze(
    VisualStrip strip, {
    required int sourceStringCount,
    bool preferPositionedPdf = true,
  }) async {
    preferences.add(preferPositionedPdf);
    if (strip.id == 'retry' && !failedOnce) {
      failedOnce = true;
      throw StateError('retry me');
    }
    return VisualTabAnalysis(
      stripId: strip.id,
      sourceType: VisualTabSourceType.rasterOcr,
      systems: const [
        VisualTabSystem(
          id: 'system',
          rect: NormalizedRect(0, 0, 1, 1),
          stringLines: [0.2, 0.4, 0.6, 0.8],
          tokens: [
            VisualTabToken(
              id: 'token',
              text: '3',
              rect: NormalizedRect(0.4, 0.5, 0.45, 0.6),
              kind: VisualTabTokenKind.fret,
              stringIndex: 2,
            ),
          ],
        ),
      ],
    );
  }
}
