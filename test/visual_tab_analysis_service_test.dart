import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:music_tabbler/application/service_contracts.dart';
import 'package:music_tabbler/application/visual_tab_analysis_service.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';
import 'package:music_tabbler/domain/visual_tab_transform_models.dart';

void main() {
  group('raster geometry', () {
    test('detects two light-background four-string systems and bar lines', () {
      final bytes = _tabFixture(
        background: img.ColorRgb8(245, 245, 245),
        foreground: img.ColorRgb8(20, 20, 20),
      );

      final geometry = detectVisualTabGeometry(
        bytes,
        crop: const NormalizedRect.full(),
        expectedStringCount: 4,
      );

      expect(geometry.systems, hasLength(2));
      expect(geometry.systems.first.stringLines, hasLength(4));
      expect(geometry.systems.first.barLines.length, greaterThanOrEqualTo(2));
      expect(geometry.systems.first.confidence, greaterThan(0.9));
    });

    test('detects inverted screenshot geometry', () {
      final bytes = _tabFixture(
        background: img.ColorRgb8(25, 25, 25),
        foreground: img.ColorRgb8(220, 220, 220),
      );

      final geometry = detectVisualTabGeometry(
        bytes,
        crop: const NormalizedRect.full(),
        expectedStringCount: 4,
      );

      expect(geometry.systems, hasLength(2));
    });

    test('does not silently treat an eight-string system as seven strings', () {
      final geometry = detectVisualTabGeometry(
        _stringSystemFixture(stringCount: 8),
        crop: const NormalizedRect.full(),
        expectedStringCount: 7,
      );

      expect(geometry.systems, isEmpty);
      expect(
        geometry.warnings,
        contains(
          'Raster geometry found 8 strings while 7 source strings were '
          'selected.',
        ),
      );
    });

    test('detects supported string counts with one geometry rule', () {
      for (final stringCount in [2, 4, 7, 8, 12]) {
        final geometry = detectVisualTabGeometry(
          _stringSystemFixture(stringCount: stringCount),
          crop: const NormalizedRect.full(),
          expectedStringCount: stringCount,
        );

        expect(
          geometry.systems.single.stringLines,
          hasLength(stringCount),
          reason: '$stringCount-string geometry must use the same detector.',
        );
      }
    });

    test('count-agnostic geometry keeps the complete overlapping staff', () {
      final geometry = detectVisualTabGeometryAnyStringCount(
        _stringSystemFixture(stringCount: 5),
        crop: const NormalizedRect.full(),
      );

      expect(geometry.systems, hasLength(1));
      expect(geometry.systems.single.stringLines, hasLength(5));
    });

    test('string-count consensus rejects one clean partial-staff guess', () {
      final guess = chooseVisualTabStringCountConsensus(const [
        VisualTabStringCountGuess(
          stringCount: 2,
          geometryConfidence: 1,
          detectedBarLines: 8,
        ),
        VisualTabStringCountGuess(
          stringCount: 4,
          geometryConfidence: 0.96,
          detectedBarLines: 6,
        ),
        VisualTabStringCountGuess(
          stringCount: 4,
          geometryConfidence: 0.94,
          detectedBarLines: 6,
        ),
      ]);

      expect(guess.stringCount, 4);
      expect(guess.warning, contains('Sampled rows disagreed'));
    });

    test(
      'raster readiness preview guesses the first row string count',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'music_tabbler_string_count_guess_',
        );
        addTearDown(() => directory.delete(recursive: true));
        await File(
          '${directory.path}${Platform.pathSeparator}row.png',
        ).writeAsBytes(_stringSystemFixture(stringCount: 8));
        final service = VisualTabAnalysisService(
          library: _AnalysisLibrary(directory.path),
          textRecognition: _PreparedCountingTextRecognition(),
        );

        final guess = await service.guessSourceStringCount(
          const VisualStrip(
            id: 'row',
            assetHash: 'row',
            assetExtension: 'png',
            pixelWidth: 1000,
            pixelHeight: 240,
          ),
        );

        expect(guess.stringCount, 8);
        expect(guess.geometryConfidence, greaterThan(0.9));
        expect(guess.detectedBarLines, greaterThanOrEqualTo(2));
        expect(guess.rasterLikelyUsable, isTrue);
      },
    );

    test('ignores a narrow rest stem crossing a string insertion gap', () {
      final image = img.decodePng(
        _tabFixture(
          background: img.ColorRgb8(255, 255, 255),
          foreground: img.ColorRgb8(0, 0, 0),
        ),
      )!;
      img.drawLine(
        image,
        x1: 300,
        y1: 46,
        x2: 300,
        y2: 60,
        color: img.ColorRgb8(0, 0, 0),
        thickness: 2,
      );

      final geometry = detectVisualTabGeometry(
        Uint8List.fromList(img.encodePng(image)),
        crop: const NormalizedRect.full(),
        expectedStringCount: 4,
      );

      expect(geometry.systems.first.connectedNotationRisks, isEmpty);
    });

    test('flags a diagonal connector joining neighboring strings', () {
      final image = img.decodePng(
        _tabFixture(
          background: img.ColorRgb8(255, 255, 255),
          foreground: img.ColorRgb8(0, 0, 0),
        ),
      )!;
      img.drawLine(
        image,
        x1: 288,
        y1: 47,
        x2: 312,
        y2: 59,
        color: img.ColorRgb8(0, 0, 0),
        thickness: 2,
      );

      final geometry = detectVisualTabGeometry(
        Uint8List.fromList(img.encodePng(image)),
        crop: const NormalizedRect.full(),
        expectedStringCount: 4,
      );

      expect(
        geometry.systems.first.connectedNotationRisks,
        contains(
          isA<VisualConnectedNotationRisk>().having(
            (risk) => risk.gapIndex,
            'gapIndex',
            1,
          ),
        ),
      );
    });

    test('opening signature ink is not exposed as a seam risk', () {
      final image = img.decodePng(_stringSystemFixture(stringCount: 8))!;
      img.drawString(
        image,
        '4',
        font: img.arial48,
        x: 90,
        y: 42,
        color: img.ColorRgb8(0, 0, 0),
      );
      img.drawString(
        image,
        '4',
        font: img.arial48,
        x: 90,
        y: 94,
        color: img.ColorRgb8(0, 0, 0),
      );

      final geometry = detectVisualTabGeometry(
        Uint8List.fromList(img.encodePng(image)),
        crop: const NormalizedRect.full(),
        expectedStringCount: 8,
      );

      expect(geometry.systems.single.connectedNotationRisks, isEmpty);
      expect(geometry.systems.single.openingSignatureRects, isNotEmpty);

      final signature = geometry.systems.single.openingSignatureRects.single;
      final result = buildVisualTabAnalysis(
        stripId: 'opening-signature',
        sourceType: VisualTabSourceType.rasterOcr,
        geometry: geometry,
        candidates: [
          VisualTabTextCandidate(
            text: '4',
            rect: NormalizedRect(
              signature.left,
              geometry.systems.single.stringLines[1] - 0.015,
              signature.right,
              geometry.systems.single.stringLines[2] + 0.015,
            ),
          ),
          VisualTabTextCandidate(
            text: '4',
            rect: NormalizedRect(
              signature.left,
              geometry.systems.single.stringLines[5] - 0.015,
              signature.right,
              geometry.systems.single.stringLines[6] + 0.015,
            ),
          ),
          VisualTabTextCandidate(
            text: '3',
            rect: NormalizedRect(
              0.30,
              geometry.systems.single.stringLines.last - 0.01,
              0.32,
              geometry.systems.single.stringLines.last + 0.01,
            ),
          ),
        ],
      );

      expect(
        result.systems.single.tokens
            .where((token) => token.isFretLike)
            .map((token) => token.text),
        ['3'],
        reason: 'The opening signature must not leave red review overlays.',
      );
    });

    test('single surviving opening-signature fragment is structural', () {
      final image = img.decodePng(_stringSystemFixture(stringCount: 4))!;
      // Compact Android renders can leave only the upper half of a large time
      // signature after staff-line removal. It must not become a seam review.
      img.drawString(
        image,
        '4',
        font: img.arial48,
        x: 70,
        y: 34,
        color: img.ColorRgb8(0, 0, 0),
      );

      final geometry = detectVisualTabGeometry(
        Uint8List.fromList(img.encodePng(image)),
        crop: const NormalizedRect.full(),
        expectedStringCount: 4,
      );

      expect(geometry.systems, hasLength(1));
      expect(geometry.systems.single.openingSignatureRects, isNotEmpty);
      expect(geometry.systems.single.connectedNotationRisks, isEmpty);
    });

    test('opening signature remains structural when it hides the first bar', () {
      final image = img.decodePng(_stringSystemFixture(stringCount: 4))!;
      // Match compact Android crops where the time signature overwrites the
      // left staff bar so the next measure boundary is the first detected bar.
      img.drawLine(
        image,
        x1: 30,
        y1: 48,
        x2: 30,
        y2: 100,
        color: img.ColorRgb8(255, 255, 255),
        thickness: 5,
      );
      img.drawString(
        image,
        '4',
        font: img.arial48,
        x: 70,
        y: 34,
        color: img.ColorRgb8(0, 0, 0),
      );

      final geometry = detectVisualTabGeometry(
        Uint8List.fromList(img.encodePng(image)),
        crop: const NormalizedRect.full(),
        expectedStringCount: 4,
      );

      expect(geometry.systems, hasLength(1));
      expect(geometry.systems.single.barLines.first, greaterThan(0.40));
      expect(geometry.systems.single.connectedNotationRisks, isEmpty);
    });

    test('time-signature strokes mistaken for bars stay structural', () {
      final image = img.decodePng(_stringSystemFixture(stringCount: 4))!;
      img.drawLine(
        image,
        x1: 30,
        y1: 48,
        x2: 30,
        y2: 100,
        color: img.ColorRgb8(255, 255, 255),
        thickness: 5,
      );
      for (final x in [15, 37, 85]) {
        img.drawLine(
          image,
          x1: x,
          y1: 50,
          x2: x,
          y2: 98,
          color: img.ColorRgb8(0, 0, 0),
          thickness: 1,
        );
      }
      img.drawString(
        image,
        '4',
        font: img.arial48,
        x: 70,
        y: 34,
        color: img.ColorRgb8(0, 0, 0),
      );

      final geometry = detectVisualTabGeometry(
        Uint8List.fromList(img.encodePng(image)),
        crop: const NormalizedRect.full(),
        expectedStringCount: 4,
      );

      expect(geometry.systems, hasLength(1));
      expect(
        geometry.systems.single.barLines.where((bar) => bar < 0.15).length,
        greaterThanOrEqualTo(3),
      );
      expect(geometry.systems.single.connectedNotationRisks, isEmpty);
    });

    test('two-note opening sustains are not treated as a time signature', () {
      const lines = [0.20, 0.25, 0.30, 0.35, 0.40, 0.45, 0.50, 0.55];
      const geometry = VisualTabGeometry(
        systems: [
          VisualTabSystemGeometry(
            rect: NormalizedRect(0.05, 0.15, 0.95, 0.60),
            stringLines: lines,
            barLines: [0.10, 0.50, 0.90],
          ),
        ],
      );
      final result = buildVisualTabAnalysis(
        stripId: 'opening-sustain',
        sourceType: VisualTabSourceType.rasterOcr,
        geometry: geometry,
        candidates: const [
          VisualTabTextCandidate(
            text: '(7)',
            rect: NormalizedRect(0.12, 0.39, 0.15, 0.43),
          ),
          VisualTabTextCandidate(
            text: '(8)',
            rect: NormalizedRect(0.12, 0.44, 0.15, 0.48),
          ),
        ],
      );

      expect(
        result.systems.single.tokens
            .where((token) => token.enabled && token.isFretLike)
            .map((token) => token.text),
        ['(7)', '(8)'],
      );
    });
  });

  test('assigns fret tokens but leaves measure numbers unassigned', () {
    final geometry = detectVisualTabGeometry(
      _tabFixture(
        background: img.ColorRgb8(255, 255, 255),
        foreground: img.ColorRgb8(0, 0, 0),
      ),
      crop: const NormalizedRect.full(),
      expectedStringCount: 4,
    );
    final first = geometry.systems.first;
    final stringY = first.stringLines[2];
    final spacing = first.stringLines[1] - first.stringLines[0];
    final result = buildVisualTabAnalysis(
      stripId: 'strip',
      sourceType: VisualTabSourceType.rasterOcr,
      geometry: geometry,
      candidates: [
        VisualTabTextCandidate(
          text: '(12)',
          rect: NormalizedRect(0.20, stringY - 0.01, 0.25, stringY + 0.01),
        ),
        VisualTabTextCandidate(
          text: '7',
          rect: NormalizedRect(
            0.35,
            first.stringLines.first - spacing * 2.8,
            0.37,
            first.stringLines.first - spacing * 2.2,
          ),
        ),
        VisualTabTextCandidate(
          text: 'X',
          rect: NormalizedRect(0.45, stringY - 0.01, 0.48, stringY + 0.01),
        ),
      ],
    );

    final tokens = result.systems.expand((system) => system.tokens).toList();
    final fret = tokens.singleWhere((token) => token.text == '(12)');
    final measure = tokens.singleWhere((token) => token.text == '7');
    final deadNote = tokens.singleWhere((token) => token.text == 'X');
    expect(fret.kind, VisualTabTokenKind.fret);
    expect(fret.stringIndex, 1);
    expect(measure.kind, VisualTabTokenKind.measureNumber);
    expect(measure.stringIndex, isNull);
    expect(measure.requiresReview, isFalse);
    expect(result.unresolvedReviewCount, 0);
    expect(deadNote.kind, VisualTabTokenKind.deadNote);
  });

  test('positioned PDF opening signatures are excluded from review', () {
    const lines = [0.35, 0.45, 0.55, 0.65];
    const geometry = VisualTabGeometry(
      systems: [
        VisualTabSystemGeometry(
          rect: NormalizedRect(0.05, 0.20, 0.95, 0.72),
          stringLines: lines,
          barLines: [0.10, 0.50, 0.90],
          openingSignatureRects: [NormalizedRect(0.08, 0.30, 0.14, 0.62)],
        ),
      ],
    );
    final result = buildVisualTabAnalysis(
      stripId: 'positioned-signature',
      sourceType: VisualTabSourceType.positionedPdf,
      geometry: geometry,
      candidates: const [
        VisualTabTextCandidate(
          text: '4',
          rect: NormalizedRect(0.09, 0.32, 0.13, 0.43),
        ),
        VisualTabTextCandidate(
          text: '4',
          rect: NormalizedRect(0.09, 0.50, 0.13, 0.61),
        ),
        VisualTabTextCandidate(
          text: '0',
          rect: NormalizedRect(0.24, 0.61, 0.27, 0.68),
        ),
      ],
    );

    expect(result.systems.single.tokens.map((token) => token.text), ['0']);
    expect(result.enabledFretTokenCount, 1);
    expect(result.unresolvedReviewCount, 0);
  });

  test('never classifies out-of-range measure labels as frets', () {
    expect(
      classifyVisualTabToken('44', signedDistance: 0, stringSpacing: 0.02),
      VisualTabTokenKind.measureNumber,
    );
    expect(
      classifyVisualTabToken('118', signedDistance: 0, stringSpacing: 0.02),
      VisualTabTokenKind.measureNumber,
    );
  });

  test('stacked time-signature digits at the first bar are not frets', () {
    const geometry = VisualTabGeometry(
      systems: [
        VisualTabSystemGeometry(
          rect: NormalizedRect(0.05, 0.2, 0.95, 0.8),
          stringLines: [0.35, 0.45, 0.55, 0.65],
          barLines: [0.10, 0.50, 0.90],
        ),
      ],
    );
    final result = buildVisualTabAnalysis(
      stripId: 'strip',
      sourceType: VisualTabSourceType.rasterOcr,
      geometry: geometry,
      candidates: const [
        VisualTabTextCandidate(
          text: '4',
          rect: NormalizedRect(0.09, 0.31, 0.11, 0.39),
        ),
        VisualTabTextCandidate(
          text: '4',
          rect: NormalizedRect(0.09, 0.51, 0.11, 0.59),
        ),
        VisualTabTextCandidate(
          text: '0',
          rect: NormalizedRect(0.14, 0.62, 0.16, 0.68),
        ),
      ],
    );

    final frets = result.systems.single.tokens.where(
      (token) => token.isFretLike,
    );
    expect(frets.map((token) => token.text), ['0']);
  });

  test('mid-song mixed time-signature digits are not frets', () {
    const geometry = VisualTabGeometry(
      systems: [
        VisualTabSystemGeometry(
          rect: NormalizedRect(0.05, 0.2, 0.95, 0.8),
          stringLines: [0.35, 0.45, 0.55, 0.65],
          barLines: [0.10, 0.50, 0.90],
        ),
      ],
    );
    final result = buildVisualTabAnalysis(
      stripId: 'mid-song-3-4',
      sourceType: VisualTabSourceType.rasterOcr,
      geometry: geometry,
      candidates: const [
        VisualTabTextCandidate(
          text: '3',
          rect: NormalizedRect(0.485, 0.30, 0.515, 0.42),
        ),
        VisualTabTextCandidate(
          text: '4',
          rect: NormalizedRect(0.485, 0.50, 0.515, 0.62),
        ),
        VisualTabTextCandidate(
          text: '2',
          rect: NormalizedRect(0.62, 0.62, 0.65, 0.68),
        ),
      ],
    );

    expect(result.systems.single.tokens.map((token) => token.text), ['2']);
    expect(result.unresolvedReviewCount, 0);
  });

  test('ordinary stacked frets near a bar remain reviewable notes', () {
    const geometry = VisualTabGeometry(
      systems: [
        VisualTabSystemGeometry(
          rect: NormalizedRect(0.05, 0.2, 0.95, 0.8),
          stringLines: [0.35, 0.45, 0.55, 0.65],
          barLines: [0.10, 0.50, 0.90],
        ),
      ],
    );
    final result = buildVisualTabAnalysis(
      stripId: 'mid-song-chord',
      sourceType: VisualTabSourceType.rasterOcr,
      geometry: geometry,
      candidates: const [
        VisualTabTextCandidate(
          text: '3',
          rect: NormalizedRect(0.505, 0.43, 0.525, 0.47),
        ),
        VisualTabTextCandidate(
          text: '4',
          rect: NormalizedRect(0.505, 0.53, 0.525, 0.57),
        ),
      ],
    );

    expect(result.systems.single.tokens.map((token) => token.text), ['3', '4']);
  });

  test('hammer-on endpoints touching a connector remain fret tokens', () {
    const connector = NormalizedRect(0.43, 0.315, 0.58, 0.455);
    const geometry = VisualTabGeometry(
      systems: [
        VisualTabSystemGeometry(
          rect: NormalizedRect(0.05, 0.20, 0.95, 0.80),
          stringLines: [0.35, 0.45, 0.55, 0.65],
          barLines: [0.10, 0.70, 0.90],
          connectedNotationRisks: [
            VisualConnectedNotationRisk(
              id: 'hammer-on-connector',
              rect: connector,
              gapIndex: 0,
            ),
          ],
        ),
      ],
    );
    final result = buildVisualTabAnalysis(
      stripId: 'hammer-on',
      sourceType: VisualTabSourceType.rasterOcr,
      geometry: geometry,
      candidates: const [
        VisualTabTextCandidate(
          text: '2',
          rect: NormalizedRect(0.435, 0.335, 0.455, 0.365),
        ),
        VisualTabTextCandidate(
          text: '4',
          rect: NormalizedRect(0.555, 0.335, 0.575, 0.365),
        ),
      ],
    );

    final tokens = result.systems.single.tokens;
    expect(tokens.map((token) => token.text), ['2', '4']);
    expect(
      tokens.every((token) => token.kind == VisualTabTokenKind.fret),
      true,
    );
    expect(tokens.every((token) => token.enabled), true);
    expect(tokens.every((token) => token.stringIndex == 3), true);
  });

  test('ambiguous stacked time-signature digits are still ignored', () {
    const signatureTop = NormalizedRect(0.09, 0.31, 0.11, 0.39);
    const signatureBottom = NormalizedRect(0.09, 0.51, 0.11, 0.59);
    const geometry = VisualTabGeometry(
      systems: [
        VisualTabSystemGeometry(
          rect: NormalizedRect(0.05, 0.2, 0.95, 0.8),
          stringLines: [0.35, 0.45, 0.55, 0.65],
          barLines: [0.10, 0.50, 0.90],
          connectedNotationRisks: [
            VisualConnectedNotationRisk(
              id: 'signature-overlap',
              rect: signatureTop,
              gapIndex: 0,
            ),
          ],
        ),
      ],
    );
    final result = buildVisualTabAnalysis(
      stripId: 'ambiguous-signature',
      sourceType: VisualTabSourceType.rasterOcr,
      geometry: geometry,
      candidates: const [
        VisualTabTextCandidate(text: '4', rect: signatureTop),
        VisualTabTextCandidate(text: '4', rect: signatureBottom),
        VisualTabTextCandidate(
          text: '0',
          rect: NormalizedRect(0.24, 0.62, 0.27, 0.68),
        ),
      ],
    );

    expect(result.systems.single.tokens.map((token) => token.text), ['0']);
    expect(result.unresolvedReviewCount, 1);
  });

  test('large stacked time signatures are ignored for every string count', () {
    for (final stringCount in [4, 8, 12]) {
      final lines = [
        for (var index = 0; index < stringCount; index += 1)
          0.20 + index * 0.04,
      ];
      final geometry = VisualTabGeometry(
        systems: [
          VisualTabSystemGeometry(
            rect: NormalizedRect(0.05, 0.15, 0.95, lines.last + 0.05),
            stringLines: lines,
            barLines: const [0.10, 0.42, 0.90],
          ),
        ],
      );
      final result = buildVisualTabAnalysis(
        stripId: 'strip-$stringCount',
        sourceType: VisualTabSourceType.rasterOcr,
        geometry: geometry,
        candidates: [
          VisualTabTextCandidate(
            text: '4',
            rect: NormalizedRect(
              0.19,
              lines[1] - 0.025,
              0.22,
              lines[1] + 0.025,
            ),
          ),
          VisualTabTextCandidate(
            text: '4',
            rect: NormalizedRect(
              0.19,
              lines[stringCount - 2] - 0.025,
              0.22,
              lines[stringCount - 2] + 0.025,
            ),
          ),
          VisualTabTextCandidate(
            text: '3',
            rect: NormalizedRect(
              0.30,
              lines.last - 0.012,
              0.32,
              lines.last + 0.012,
            ),
          ),
        ],
      );

      expect(
        result.systems.single.tokens
            .where((token) => token.isFretLike)
            .map((token) => token.text),
        ['3'],
        reason: '$stringCount-string systems use the same signature rule.',
      );
    }
  });

  test('positioned PDF analysis drops notation-like systems without frets', () {
    final geometry = detectVisualTabGeometry(
      _tabFixture(
        background: img.ColorRgb8(255, 255, 255),
        foreground: img.ColorRgb8(0, 0, 0),
      ),
      crop: const NormalizedRect.full(),
      expectedStringCount: 4,
    );
    final tabSystem = geometry.systems.last;
    final stringY = tabSystem.stringLines.last;

    final result = buildVisualTabAnalysis(
      stripId: 'strip',
      sourceType: VisualTabSourceType.positionedPdf,
      geometry: geometry,
      candidates: [
        VisualTabTextCandidate(
          text: '9',
          rect: NormalizedRect(0.3, stringY - 0.01, 0.33, stringY + 0.01),
        ),
      ],
    );

    expect(result.systems, hasLength(1));
    expect(result.enabledFretTokenCount, 1);
  });

  test('positioned sustain labels supplement overlapping raster OCR', () {
    final merged = mergeVisualTabCandidates(
      positioned: const [
        VisualTabTextCandidate(
          text: '(0)',
          rect: NormalizedRect(0.20, 0.48, 0.25, 0.54),
        ),
      ],
      raster: const [
        VisualTabTextCandidate(
          text: '0',
          rect: NormalizedRect(0.21, 0.49, 0.24, 0.53),
          confidence: 0.91,
        ),
        VisualTabTextCandidate(
          text: '5',
          rect: NormalizedRect(0.60, 0.48, 0.63, 0.54),
          confidence: 0.88,
        ),
      ],
    );

    expect(merged.map((candidate) => candidate.text), ['(0)', '5']);
  });

  test(
    'positioned PDF without fret text does not silently invoke raster OCR',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'music_tabbler_positioned_analysis_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final imagePath = '${directory.path}${Platform.pathSeparator}strip.png';
      await File(imagePath).writeAsBytes(
        _tabFixture(
          background: img.ColorRgb8(255, 255, 255),
          foreground: img.ColorRgb8(0, 0, 0),
        ),
      );
      final recognition = _CountingTextRecognition();
      final service = VisualTabAnalysisService(
        library: _AnalysisLibrary(directory.path),
        textRecognition: recognition,
      );

      final result = await service.analyze(
        const VisualStrip(
          id: 'strip',
          assetHash: 'strip',
          assetExtension: 'png',
          pixelWidth: 600,
          pixelHeight: 240,
          sourceAssetHash: 'missing_source',
          sourcePage: 1,
        ),
        sourceStringCount: 4,
      );

      expect(result.sourceType, VisualTabSourceType.positionedPdf);
      expect(recognition.callCount, 0);
      expect(
        result.warnings,
        contains(
          'The positioned PDF contains no usable fret text for this row. '
          'Use Raster / OCR in review if the row contains tablature.',
        ),
      );
    },
  );

  test('unavailable positioned PDF text falls back to raster review', () async {
    final directory = await Directory.systemTemp.createTemp(
      'music_tabbler_positioned_fallback_',
    );
    addTearDown(() => directory.delete(recursive: true));
    await File(
      '${directory.path}${Platform.pathSeparator}strip.png',
    ).writeAsBytes(
      _tabFixture(
        background: img.ColorRgb8(255, 255, 255),
        foreground: img.ColorRgb8(0, 0, 0),
      ),
    );
    await File(
      '${directory.path}${Platform.pathSeparator}corrupt_source.pdf',
    ).writeAsBytes(const [0, 1, 2, 3]);
    final service = VisualTabAnalysisService(
      library: _AnalysisLibrary(directory.path),
      textRecognition: _CountingTextRecognition(),
    );

    final result = await service.analyze(
      const VisualStrip(
        id: 'strip',
        assetHash: 'strip',
        assetExtension: 'png',
        pixelWidth: 600,
        pixelHeight: 240,
        sourceAssetHash: 'corrupt_source',
        sourcePage: 1,
      ),
      sourceStringCount: 4,
    );

    expect(result.sourceType, VisualTabSourceType.rasterOcr);
    expect(result.systems, hasLength(2));
    expect(
      result.warnings,
      contains(
        'The positioned PDF text layer was unavailable on this device. '
        'Raster analysis was used instead.',
      ),
    );
  });

  test('raster OCR is cropped and run once per detected tab system', () async {
    final directory = await Directory.systemTemp.createTemp(
      'music_tabbler_raster_analysis_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final imagePath = '${directory.path}${Platform.pathSeparator}strip.png';
    await File(imagePath).writeAsBytes(
      _tabFixture(
        background: img.ColorRgb8(255, 255, 255),
        foreground: img.ColorRgb8(0, 0, 0),
      ),
    );
    final recognition = _CountingTextRecognition();
    final service = VisualTabAnalysisService(
      library: _AnalysisLibrary(directory.path),
      textRecognition: recognition,
    );

    final result = await service.analyze(
      const VisualStrip(
        id: 'strip',
        assetHash: 'strip',
        assetExtension: 'png',
        pixelWidth: 600,
        pixelHeight: 240,
      ),
      sourceStringCount: 4,
      preferPositionedPdf: false,
    );

    expect(result.sourceType, VisualTabSourceType.rasterOcr);
    expect(result.systems, hasLength(2));
    expect(recognition.callCount, 2);
  });

  test(
    'native OCR failure preserves deterministic glyph recognition',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'music_tabbler_raster_ocr_failure_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final image = img.decodePng(
        _tabFixture(
          background: img.ColorRgb8(255, 255, 255),
          foreground: img.ColorRgb8(0, 0, 0),
        ),
      )!;
      img.drawString(
        image,
        '7',
        font: img.arial14,
        x: 100,
        y: 52,
        color: img.ColorRgb8(0, 0, 0),
      );
      await File(
        '${directory.path}${Platform.pathSeparator}strip.png',
      ).writeAsBytes(img.encodePng(image));
      final service = VisualTabAnalysisService(
        library: _AnalysisLibrary(directory.path),
        textRecognition: const _FailingPreparedTextRecognition(),
      );

      final result = await service.analyze(
        const VisualStrip(
          id: 'strip',
          assetHash: 'strip',
          assetExtension: 'png',
          pixelWidth: 600,
          pixelHeight: 240,
        ),
        sourceStringCount: 4,
        preferPositionedPdf: false,
      );

      expect(result.sourceType, VisualTabSourceType.rasterOcr);
      expect(result.systems, hasLength(2));
      expect(result.enabledFretTokenCount, greaterThanOrEqualTo(1));
      expect(
        result.warnings,
        isNot(
          contains(
            'Local raster OCR was unavailable on this device. The detected '
            'string geometry remains editable; use Add note for missed frets '
            'and dead notes.',
          ),
        ),
      );
    },
  );

  test('prepared raster OCR maps isolated glyphs back to strings', () async {
    final directory = await Directory.systemTemp.createTemp(
      'music_tabbler_prepared_raster_analysis_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final image = img.decodePng(
      _tabFixture(
        background: img.ColorRgb8(255, 255, 255),
        foreground: img.ColorRgb8(0, 0, 0),
      ),
    )!;
    img.drawString(
      image,
      '7',
      font: img.arial14,
      x: 100,
      y: 52,
      color: img.ColorRgb8(0, 0, 0),
    );
    final imagePath = '${directory.path}${Platform.pathSeparator}strip.png';
    await File(imagePath).writeAsBytes(img.encodePng(image));
    final recognition = _PreparedCountingTextRecognition();
    final service = VisualTabAnalysisService(
      library: _AnalysisLibrary(directory.path),
      textRecognition: recognition,
    );

    final result = await service.analyze(
      const VisualStrip(
        id: 'strip',
        assetHash: 'strip',
        assetExtension: 'png',
        pixelWidth: 600,
        pixelHeight: 240,
      ),
      sourceStringCount: 4,
      preferPositionedPdf: false,
    );

    expect(recognition.preparedCallCount, greaterThanOrEqualTo(1));
    expect(result.enabledFretTokenCount, greaterThanOrEqualTo(1));
  });

  test(
    'prepared raster OCR splits a large chart into bounded sheets',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'music_tabbler_batched_raster_analysis_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final image = img.decodePng(
        _tabFixture(
          background: img.ColorRgb8(255, 255, 255),
          foreground: img.ColorRgb8(0, 0, 0),
        ),
      )!;
      for (var index = 0; index < 16; index += 1) {
        img.drawString(
          image,
          '7',
          font: img.arial14,
          x: 35 + index * 34,
          y: 52,
          color: img.ColorRgb8(0, 0, 0),
        );
      }
      await File(
        '${directory.path}${Platform.pathSeparator}strip.png',
      ).writeAsBytes(img.encodePng(image));
      final recognition = _PreparedCountingTextRecognition();
      final service = VisualTabAnalysisService(
        library: _AnalysisLibrary(directory.path),
        textRecognition: recognition,
      );

      final result = await service.analyze(
        const VisualStrip(
          id: 'strip',
          assetHash: 'strip',
          assetExtension: 'png',
          pixelWidth: 600,
          pixelHeight: 240,
        ),
        sourceStringCount: 4,
        preferPositionedPdf: false,
      );

      expect(result.enabledFretTokenCount, greaterThanOrEqualTo(13));
      expect(recognition.preparedCallCount, greaterThanOrEqualTo(2));
    },
  );

  test('Songsterr open-string glyph is not promoted to fret eight', () {
    final glyphBytes = base64Decode(_songsterrZeroGlyph);

    expect(correctVisualTabRasterZeroEight('8', glyphBytes), '0');
    expect(correctVisualTabRasterZeroEight('6', glyphBytes), '0');
    expect(correctVisualTabRasterZeroEight('9', glyphBytes), '0');
    expect(correctVisualTabRasterZeroEight('7', glyphBytes), '7');
  });

  test(
    'deterministic glyph classifier rejects a disagreeing platform label',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'music_tabbler_native_raster_analysis_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final image = img.decodePng(
        _tabFixture(
          background: img.ColorRgb8(255, 255, 255),
          foreground: img.ColorRgb8(0, 0, 0),
        ),
      )!;
      img.drawString(
        image,
        '7',
        font: img.arial14,
        x: 100,
        y: 52,
        color: img.ColorRgb8(0, 0, 0),
      );
      final imagePath = '${directory.path}${Platform.pathSeparator}strip.png';
      await File(imagePath).writeAsBytes(img.encodePng(image));
      final service = VisualTabAnalysisService(
        library: _AnalysisLibrary(directory.path),
        textRecognition: const _NativeOverrideRecognition(),
      );

      final result = await service.analyze(
        const VisualStrip(
          id: 'strip',
          assetHash: 'strip',
          assetExtension: 'png',
          pixelWidth: 600,
          pixelHeight: 240,
        ),
        sourceStringCount: 4,
        preferPositionedPdf: false,
      );

      final frets = result.systems
          .expand((system) => system.tokens)
          .where((token) => token.kind == VisualTabTokenKind.fret)
          .toList();
      expect(frets, isNotEmpty);
      expect(
        frets,
        everyElement(
          isA<VisualTabToken>().having((token) => token.text, 'text', '7'),
        ),
      );
      expect(
        frets,
        everyElement(
          isA<VisualTabToken>().having(
            (token) => token.enabled,
            'enabled',
            isTrue,
          ),
        ),
      );
    },
  );

  test(
    'low-confidence deterministic guesses do not replace native OCR',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'music_tabbler_eight_string_raster_analysis_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final imagePath = '${directory.path}${Platform.pathSeparator}strip.png';
      await File(
        imagePath,
      ).writeAsBytes(base64Decode(_eightStringStackedThrees));
      final service = VisualTabAnalysisService(
        library: _AnalysisLibrary(directory.path),
        textRecognition: const _NativeThreeRecognition(),
      );

      final result = await service.analyze(
        const VisualStrip(
          id: 'strip',
          assetHash: 'strip',
          assetExtension: 'png',
          pixelWidth: 250,
          pixelHeight: 140,
        ),
        sourceStringCount: 8,
        preferPositionedPdf: false,
      );

      final frets = result.systems
          .expand((system) => system.tokens)
          .where((token) => token.kind == VisualTabTokenKind.fret)
          .toList();
      expect(frets.length, greaterThanOrEqualTo(8));
      expect(
        frets,
        everyElement(
          isA<VisualTabToken>()
              .having((token) => token.text, 'text', '3')
              .having((token) => token.enabled, 'enabled', isTrue),
        ),
      );
    },
  );

  test('one reliable OCR glyph stabilizes visually repeated peers', () async {
    final directory = await Directory.systemTemp.createTemp(
      'music_tabbler_repeated_eight_string_analysis_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final imagePath = '${directory.path}${Platform.pathSeparator}strip.png';
    await File(imagePath).writeAsBytes(base64Decode(_eightStringRepeatedOnes));
    final service = VisualTabAnalysisService(
      library: _AnalysisLibrary(directory.path),
      textRecognition: const _FirstNativeOneRecognition(),
    );

    final result = await service.analyze(
      const VisualStrip(
        id: 'strip',
        assetHash: 'strip',
        assetExtension: 'png',
        pixelWidth: 500,
        pixelHeight: 210,
      ),
      sourceStringCount: 8,
      preferPositionedPdf: false,
    );

    final enabledOnes = result.systems
        .expand((system) => system.tokens)
        .where((token) => token.text == '1' && token.enabled)
        .toList();
    expect(enabledOnes.length, greaterThanOrEqualTo(10));
    expect(
      result.systems
          .expand((system) => system.tokens)
          .where((token) => token.isFretLike && token.enabled),
      everyElement(
        isA<VisualTabToken>().having((token) => token.text, 'text', '1'),
      ),
    );
  });

  test('a repeated glyph family is proposed without native OCR', () async {
    final directory = await Directory.systemTemp.createTemp(
      'music_tabbler_repeated_family_analysis_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final imagePath = '${directory.path}${Platform.pathSeparator}strip.png';
    await File(imagePath).writeAsBytes(base64Decode(_eightStringRepeatedOnes));
    final service = VisualTabAnalysisService(
      library: _AnalysisLibrary(directory.path),
      textRecognition: _PreparedCountingTextRecognition(),
    );

    final result = await service.analyze(
      const VisualStrip(
        id: 'strip',
        assetHash: 'strip',
        assetExtension: 'png',
        pixelWidth: 500,
        pixelHeight: 210,
      ),
      sourceStringCount: 8,
      preferPositionedPdf: false,
    );

    expect(result.enabledFretTokenCount, greaterThanOrEqualTo(10));
    expect(
      result.systems
          .expand((system) => system.tokens)
          .where((token) => token.enabled && token.isFretLike),
      everyElement(
        isA<VisualTabToken>().having((token) => token.text, 'text', '1'),
      ),
    );
  });

  test('stacked chord and slide columns are string-count agnostic', () async {
    for (final stringCount in [4, 8, 12]) {
      final directory = await Directory.systemTemp.createTemp(
        'music_tabbler_notation_columns_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final imagePath = '${directory.path}${Platform.pathSeparator}strip.png';
      final bytes = _notationColumnFixture(stringCount: stringCount);
      await File(imagePath).writeAsBytes(bytes);
      final image = img.decodePng(bytes)!;
      final service = VisualTabAnalysisService(
        library: _AnalysisLibrary(directory.path),
        textRecognition: _PreparedCountingTextRecognition(),
      );

      final result = await service.analyze(
        VisualStrip(
          id: 'strip',
          assetHash: 'strip',
          assetExtension: 'png',
          pixelWidth: image.width,
          pixelHeight: image.height,
        ),
        sourceStringCount: stringCount,
        preferPositionedPdf: false,
      );
      final frets = result.systems
          .expand((system) => system.tokens)
          .where((token) => token.enabled && token.isFretLike)
          .toList();
      List<VisualTabToken> inColumn(double left, double right) => frets
          .where((token) => token.rect.left >= left && token.rect.left <= right)
          .toList();

      expect(
        inColumn(0.23, 0.29).map((token) => token.stringIndex).toSet(),
        hasLength(2),
        reason: '$stringCount-string two-note chord column',
      );
      expect(
        inColumn(0.33, 0.39).map((token) => token.stringIndex).toSet(),
        hasLength(3),
        reason: '$stringCount-string three-note chord column',
      );
      expect(
        inColumn(0.69, 0.80).map((token) => token.text),
        containsAll(['1', '3']),
        reason: '$stringCount-string slide endpoints',
      );
    }
  });

  test('reported three-note sustain column remains three strings', () async {
    final directory = await Directory.systemTemp.createTemp(
      'music_tabbler_sustain_column_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final bytes = base64Decode(_panThreeStringSustainColumn);
    final decoded = img.decodePng(bytes)!;
    await File(
      '${directory.path}${Platform.pathSeparator}strip.png',
    ).writeAsBytes(bytes);
    final service = VisualTabAnalysisService(
      library: _AnalysisLibrary(directory.path),
      textRecognition: _PreparedCountingTextRecognition(),
    );

    final result = await service.analyze(
      VisualStrip(
        id: 'strip',
        assetHash: 'strip',
        assetExtension: 'png',
        pixelWidth: decoded.width,
        pixelHeight: decoded.height,
      ),
      sourceStringCount: 8,
      preferPositionedPdf: false,
    );
    final frets = result.systems.single.tokens
        .where((token) => token.enabled && token.isFretLike)
        .toList();
    final sustainColumn = frets.where((token) {
      final centerX = (token.rect.left + token.rect.right) / 2;
      return centerX >= 0.60 && centerX <= 0.69;
    }).toList();

    expect(
      sustainColumn.map((token) => token.stringIndex).toSet(),
      hasLength(3),
      reason: frets
          .map(
            (token) =>
                '${token.text}:s${token.stringIndex}'
                '@${token.rect.left.toStringAsFixed(3)}',
          )
          .join(' '),
    );
    expect(
      sustainColumn,
      everyElement(
        isA<VisualTabToken>().having(
          (token) => token.text,
          'text',
          startsWith('('),
        ),
      ),
    );
  });

  test('tie fragments before a raster sustain are not fret tokens', () {
    const stringLines = [
      0.3090277777777778,
      0.3900462962962963,
      0.4710648148148148,
      0.5543981481481481,
      0.6354166666666666,
      0.7164351851851852,
      0.7974537037037037,
      0.8784722222222222,
    ];
    const geometry = VisualTabGeometry(
      systems: [
        VisualTabSystemGeometry(
          rect: NormalizedRect(0, 0.30, 1, 0.95),
          stringLines: stringLines,
          barLines: [0.0068, 0.0873, 0.0918, 0.6088, 0.9919],
        ),
      ],
    );
    const candidates = [
      VisualTabTextCandidate(
        text: '1',
        rect: NormalizedRect(0.5274, 0.7593, 0.5374, 0.8310),
        confidence: 0.98,
      ),
      // The descending and ascending sides of the tie curve were previously
      // promoted to fret 21 and fret 11 on the sustained string.
      VisualTabTextCandidate(
        text: '21',
        rect: NormalizedRect(0.5502, 0.7940, 0.5672, 0.8449),
        confidence: 0.72,
      ),
      VisualTabTextCandidate(
        text: '11',
        rect: NormalizedRect(0.6132, 0.7940, 0.6277, 0.8472),
        confidence: 0.74,
      ),
      // The bar/tie junction was also proposed on the neighbouring string.
      VisualTabTextCandidate(
        text: '11',
        rect: NormalizedRect(0.6418, 0.7130, 0.6655, 0.7662),
        confidence: 0.74,
      ),
      VisualTabTextCandidate(
        text: '(1)',
        rect: NormalizedRect(0.6393, 0.7523, 0.6655, 0.8449),
        confidence: 0.90,
      ),
      VisualTabTextCandidate(
        text: '1',
        rect: NormalizedRect(0.7624, 0.7593, 0.7724, 0.8310),
        confidence: 0.98,
      ),
    ];

    final result = buildVisualTabAnalysis(
      stripId: 'pan-row-2',
      sourceType: VisualTabSourceType.rasterOcr,
      geometry: geometry,
      candidates: candidates,
    );
    final frets = result.systems.single.tokens
        .where((token) => token.enabled && token.isFretLike)
        .toList();

    expect(frets.map((token) => token.text), ['1', '(1)', '1']);
  });

  test('parenthesized sustain label follows its preceding fret', () {
    const geometry = VisualTabGeometry(
      systems: [
        VisualTabSystemGeometry(
          rect: NormalizedRect(0, 0.2, 1, 0.8),
          stringLines: [0.35, 0.45, 0.55, 0.65],
          barLines: [0.05, 0.50, 0.95],
        ),
      ],
    );
    final result = buildVisualTabAnalysis(
      stripId: 'correct-sustain-label',
      sourceType: VisualTabSourceType.rasterOcr,
      geometry: geometry,
      candidates: const [
        VisualTabTextCandidate(
          text: '0',
          rect: NormalizedRect(0.38, 0.42, 0.40, 0.48),
          confidence: 0.90,
        ),
        VisualTabTextCandidate(
          text: '(3)',
          rect: NormalizedRect(0.46, 0.41, 0.50, 0.49),
          confidence: 0.72,
        ),
      ],
    );

    expect(
      result.systems.single.tokens
          .where((token) => token.enabled && token.isFretLike)
          .map((token) => token.text),
      ['0', '(0)'],
    );
  });

  test('duplicate neighboring glyphs infer one middle-string sustain', () {
    const geometry = VisualTabGeometry(
      systems: [
        VisualTabSystemGeometry(
          rect: NormalizedRect(0, 0.2, 1, 0.8),
          stringLines: [0.35, 0.45, 0.55, 0.65],
          barLines: [0.05, 0.50, 0.95],
        ),
      ],
    );
    final result = buildVisualTabAnalysis(
      stripId: 'bracketed-sustain',
      sourceType: VisualTabSourceType.rasterOcr,
      geometry: geometry,
      candidates: const [
        VisualTabTextCandidate(
          text: '0',
          rect: NormalizedRect(0.38, 0.42, 0.40, 0.48),
          confidence: 0.90,
        ),
        VisualTabTextCandidate(
          text: '11',
          rect: NormalizedRect(0.46, 0.32, 0.49, 0.39),
          confidence: 0.74,
        ),
        VisualTabTextCandidate(
          text: '11',
          rect: NormalizedRect(0.46, 0.51, 0.49, 0.58),
          confidence: 0.74,
        ),
      ],
    );

    final frets = result.systems.single.tokens
        .where((token) => token.enabled && token.isFretLike)
        .toList();
    expect(frets.map((token) => token.text), ['0', '(0)']);
    expect(frets.last.stringIndex, 2);
    expect(frets.last.sourceGlyphMatchesToken, isFalse);
  });

  test('reported slide-adjacent fret remains enabled', () async {
    final directory = await Directory.systemTemp.createTemp(
      'music_tabbler_slide_adjacent_fret_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final bytes = base64Decode(_panBar31SlideFixture);
    final decoded = img.decodePng(bytes)!;
    await File(
      '${directory.path}${Platform.pathSeparator}strip.png',
    ).writeAsBytes(bytes);
    final service = VisualTabAnalysisService(
      library: _AnalysisLibrary(directory.path),
      textRecognition: _PreparedCountingTextRecognition(),
    );

    final result = await service.analyze(
      VisualStrip(
        id: 'strip',
        assetHash: 'strip',
        assetExtension: 'png',
        pixelWidth: decoded.width,
        pixelHeight: decoded.height,
      ),
      sourceStringCount: 8,
      preferPositionedPdf: false,
    );
    final frets = result.systems.single.tokens
        .where((token) => token.enabled && token.isFretLike)
        .toList();

    expect(
      frets.where((token) {
        final centerX = (token.rect.left + token.rect.right) / 2;
        return token.text == '7' && centerX >= 0.45 && centerX <= 0.52;
      }),
      hasLength(1),
      reason: frets
          .map(
            (token) =>
                '${token.text}:s${token.stringIndex}'
                '@${token.rect.left.toStringAsFixed(3)}',
          )
          .join(' '),
    );
  });

  test('thin slide strokes do not merge adjacent fret glyphs', () async {
    final directory = await Directory.systemTemp.createTemp(
      'music_tabbler_slide_raster_analysis_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final image = img.decodePng(
      _tabFixture(
        background: img.ColorRgb8(255, 255, 255),
        foreground: img.ColorRgb8(0, 0, 0),
      ),
    )!;
    for (final (value, x) in [
      ('12', 90),
      ('9', 200),
      ('9', 255),
      ('9', 310),
      ('9', 365),
    ]) {
      img.drawString(
        image,
        value,
        font: img.arial14,
        x: x,
        y: 64,
        color: img.ColorRgb8(0, 0, 0),
      );
    }
    img.drawLine(
      image,
      x1: 108,
      y1: 73,
      x2: 200,
      y2: 76,
      color: img.ColorRgb8(0, 0, 0),
    );
    final imagePath = '${directory.path}${Platform.pathSeparator}strip.png';
    await File(imagePath).writeAsBytes(img.encodePng(image));
    final service = VisualTabAnalysisService(
      library: _AnalysisLibrary(directory.path),
      textRecognition: _PreparedCountingTextRecognition(),
    );

    final result = await service.analyze(
      const VisualStrip(
        id: 'strip',
        assetHash: 'strip',
        assetExtension: 'png',
        pixelWidth: 600,
        pixelHeight: 240,
      ),
      sourceStringCount: 4,
      preferPositionedPdf: false,
    );

    final lowStringTokens = result.systems.first.tokens
        .where((token) => token.isFretLike && token.stringIndex == 0)
        .toList();
    expect(lowStringTokens, hasLength(greaterThanOrEqualTo(4)));
    expect(lowStringTokens.map((token) => token.text), contains('12'));
  });

  test(
    'prepared raster OCR reaches sustains below the lowest string',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'music_tabbler_sustain_raster_analysis_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final image = img.decodePng(
        _tabFixture(
          background: img.ColorRgb8(255, 255, 255),
          foreground: img.ColorRgb8(0, 0, 0),
        ),
      )!;
      // The lowest string of the first fixture system is y=71. Songsterr-style
      // parenthesized sustains sit below it instead of being centred on it.
      img.drawString(
        image,
        '(0)',
        font: img.arial14,
        x: 100,
        y: 73,
        color: img.ColorRgb8(0, 0, 0),
      );
      // A separate shallow tie must not be promoted to another fret token.
      img.drawLine(
        image,
        x1: 210,
        y1: 75,
        x2: 224,
        y2: 82,
        color: img.ColorRgb8(0, 0, 0),
        thickness: 3,
      );
      img.drawLine(
        image,
        x1: 224,
        y1: 82,
        x2: 260,
        y2: 82,
        color: img.ColorRgb8(0, 0, 0),
        thickness: 2,
      );
      img.drawLine(
        image,
        x1: 260,
        y1: 82,
        x2: 274,
        y2: 75,
        color: img.ColorRgb8(0, 0, 0),
        thickness: 3,
      );
      final imagePath = '${directory.path}${Platform.pathSeparator}strip.png';
      await File(imagePath).writeAsBytes(img.encodePng(image));
      final service = VisualTabAnalysisService(
        library: _AnalysisLibrary(directory.path),
        textRecognition: const _NativeZeroRecognition(),
      );

      final result = await service.analyze(
        const VisualStrip(
          id: 'strip',
          assetHash: 'strip',
          assetExtension: 'png',
          pixelWidth: 600,
          pixelHeight: 240,
        ),
        sourceStringCount: 4,
        preferPositionedPdf: false,
      );

      final sustainedFrets = result.systems.first.tokens
          .where((token) => token.isFretLike && token.stringIndex == 0)
          .toList();
      expect(
        sustainedFrets,
        hasLength(1),
        reason: result.systems
            .map(
              (system) => system.tokens
                  .map(
                    (token) =>
                        '${token.text}:${token.kind.name}:${token.stringIndex}'
                        '@${token.rect.left.toStringAsFixed(3)},'
                        '${token.rect.top.toStringAsFixed(3)} '
                        '${token.rect.width.toStringAsFixed(3)}x'
                        '${token.rect.height.toStringAsFixed(3)}',
                  )
                  .join(','),
            )
            .join(' | '),
      );
    },
  );

  test(
    'compact four-string staff preserves distinct 0 9 and 12 glyphs',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'music_tabbler_compact_bass_staff_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final source = img.Image(width: 2412, height: 364);
      img.fill(source, color: img.ColorRgb8(255, 255, 255));
      const lines = [140, 176, 212, 248];
      for (final y in lines) {
        img.drawLine(
          source,
          x1: 40,
          y1: y,
          x2: 2360,
          y2: y,
          color: img.ColorRgb8(0, 0, 0),
        );
      }
      for (final x in [40, 800, 1600, 2360]) {
        img.drawLine(
          source,
          x1: x,
          y1: lines.first,
          x2: x,
          y2: lines.last,
          color: img.ColorRgb8(0, 0, 0),
        );
      }
      for (final (value, x) in [
        ('0', 240),
        ('12', 600),
        ('9', 1200),
        ('5', 1800),
      ]) {
        img.drawString(
          source,
          value,
          font: img.arial48,
          x: x,
          y: lines.last - 24,
          color: img.ColorRgb8(0, 0, 0),
        );
      }
      final image = img.copyResize(
        source,
        width: 1206,
        height: 182,
        interpolation: img.Interpolation.cubic,
      );
      await File(
        '${directory.path}${Platform.pathSeparator}strip.png',
      ).writeAsBytes(img.encodePng(image));
      final service = VisualTabAnalysisService(
        library: _AnalysisLibrary(directory.path),
        textRecognition: _PreparedCountingTextRecognition(),
      );
      final result = await service.analyze(
        const VisualStrip(
          id: 'strip',
          assetHash: 'strip',
          assetExtension: 'png',
          pixelWidth: 1206,
          pixelHeight: 182,
        ),
        sourceStringCount: 4,
        preferPositionedPdf: false,
      );
      final lowStringLabels = result.systems
          .expand((system) => system.tokens)
          .where((token) => token.enabled && token.stringIndex == 0)
          .map((token) => token.text)
          .toList();

      expect(lowStringLabels, containsAll(['0', '12', '9', '5']));
    },
  );
}

class _AnalysisLibrary implements ChartLibrary {
  _AnalysisLibrary(this.root);

  final String root;

  @override
  String assetPath(String hash, String extension) {
    return '$root${Platform.pathSeparator}$hash.$extension';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountingTextRecognition implements TextRecognitionService {
  var callCount = 0;

  @override
  Future<MetadataSuggestion> recognize(VisualStrip strip) async {
    callCount += 1;
    return const MetadataSuggestion();
  }
}

class _PreparedCountingTextRecognition
    implements TextRecognitionService, PreparedTextRecognitionService {
  var preparedCallCount = 0;

  @override
  Future<MetadataSuggestion> recognize(VisualStrip strip) async =>
      const MetadataSuggestion();

  @override
  Future<MetadataSuggestion> recognizePreparedImage(Uint8List bytes) async {
    preparedCallCount += 1;
    return const MetadataSuggestion();
  }
}

class _FailingPreparedTextRecognition
    implements TextRecognitionService, PreparedTextRecognitionService {
  const _FailingPreparedTextRecognition();

  @override
  Future<MetadataSuggestion> recognize(VisualStrip strip) async =>
      throw StateError('native OCR unavailable');

  @override
  Future<MetadataSuggestion> recognizePreparedImage(Uint8List bytes) async =>
      throw StateError('native OCR unavailable');
}

class _NativeOverrideRecognition
    implements TextRecognitionService, PreparedTextRecognitionService {
  const _NativeOverrideRecognition();

  @override
  Future<MetadataSuggestion> recognize(VisualStrip strip) async =>
      const MetadataSuggestion();

  @override
  Future<MetadataSuggestion> recognizePreparedImage(Uint8List bytes) async {
    final sheet = img.decodePng(bytes)!;
    final rows = sheet.height ~/ 96;
    final columns = sheet.width ~/ 128;
    return MetadataSuggestion(
      regions: [
        for (var row = 0; row < rows; row += 1)
          for (var column = 0; column < columns; column += 1)
            RecognizedTextRegion(
              text: '12',
              rect: NormalizedRect(
                (column + 0.4) / columns,
                (row + 0.4) / rows,
                (column + 0.6) / columns,
                (row + 0.6) / rows,
              ),
            ),
      ],
    );
  }
}

class _NativeZeroRecognition
    implements TextRecognitionService, PreparedTextRecognitionService {
  const _NativeZeroRecognition();

  @override
  Future<MetadataSuggestion> recognize(VisualStrip strip) async =>
      const MetadataSuggestion();

  @override
  Future<MetadataSuggestion> recognizePreparedImage(Uint8List bytes) async {
    final sheet = img.decodePng(bytes)!;
    final rows = sheet.height ~/ 96;
    final columns = sheet.width ~/ 128;
    return MetadataSuggestion(
      regions: [
        for (var row = 0; row < rows; row += 1)
          for (var column = 0; column < columns; column += 1)
            RecognizedTextRegion(
              text: '0',
              rect: NormalizedRect(
                (column + 0.4) / columns,
                (row + 0.4) / rows,
                (column + 0.6) / columns,
                (row + 0.6) / rows,
              ),
            ),
      ],
    );
  }
}

class _NativeThreeRecognition
    implements TextRecognitionService, PreparedTextRecognitionService {
  const _NativeThreeRecognition();

  @override
  Future<MetadataSuggestion> recognize(VisualStrip strip) async =>
      const MetadataSuggestion();

  @override
  Future<MetadataSuggestion> recognizePreparedImage(Uint8List bytes) async {
    final sheet = img.decodePng(bytes)!;
    final rows = sheet.height ~/ 96;
    final columns = sheet.width ~/ 128;
    return MetadataSuggestion(
      regions: [
        for (var row = 0; row < rows; row += 1)
          for (var column = 0; column < columns; column += 1)
            RecognizedTextRegion(
              text: '3',
              rect: NormalizedRect(
                (column + 0.4) / columns,
                (row + 0.4) / rows,
                (column + 0.6) / columns,
                (row + 0.6) / rows,
              ),
            ),
      ],
    );
  }
}

class _FirstNativeOneRecognition
    implements TextRecognitionService, PreparedTextRecognitionService {
  const _FirstNativeOneRecognition();

  @override
  Future<MetadataSuggestion> recognize(VisualStrip strip) async =>
      const MetadataSuggestion();

  @override
  Future<MetadataSuggestion> recognizePreparedImage(Uint8List bytes) async {
    final sheet = img.decodePng(bytes)!;
    final rows = sheet.height ~/ 96;
    return MetadataSuggestion(
      regions: [
        RecognizedTextRegion(
          text: '1',
          rect: NormalizedRect(0.4, 1.4 / rows, 0.6, 1.6 / rows),
        ),
      ],
    );
  }
}

Uint8List _tabFixture({
  required img.Color background,
  required img.Color foreground,
}) {
  final image = img.Image(width: 600, height: 240);
  img.fill(image, color: background);
  for (final top in [35, 145]) {
    for (var index = 0; index < 4; index += 1) {
      final y = top + index * 12;
      img.drawLine(
        image,
        x1: 18,
        y1: y,
        x2: 582,
        y2: y,
        color: foreground,
        thickness: 1,
      );
    }
    for (final x in [18, 200, 400, 582]) {
      img.drawLine(
        image,
        x1: x,
        y1: top,
        x2: x,
        y2: top + 36,
        color: foreground,
        thickness: 1,
      );
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _stringSystemFixture({required int stringCount}) {
  final image = img.Image(width: 1000, height: 240);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  const top = 50;
  const spacing = 16;
  for (var index = 0; index < stringCount; index += 1) {
    final y = top + index * spacing;
    img.drawLine(
      image,
      x1: 30,
      y1: y,
      x2: 970,
      y2: y,
      color: img.ColorRgb8(0, 0, 0),
    );
  }
  for (final x in [30, 500, 970]) {
    img.drawLine(
      image,
      x1: x,
      y1: top,
      x2: x,
      y2: top + spacing * (stringCount - 1),
      color: img.ColorRgb8(0, 0, 0),
    );
  }
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _notationColumnFixture({required int stringCount}) {
  const width = 1000;
  const top = 50;
  const spacing = 24;
  final height = top + spacing * (stringCount - 1) + 80;
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  final lines = [
    for (var index = 0; index < stringCount; index += 1) top + index * spacing,
  ];
  for (final y in lines) {
    img.drawLine(
      image,
      x1: 30,
      y1: y,
      x2: 970,
      y2: y,
      color: img.ColorRgb8(0, 0, 0),
    );
  }
  for (final x in [30, 500, 970]) {
    img.drawLine(
      image,
      x1: x,
      y1: lines.first,
      x2: x,
      y2: lines.last,
      color: img.ColorRgb8(0, 0, 0),
    );
  }
  void drawFret(String value, int x, int lineIndex) {
    img.drawString(
      image,
      value,
      font: img.arial24,
      x: x,
      y: lines[lineIndex] - 12,
      color: img.ColorRgb8(0, 0, 0),
    );
  }

  for (final lineIndex in [stringCount - 2, stringCount - 1]) {
    drawFret('1', 250, lineIndex);
  }
  for (final lineIndex in [stringCount - 3, stringCount - 2, stringCount - 1]) {
    drawFret('1', 350, lineIndex);
  }
  drawFret('1', 700, stringCount - 1);
  drawFret('3', 760, stringCount - 1);
  img.drawLine(
    image,
    x1: 712,
    y1: lines.last - 3,
    x2: 760,
    y2: lines.last - 1,
    color: img.ColorRgb8(0, 0, 0),
  );
  return Uint8List.fromList(img.encodePng(image));
}

// A tiny crop from the reported Songsterr source. It contains one open-string
// zero and its adjacent string segment, preserving the typography that was
// previously confused with an eight without retaining any song content.
const _panBar31SlideFixture =
    'iVBORw0KGgoAAAANSUhEUgAAAjAAAAC+CAIAAACktqK5AAAABGdBTUEAALGPC/xhBQAAACBjSFJNAAB6JgAAgIQAAPoAAACA6AAAdTAAAOpgAAA6mAAAF3CculE8AAAAeGVYSWZNTQAqAAAACAAEARoABQAAAAEAAAA+ARsABQAAAAEAAABGASgAAwAAAAEAAgAAh2kABAAAAAEAAABOAAAAAAAAAJAAAAABAAAAkAAAAAEAA6ABAAMAAAABAAEAAKACAAQAAAABAAACMKADAAQAAAABAAAAvgAAAAACuLHdAAAACXBIWXMAABYlAAAWJQFJUiTwAAACnWlUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iWE1QIENvcmUgNi4wLjAiPgogICA8cmRmOlJERiB4bWxuczpyZGY9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkvMDIvMjItcmRmLXN5bnRheC1ucyMiPgogICAgICA8cmRmOkRlc2NyaXB0aW9uIHJkZjphYm91dD0iIgogICAgICAgICAgICB4bWxuczp0aWZmPSJodHRwOi8vbnMuYWRvYmUuY29tL3RpZmYvMS4wLyIKICAgICAgICAgICAgeG1sbnM6ZXhpZj0iaHR0cDovL25zLmFkb2JlLmNvbS9leGlmLzEuMC8iPgogICAgICAgICA8dGlmZjpYUmVzb2x1dGlvbj4xNDQ8L3RpZmY6WFJlc29sdXRpb24+CiAgICAgICAgIDx0aWZmOllSZXNvbHV0aW9uPjE0NDwvdGlmZjpZUmVzb2x1dGlvbj4KICAgICAgICAgPHRpZmY6UmVzb2x1dGlvblVuaXQ+MjwvdGlmZjpSZXNvbHV0aW9uVW5pdD4KICAgICAgICAgPGV4aWY6UGl4ZWxZRGltZW5zaW9uPjIzMDwvZXhpZjpQaXhlbFlEaW1lbnNpb24+CiAgICAgICAgIDxleGlmOlBpeGVsWERpbWVuc2lvbj4xMTUwPC9leGlmOlBpeGVsWERpbWVuc2lvbj4KICAgICAgICAgPGV4aWY6Q29sb3JTcGFjZT4xPC9leGlmOkNvbG9yU3BhY2U+CiAgICAgIDwvcmRmOkRlc2NyaXB0aW9uPgogICA8L3JkZjpSREY+CjwveDp4bXBtZXRhPgppl0mZAAAmxElEQVR4Ae2defhVRf3H4Qsimv4EEkHREJfUTCVERVyAzKXMrRI1xURNCssl10fFpezRFsU1olIsNFEqs8THIlNBLbfCDU1y+aYYLiBuuLD9XjI+43TO/V7ucs7MuXPe94/7zJk7Zz7zec255zPLZ2Y6LdenaQJ33nln586dr7zyynRO5qfHH388/RO3jBw50sRPmzaNyylTppjLc889d5111jFhsuWn9O15xGy55ZaIrivnefPm7bbbboMHDz7ooIO6dOlCUe2nra3t0EMP3XDDDW2MCWy//fZbbLFFInKrrbbae++9E5Hdu3fPKdsHH3ywLjWVWAREwAOBTh5kSESrEGjAILmqzZo1y7U0xkJjsbBA1tLsv//+b7/99sKFC4866igslonfbLPNFixYQFYTJ07s1q2biezXr9+TTz5JZE7ZuiVXWAREoAgEZJCKUAtFKcP999//7LPPNlOauXPn9u3bt1OnTgceeKDNB/NDFwozM3z4cBtJYNy4cUR27dr1kUcesfGXXXYZtxNP59JG5pStzV8BERCBIhD4YCyI/78+IpAVgdmzZ0+ePPnUU0/t2bOnzfO999679NJLDzvssPXWW89G8uxhfoYMGbLDDjvYSAI333wzHabRo0e7kTll64pQWAREICwBGaSw/CVdBERABETgQwJtIiECIiACIiACRSAgg1SEWlAZREAEREAEOskg6SEQAREQAREoBAEZpEJUgwohAiIgAiIgg6RnQAREQAREoBAEZJAKUQ0qhAiIgAiIgAySngEREAEREIFCEOhaiFJ06rRo0aL77rtv6dKl2267rbug0hTv6aefZqXkdtttV5DSqhgiIAIiIAKZEyjEwti33nqL5fpz5sxZtmzZWmutdc8997C5mavqjjvuuPnmm0+aNMmNVFgEREAERCAmAoUYsmOb5z59+syfP58NZtgAm11nLOLXX3+dXTjpPNkYBURABERABKIkEN4g0T3ac889L7jggjXWWIPtn9kN+oEHHjCs77rrrnXXXff999/XYF2UD5+UEgEREAGXQPg5JOzQGWecYct03XXXDR061Fz26tXr3nvvHThw4IgRI2wCBURABERABKIkEN4gWaznnHPOVVdd9cYbb8ycOdNEcmib/VUBERABERCBuAmEH7KzfMeMGTNjxozjjjuOKaWXXnrJxisgAiIgAiJQBgIFMkiclLPRRhudf/75ixcvvuaaa8pAXzqKgAiIgAhYAuENUnt7+9FHH82ZobZMzCqxIMleKiACIiACIlAGAuHnkHr37n377be//PLLU6dOXXXVVVlshN/dqFGjykBfOoqACIiACFgC4Q3S6quvPn369OHDh/fr169z5844NVx//fUbbLCBLaICIiACIiACZSBQiJ0aAM2qWDwalixZMmjQoI033jiB/uGHH+7evXti+4ZEGl2KgAiIgAi0NIGiGKSWhqjCi4AIiIAINE8gvFND8zooBxEQAREQgQgIyCBFUIlSQQREQARiICCDFEMtSgcREAERiICADFIElSgVREAERCAGAjJIMdSidBABERCBCAjIIEVQiVJBBERABGIgIIMUQy1KBxEQARGIgECYnRomTJgQATupIAIiIAIikCGBMAtj2SKIz/Lly/lGmbwDeeefVsGbRG+CrI4RS4xYNf/VJ5gZvtzKAzNMD4mt6h566CH+JPqIgAiIgAiUkwAHgnPUw+zZs636YQxSly5d2OTbFkIBERABERCBshHo0aNHW1ubawvk1FC2Z0D6ioAIiEBBCcggFbRiVCwREAERKBsBGaSy1bj0FQEREIGCEpBBKmjFqFgiIAIiUDYCMkhlq3HpKwIiIAIFJSCDVNCKUbFEQAREoGwEZJDKVuPSVwREQAQKSkAGqaAVo2KJgAiIQNkIyCCVrcalrwiIgAgUlIAMUkErRsUSAREQgbIRkEEqW41LXxEQAREoKAEZpIJWjIolAiIgAmUjEGZz1TfffFNHIpXtUZO+IiACIuASeOqpp9555x3XFoQ5D2m11VYbMmSIWzKFRUAEREAESkVg4cKFnD0xdOhQq3UYgzRgwIBnn33WFkIBERABERCBshG46667Ro4c+dJLL1nFNYdkUSggAiIgAiIQkoAMUkj6ki0CIiACImAJyCBZFAqIgAiIgAiEJCCDFJK+ZIuACIiACFgCMkgWhQIiIAIiIAIhCcgghaQv2SIgAiIgApaADJJFoYAIiIAIiEBIAjJIIelLtgiIgAiIgCUgg2RRKCACIiACIhCSgAxSSPqSLQIiIAIiYAnIIFkUCoiACIiACIQkIIMUkr5ki4AIiIAIWAIySBaFAiIgAiIgAiEJhDkP6dVXXz3yyCOXL1/euXNntM87kHf+aRW8SfQmyOoYscSIVfNffYKZ4cstVpjs883ZeKNHj4aV0TGMQVqyZImOn+AdoY8IiIAIlJYA5yEtXbr0ueeeswR0HpJFoYAIiIAIiIA/AjoPyR9rSRIBERABEaiLgJwa6sKlxCIgAiIgAnkRkEHKi6zyFQEREAERqIuADFJduJRYBERABEQgLwIySHmRVb4iIAIiIAJ1EZBBqguXEouACIiACORFQAYpL7LKVwREQAREoC4CMkh14VJiERABERCBvAjIIOVFVvmKgAiIgAjURUAGqS5cSiwCIiACIpAXARmkvMgqXxEQAREQgboIyCDVhUuJRUAEREAE8iIQZrfvvLRRviLQggQWL178+uuvcybLK6+8QuCtt9567bXX5s+fz0bIfC9btox41DLh999/nz2SrZaEud1euoFVVlmlR48eJqatrW3ttdcmTODjH/84gd69e5twly5diOnZs+caa6yx1lprEU9KAtzu5qawCHggEGa379VXX33IkCEe1JMIESgmAczMggULMCd8sEAFLCT2CXvGp1evXpiuApZQRWp1Ajz8jz/++E477WQVCdNDolHWv39/WwgFRCAyAtibOXPmPProo2+//TaqdXTAWsX4/1vxoZuCGVhnnXW4nXDXrln+VTmQjA4ZOb/88ssUlfAbKz7umXKYSQ5Pe+GFF6qUn+Jtvvnm/JdlsaCkT70EVl111SeeeMK1BWF6SAMGDNABffVWntIXmcCiRYtmzZr1z3/+8/7776fR9+STTxLjFph3fb9+/XiD8yGAjWGgjP4H33RBGCgzPRKMkXuX5zBWyfTYGCSkA8cgIZfz5s0jwOGe//3vf1988UWsF3bULRgDHgMHDtxqq60+/elP77zzzgRkn1w+CndEIH0eUpbNro6kKl4EoiTA5M3tt99+xx133HPPPQ888ICZy8HwrL/++tttt91mm21Gw2uDDTbYeOON11tvvb59+xZ/VsZ0zqpXFmrSbeLz/PPPP/3008888wwnfs6ePfvee+81N3bv3n3QoEGMw4wYMWK33XYrvtbV9dWvPgmoh+STtmRFQoDew4QJEy677DJ6EmbYbaONNtpnn32YGd19993p8USiZz1qYKIwzLfddtstt9xCj8pgoed33HHHffOb3ywnk3r4lTFtuockg1TG50A6N0ygvb39yiuv/OlPf8oU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lxsnZfTp04f6sh8u2baOLVYPPvhgItlrjcOc2J+aTV1xAXc3K8INj72FMiGfSSaUtno+bHfA7nH0+WBlUoYxSGYvO0tcAREQAREQgYoEqix9YZFsS+/5nV6HJKeGis+AIkVABESgKAToPZiipANFKWJG5Qgzh5RR4ZWNCIiACERO4H82w+7UiaNNOROdWQ92GY9vCxsZpMifZqknAiLQ0gTYts4tP5NMXLKjdCLeTdO6YRmk1q07lVwERKB0BHbYYQeOxDWHtcenvAxSfHUqjURABKIlMGrFJ1b15NQQa81KLxEQARFoMQIySC1WYSquCIiACMRKQAYp1pqVXiIgAiLQYgRkkFqswlRcERABEYiVgAxSrDUrvURABESgxQjIILVYham4IiACIhArARmkWGtWeomACIhAixEIsw5pyZIl7e3tLYZKxRUBERABEciOwLx585YuXeragjC7fVfZvzY7ZZWTCIiACIhAKxEIY5Cee+45ewAGtKqfmdHYsSLuXXnnn1bBm0RvgqyOEUuMWDX/1SeY7ivI8m8sUB6YYQwStaKPCIiACIiACLgE5NTg0lBYBERABEQgGAEZpGDoJVgEREAERMAlIIPk0lBYBERABEQgGAEZpGDoJVgEREAERMAlIIPk0lBYBERABEQgGAEZpGDoJVgEREAERMAlIIPk0lBYBERABEQgGAEZpGDoJVgEREAERMAlIIPk0lBYBERABEQgGAEZpGDoJVgEREAERMAlIIPk0lBYBERABEQgGAEZpGDoJVgEREAERMAlIIPk0lBYBERABEQgGAEZpGDoJVgEREAERMAlEK1BevHFFydNmuSqWoQwpZowYQLfngszc8XHs9BQyuakpjeG7777Lg/Jm2++mZMiiWwRhDiEJuLzuIySIUpde+21eeBK5GkejMceeywRH9NltAZpzpw5p59+etGqilKNHTuWb88Fu2HFx7PQUMrmpKY3hliIY489dv78+TkpksgWQYjzY/+iZIhS48aNS1DN45I64u0xY8aMPDIvSJ7RGqSC8E0Xw5wjmY6PMqZUymZbg97QeROULZ9acotPtfg0StSjDFICiC5FQAREQATCEJBB8s19+fLlvkWGk1cqZbPF7A2dN0HZ8qklt/hUi0+jRD3KICWA5H4ZfafbJVgqZV3Fmw97Q+dNUPNM6s0hPtXi0yhRpzJICSC6FAEREAERCENABsk39+g73S7QUinrKt582Bs6b4KaZ1JvDvGpFp9GiTqVQUoAyf0y+k63S7BUyrqKNx/2hs6boOaZ1JtDfKrFp1GiTmWQEkB0KQIiIAIiEIaADJJv7tF3ul2gpVLWVbz5sDd03gQ1z6TeHOJTLT6NEnUqg5QAkvtl9J1ul2CplHUVbz7sDZ03Qc0zqTeH+FSLT6NEncogJYDoUgREQAREIAwBGSTf3KPvdLtAS6Wsq3jzYW/ovAlqnkm9OcSnWnwaJepUBikBJPfL6DvdLsFSKesq3nzYGzpvgppnUm8O8akWn0aJOu2auNZl3gRo4xxyyCHdu3cnYB6vZgI13rtgwYJRo0blrVo6f4qXjmzdmMmTJ0+bNq35WoOAqbiK1bds2TIS7LzzzqussopNmVUgLXHx4sVkPnjw4La2trxV4zlEVrYMLRlXtVwZJiSyXXqvXr2I9PBBRw9SAoqQQfINn//8vHnzfEsNJM+84AIJz14s+//zyT7fSjnOnTu3UnRecc8//3xeWafyjY+hN4MU2R8q9Wh00pBdmoliREAEREAEAhCQQfIN3Xa6MwnUlYlvVVcMTPkXmqvEuoCvNPFKE6BLtmmyza1K8bwJsmUIKDHXR87N3OroRsYU1pCd79qk0z1+/PiBAwf6FHzJJZf4FGdlRTbCsN9++51wwglWu5wCCxcuPOCAA6ZMmdK3b9+cRLjZMoDMpOZNN93Uo0cPNz6PsHkOI2OIUrNmzcoDVzrPyP5QaQVlkNJMco/BGg0bNix3MY6AqVOnOlcKNkigX79+HirulVdeoXxDhgzp379/gwWt57b29naSDx06tHfv3vXc10ha8xxGxhClvBmkRqC31D0xG6SlS5eaP1txaoTWKJ1uvj0XjGnkNddc0z+HyEYYwOih4vDaoqZeeOEFP/VlBOHUsGjRorwlGneGyBh689GgdiL7Q6Wft5gNEj6mAwYMSOscNoZONyMk/sswduxY/0IjG2HA7ZuPH4y77LKLH0FGCm7f3sTFx9BPX5YKiuwPlX7k5NSQZqIYERABERCBAAQiN0imh2v7ud4CxRTk//myHPyLzkmi1SiTQCaZoGnt+dSesq5s04m9CbKiA0qkDH4+Vkc/4vxLiXbIDpchD3On/iusYYmbbrppw/c2diNVMHz4cA++W40Vr967AKgnql5oJUnvxx+yW7du/KHwrImYaufoTW7ElSfVREAERCAmApEP2cVUVdJFBERABOImIIMUd/1KOxEQARFoGQL/Dxbh4429hZ58AAAAAElFTkSuQmCC';

const _panThreeStringSustainColumn =
    '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';

const _songsterrZeroGlyph =
    'iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAAAXNSR0IArs4c6QAAAERlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAGKADAAQAAAABAAAAGAAAAADiNXWtAAABtklEQVRIDe1TOa4CMQz1jD5USFCwVRyBnQJoKUGCeq4CgtNQcQgKShpoEesNkFgktvzYEtbAmDAUdFiK5uX52W/kJJbSAV8M+4u9qfXP4O2Evz6iP9Mv7HY76Pf7MBqNSFatVsFxHAiFQqayxxxeUyk2m43KZDJ4hR9WOp1W6/VaKhE5EFlNNhoNblwoFFSxWOR9vV5/VebhRYPFYqEsy6KG5XJZnU4nWpVKhTjMzedzTzOJEA95MBigMc2y1WpBIBCg1Ww2icMcavyEaKD/jmv1OTDW82e8XC4Zm4BooA+Ra5LJJONEIsF4tVoxNgHxmu73e7FGz5754/HI2A2u1ysMh0OmRAN3I1Y+gVea8/kMtVqN1aJBPB5nweVyEXEsFmPeDYLBIIzHY6ZEg1QqxYLZbAb5fJ72iO/h1tw5/Nq2DfrdMCUeci6XY8FkMhFxNptl3gikx3E4HFQkEqFHFY1GlTZR0+lUIdbNKIcaPyG+ZCzsdDrUDBs+r3a77ac3aV4a3G431ev1lH7FbIC42+0qzPkNC4WmGW63W7oVKCuVShAOh01yT+6tgafiQ0K8RR/2MMr/AXcEKrciD6DzAAAAAElFTkSuQmCC';

// A compact crop of an eight-string stacked-chord pattern from the reported
// source. It retains only repeated fret threes and the staff geometry needed
// to characterize disagreement between native OCR and the fallback classifier.
const _eightStringRepeatedOnes =
    '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';

const _eightStringStackedThrees =
    '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';
