import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';
import 'package:music_tabbler/domain/visual_tab_transform_models.dart';

void main() {
  group('visual route fret offset', () {
    test('Motion Sickness low D routes to B at +3', () {
      expect(
        calculateVisualRouteFretOffset(
          sourceOpenMidi: 38,
          sourceCapo: 0,
          desiredPitchChange: 0,
          targetOpenMidi: 35,
          targetCapo: 0,
        ),
        3,
      );
    });

    test('Rock With You routes keep frets with pitch -2 and capo 2', () {
      expect(
        calculateVisualRouteFretOffset(
          sourceOpenMidi: 39,
          sourceCapo: 0,
          desiredPitchChange: -2,
          targetOpenMidi: 35,
          targetCapo: 2,
        ),
        0,
      );
    });
  });

  group('visual routes', () {
    test(
      'accept ordered four-to-five route with an internal unused string',
      () {
        expect(
          () => validateMonotonicVisualRoutes(
            const [
              VisualStringRoute(
                sourceString: 0,
                targetString: 0,
                fretOffset: 3,
              ),
              VisualStringRoute(
                sourceString: 1,
                targetString: 2,
                fretOffset: 0,
              ),
              VisualStringRoute(
                sourceString: 2,
                targetString: 3,
                fretOffset: 0,
              ),
              VisualStringRoute(
                sourceString: 3,
                targetString: 4,
                fretOffset: 0,
              ),
            ],
            sourceStringCount: 4,
            targetStringCount: 5,
          ),
          returnsNormally,
        );
      },
    );

    test('reject crossing routes', () {
      expect(
        () => validateMonotonicVisualRoutes(
          const [
            VisualStringRoute(sourceString: 0, targetString: 1, fretOffset: 0),
            VisualStringRoute(sourceString: 1, targetString: 0, fretOffset: 0),
          ],
          sourceStringCount: 2,
          targetStringCount: 2,
        ),
        throwsFormatException,
      );
    });
  });

  test('analysis round-trips reviewed tokens', () {
    const analysis = VisualTabAnalysis(
      stripId: 'strip-1',
      sourceType: VisualTabSourceType.positionedPdf,
      warnings: ['Review one ambiguous token.'],
      systems: [
        VisualTabSystem(
          id: 'system-1',
          rect: NormalizedRect(0.1, 0.2, 0.9, 0.7),
          stringLines: [0.3, 0.4, 0.5, 0.6],
          connectedNotationRisks: [
            VisualConnectedNotationRisk(
              id: 'risk-1',
              rect: NormalizedRect(0.45, 0.43, 0.48, 0.47),
              gapIndex: 1,
              side: VisualConnectedComponentSide.upper,
            ),
          ],
          tokens: [
            VisualTabToken(
              id: 'token-1',
              text: '(12)',
              rect: NormalizedRect(0.2, 0.35, 0.24, 0.39),
              kind: VisualTabTokenKind.fret,
              stringIndex: 2,
              confidence: 0.85,
              enabled: false,
            ),
          ],
        ),
      ],
    );

    final restored = VisualTabAnalysis.fromJson(analysis.toJson());
    expect(restored.sourceType, VisualTabSourceType.positionedPdf);
    expect(restored.systems.single.tokens.single.text, '(12)');
    expect(restored.systems.single.tokens.single.enabled, isFalse);
    expect(restored.systems.single.stringLines, [0.3, 0.4, 0.5, 0.6]);
    expect(
      restored.systems.single.connectedNotationRisks.single.side,
      VisualConnectedComponentSide.upper,
    );
  });
}
