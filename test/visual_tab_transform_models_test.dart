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

    test('accepts multiple unused target strings at the outer edges', () {
      expect(
        () => validateMonotonicVisualRoutes(
          const [
            VisualStringRoute(sourceString: 0, targetString: 1, fretOffset: 0),
            VisualStringRoute(sourceString: 1, targetString: 2, fretOffset: 0),
            VisualStringRoute(sourceString: 2, targetString: 3, fretOffset: 0),
            VisualStringRoute(sourceString: 3, targetString: 4, fretOffset: 0),
          ],
          sourceStringCount: 4,
          targetStringCount: 6,
        ),
        returnsNormally,
      );
    });

    test('routes standard four-string bass into BEADG with unused low B', () {
      const sourceMidis = [40, 45, 50, 55];
      const targetMidis = [35, 40, 45, 50, 55];
      final routes = [
        for (var source = 0; source < sourceMidis.length; source += 1)
          VisualStringRoute(
            sourceString: source,
            targetString: source + 1,
            fretOffset: calculateVisualRouteFretOffset(
              sourceOpenMidi: sourceMidis[source],
              sourceCapo: 0,
              desiredPitchChange: 0,
              targetOpenMidi: targetMidis[source + 1],
              targetCapo: 0,
            ),
          ),
      ];

      final configuration = VisualTabTransformConfiguration(
        sourceLabels: const ['E', 'A', 'D', 'G'],
        sourceOpenMidis: sourceMidis,
        sourceCapo: 0,
        targetLabels: const ['B', 'E', 'A', 'D', 'G'],
        targetOpenMidis: targetMidis,
        targetCapo: 0,
        globalPitchChange: 0,
        routes: routes,
      );

      expect(configuration.unusedTargetStrings, [0]);
      expect(routes.map((route) => route.fretOffset), everyElement(0));
    });

    test('preserves pitch for a non-preset drop-C route with capos', () {
      const sourceMidis = [36, 43, 48, 53]; // C G C F
      const targetMidis = [35, 40, 45, 50, 55]; // B E A D G
      const sourceCapo = 1;
      const targetCapo = 3;
      const pitchChange = 2;
      final routes = [
        for (var source = 0; source < sourceMidis.length; source += 1)
          VisualStringRoute(
            sourceString: source,
            targetString: source,
            fretOffset: calculateVisualRouteFretOffset(
              sourceOpenMidi: sourceMidis[source],
              sourceCapo: sourceCapo,
              desiredPitchChange: pitchChange,
              targetOpenMidi: targetMidis[source],
              targetCapo: targetCapo,
            ),
          ),
      ];

      final configuration = VisualTabTransformConfiguration(
        sourceLabels: const ['C', 'G', 'C', 'F'],
        sourceOpenMidis: sourceMidis,
        sourceCapo: sourceCapo,
        targetLabels: const ['B', 'E', 'A', 'D', 'G'],
        targetOpenMidis: targetMidis,
        targetCapo: targetCapo,
        globalPitchChange: pitchChange,
        routes: routes,
      );

      expect(configuration.unusedTargetStrings, [4]);
      for (final sourceFret in [0, 5, 12, 19]) {
        for (final route in routes) {
          final sourcePitch =
              sourceMidis[route.sourceString] +
              sourceCapo +
              sourceFret +
              configuration.pitchChangeForSourceString(route.sourceString);
          final targetPitch =
              targetMidis[route.targetString] +
              targetCapo +
              sourceFret +
              route.effectiveOffset;
          expect(targetPitch, sourcePitch);
        }
      }
    });

    test(
      'applies a selected-string pitch change without moving other strings',
      () {
        const openMidis = [40, 45, 50, 55];
        final routes = [
          for (var source = 0; source < openMidis.length; source += 1)
            VisualStringRoute(
              sourceString: source,
              targetString: source,
              fretOffset: calculateVisualRouteFretOffset(
                sourceOpenMidi: openMidis[source],
                sourceCapo: 0,
                desiredPitchChange: source == 0 ? 3 : 0,
                targetOpenMidi: openMidis[source],
                targetCapo: 0,
              ),
            ),
        ];
        final configuration = VisualTabTransformConfiguration(
          sourceLabels: const ['E', 'A', 'D', 'G'],
          sourceOpenMidis: openMidis,
          sourceCapo: 0,
          targetLabels: const ['E', 'A', 'D', 'G'],
          targetOpenMidis: openMidis,
          targetCapo: 0,
          globalPitchChange: 0,
          selectedStringPitchChanges: const {0: 3},
          routes: routes,
        );

        expect(configuration.pitchChangeForSourceString(0), 3);
        expect(configuration.pitchChangeForSourceString(1), 0);
        expect(routes.map((route) => route.fretOffset), [3, 0, 0, 0]);
      },
    );

    test('rejects a target with fewer strings than the source', () {
      expect(
        () => validateMonotonicVisualRoutes(
          const [
            VisualStringRoute(sourceString: 0, targetString: 0, fretOffset: 0),
            VisualStringRoute(sourceString: 1, targetString: 1, fretOffset: 0),
            VisualStringRoute(sourceString: 2, targetString: 2, fretOffset: 0),
          ],
          sourceStringCount: 4,
          targetStringCount: 3,
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
    expect(restored.keepUnchanged, isFalse);
    expect(restored.systems.single.stringLines, [0.3, 0.4, 0.5, 0.6]);
    expect(
      restored.systems.single.connectedNotationRisks.single.side,
      VisualConnectedComponentSide.upper,
    );
  });

  test('analysis round-trips an explicit keep-unchanged review decision', () {
    const analysis = VisualTabAnalysis(
      stripId: 'blank-row',
      sourceType: VisualTabSourceType.rasterOcr,
      keepUnchanged: true,
    );

    final restored = VisualTabAnalysis.fromJson(analysis.toJson());
    expect(restored.keepUnchanged, isTrue);
    expect(restored.isReviewed, isTrue);
    expect(restored.isSourceUsable, isFalse);
  });
}
