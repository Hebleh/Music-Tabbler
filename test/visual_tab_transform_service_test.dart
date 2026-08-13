import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:music_tabbler/application/visual_tab_transform_service.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';
import 'package:music_tabbler/domain/visual_tab_transform_models.dart';
import 'package:music_tabbler/infrastructure/local_library.dart';

void main() {
  late Directory root;
  late LocalLibrary library;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('visual-transform-');
    library = await LocalLibrary.forTesting(root);
  });

  tearDown(() {
    library.close();
    root.deleteSync(recursive: true);
  });

  test(
    'applies one-string insertion and restores immutable base strip',
    () async {
      final fixture = _fourStringFixture();
      final asset = await library.storeAsset(fixture, 'png');
      final now = DateTime.utc(2026, 7, 28);
      final sourceStrip = VisualStrip(
        id: 'source-strip',
        assetHash: asset.hash,
        assetExtension: 'png',
        pixelWidth: 600,
        pixelHeight: 120,
      );
      final draft = VisualChartDraft(
        id: 'chart',
        title: 'Motion Sickness fixture',
        artist: 'Fixture',
        createdAt: now,
        updatedAt: now,
        strips: [sourceStrip],
      );
      final analysis = _analysis(
        tokenText: '(9)',
        tokenString: 0,
        includeDeadNote: true,
      );
      final configuration = VisualTabTransformConfiguration(
        sourceLabels: const ['D', 'A', 'D', 'G'],
        sourceOpenMidis: const [38, 45, 50, 55],
        sourceCapo: 0,
        targetLabels: const ['B', 'E', 'A', 'D', 'G'],
        targetOpenMidis: const [35, 40, 45, 50, 55],
        targetCapo: 0,
        globalPitchChange: 0,
        routes: const [
          VisualStringRoute(sourceString: 0, targetString: 0, fretOffset: 3),
          VisualStringRoute(sourceString: 1, targetString: 2, fretOffset: 0),
          VisualStringRoute(sourceString: 2, targetString: 3, fretOffset: 0),
          VisualStringRoute(sourceString: 3, targetString: 4, fretOffset: 0),
        ],
      );

      final transformed = await VisualTabTransformService(
        library,
      ).apply(draft: draft, analyses: [analysis], configuration: configuration);

      expect(transformed.visualTabTransform, isNotNull);
      expect(
        transformed.visualTabTransform!.baseStrips.single.id,
        'source-strip',
      );
      expect(transformed.strips.single.pixelHeight, greaterThan(75));
      final outputBytes = await File(
        library.assetPath(
          transformed.strips.single.assetHash,
          transformed.strips.single.assetExtension,
        ),
      ).readAsBytes();
      expect(_longHorizontalInkRows(outputBytes), hasLength(5));
      expect(
        _darkPixelsInRect(outputBytes, left: 0, top: 0, right: 20, bottom: 90),
        greaterThan(0),
        reason:
            'The first transformed system should show target tuning labels.',
      );
      expect(
        _redPixelsInRect(outputBytes, left: 0, top: 0, right: 60, bottom: 90),
        0,
        reason: 'Source tuning-label ink should be cleared before relabeling.',
      );
      final restored = VisualTabTransformService(library).remove(transformed);
      expect(restored.visualTabTransform, isNull);
      expect(restored.strips.single.id, 'source-strip');
    },
  );

  test(
    'manually added review tokens use the canonical transform path',
    () async {
      final fixture = _fourStringFixture();
      final asset = await library.storeAsset(fixture, 'png');
      final now = DateTime.utc(2026, 8, 13);
      VisualChartDraft draft(String id) => VisualChartDraft(
        id: id,
        title: 'Manual token transform',
        artist: '',
        createdAt: now,
        updatedAt: now,
        strips: [
          VisualStrip(
            id: 'source-strip',
            assetHash: asset.hash,
            assetExtension: 'png',
            pixelWidth: 600,
            pixelHeight: 120,
          ),
        ],
      );
      final service = VisualTabTransformService(library);
      final expected = await service.apply(
        draft: draft('detected-token'),
        analyses: [_analysis(tokenText: '7', tokenString: 2)],
        configuration: _dropDToFiveStringConfiguration(),
      );
      final manual = await service.apply(
        draft: draft('manual-token'),
        analyses: [
          _analysis(
            tokenId: 'review_manual_token',
            tokenText: '7',
            tokenString: 2,
          ),
        ],
        configuration: _dropDToFiveStringConfiguration(),
      );

      expect(manual.strips.single.assetHash, expected.strips.single.assetHash);
      final storedAnalysis = VisualTabAnalysis.fromJson(
        manual.visualTabTransform!.analyses.single,
      );
      expect(
        storedAnalysis.systems.single.tokens.single.id,
        'review_manual_token',
      );
      expect(storedAnalysis.systems.single.tokens.single.stringIndex, 2);
    },
  );

  test('identity transform renders a manually drawn missing token', () async {
    final fixture = _fourStringFixture();
    final asset = await library.storeAsset(fixture, 'png');
    final now = DateTime.utc(2026, 8, 13);
    final draft = VisualChartDraft(
      id: 'manual-identity-token',
      title: 'Manual identity token',
      artist: '',
      createdAt: now,
      updatedAt: now,
      strips: [
        VisualStrip(
          id: 'source-strip',
          assetHash: asset.hash,
          assetExtension: 'png',
          pixelWidth: 600,
          pixelHeight: 120,
        ),
      ],
    );
    VisualTabAnalysis analysis({required bool sourceGlyphMatchesToken}) =>
        VisualTabAnalysis(
          stripId: 'source-strip',
          sourceType: VisualTabSourceType.rasterOcr,
          systems: [
            VisualTabSystem(
              id: 'system',
              rect: const NormalizedRect(0, 0.12, 1, 0.72),
              stringLines: const [0.22, 0.34, 0.46, 0.58],
              barLines: const [0.04, 0.96],
              tokens: [
                VisualTabToken(
                  id: 'review_manual_token',
                  text: '7',
                  rect: const NormalizedRect(0.25, 0.55, 0.30, 0.61),
                  kind: VisualTabTokenKind.fret,
                  stringIndex: 0,
                  sourceGlyphMatchesToken: sourceGlyphMatchesToken,
                ),
              ],
            ),
          ],
        );
    final configuration = VisualTabTransformConfiguration(
      sourceLabels: const ['D', 'A', 'D', 'G'],
      sourceOpenMidis: const [38, 45, 50, 55],
      sourceCapo: 0,
      targetLabels: const ['D', 'A', 'D', 'G'],
      targetOpenMidis: const [38, 45, 50, 55],
      targetCapo: 0,
      globalPitchChange: 0,
      routes: const [
        VisualStringRoute(sourceString: 0, targetString: 0, fretOffset: 0),
        VisualStringRoute(sourceString: 1, targetString: 1, fretOffset: 0),
        VisualStringRoute(sourceString: 2, targetString: 2, fretOffset: 0),
        VisualStringRoute(sourceString: 3, targetString: 3, fretOffset: 0),
      ],
    );

    final transformed = await VisualTabTransformService(library).apply(
      draft: draft,
      analyses: [analysis(sourceGlyphMatchesToken: false)],
      configuration: configuration,
    );
    final sourceGlyphTransform = await VisualTabTransformService(library).apply(
      draft: draft,
      analyses: [analysis(sourceGlyphMatchesToken: true)],
      configuration: configuration,
    );
    final outputBytes = await File(
      library.assetPath(
        transformed.strips.single.assetHash,
        transformed.strips.single.assetExtension,
      ),
    ).readAsBytes();

    expect(
      transformed.strips.single.assetHash,
      isNot(sourceGlyphTransform.strips.single.assetHash),
      reason:
          'An identity route may preserve a detected source glyph, but a '
          'manually added token must produce new rendered ink.',
    );
    expect(
      _darkPixelsInRect(
        outputBytes,
        left: 140,
        top: 45,
        right: 190,
        bottom: 80,
      ),
      greaterThan(70),
      reason:
          'The reviewed token has no source glyph, so identity routing '
          'must still draw its value on the transformed row.',
    );
  });

  test('rejects transformed frets outside 0 to 36', () async {
    final fixture = _fourStringFixture();
    final asset = await library.storeAsset(fixture, 'png');
    final now = DateTime.utc(2026, 7, 28);
    final draft = VisualChartDraft(
      id: 'chart',
      title: 'Bounds',
      artist: '',
      createdAt: now,
      updatedAt: now,
      strips: [
        VisualStrip(
          id: 'source-strip',
          assetHash: asset.hash,
          assetExtension: 'png',
          pixelWidth: 600,
          pixelHeight: 120,
        ),
      ],
    );
    final configuration = VisualTabTransformConfiguration(
      sourceLabels: const ['E', 'A', 'D', 'G'],
      sourceOpenMidis: const [28, 33, 38, 43],
      sourceCapo: 0,
      targetLabels: const ['E', 'A', 'D', 'G'],
      targetOpenMidis: const [28, 33, 38, 43],
      targetCapo: 0,
      globalPitchChange: 1,
      routes: const [
        VisualStringRoute(sourceString: 0, targetString: 0, fretOffset: 1),
        VisualStringRoute(sourceString: 1, targetString: 1, fretOffset: 1),
        VisualStringRoute(sourceString: 2, targetString: 2, fretOffset: 1),
        VisualStringRoute(sourceString: 3, targetString: 3, fretOffset: 1),
      ],
    );

    expect(
      () => VisualTabTransformService(library).apply(
        draft: draft,
        analyses: [_analysis(tokenText: '36', tokenString: 0)],
        configuration: configuration,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'renders multiple added edge strings as complete bounded tab lines',
    () async {
      final fixture = _fourStringFixture();
      final asset = await library.storeAsset(fixture, 'png');
      final now = DateTime.utc(2026, 8, 11);
      final draft = VisualChartDraft(
        id: 'six-string-target',
        title: 'Guitar expansion',
        artist: '',
        createdAt: now,
        updatedAt: now,
        strips: [
          VisualStrip(
            id: 'source-strip',
            assetHash: asset.hash,
            assetExtension: 'png',
            pixelWidth: 600,
            pixelHeight: 120,
          ),
        ],
      );
      final configuration = VisualTabTransformConfiguration(
        sourceLabels: const ['E', 'A', 'D', 'G'],
        sourceOpenMidis: const [28, 33, 38, 43],
        sourceCapo: 0,
        targetLabels: const ['E', 'A', 'D', 'G', 'B', 'E'],
        targetOpenMidis: const [28, 33, 38, 43, 47, 52],
        targetCapo: 0,
        globalPitchChange: 0,
        routes: const [
          VisualStringRoute(sourceString: 0, targetString: 0, fretOffset: 0),
          VisualStringRoute(sourceString: 1, targetString: 1, fretOffset: 0),
          VisualStringRoute(sourceString: 2, targetString: 2, fretOffset: 0),
          VisualStringRoute(sourceString: 3, targetString: 3, fretOffset: 0),
        ],
      );

      final transformed = await VisualTabTransformService(library).apply(
        draft: draft,
        analyses: [_analysis(tokenText: '5', tokenString: 0)],
        configuration: configuration,
      );
      final outputBytes = await File(
        library.assetPath(
          transformed.strips.single.assetHash,
          transformed.strips.single.assetExtension,
        ),
      ).readAsBytes();
      expect(_longHorizontalInkRows(outputBytes), hasLength(6));
      final output = img.decodePng(outputBytes)!;
      final rows = _longHorizontalInkRows(outputBytes);
      for (final y in rows) {
        expect(_hasDarkPixel(output, y: y, left: 24, right: 50), isTrue);
        expect(_hasDarkPixel(output, y: y, left: 550, right: 577), isTrue);
        expect(_isDark(output.getPixel(5, y)), isFalse);
      }
    },
  );

  test('infers a seam component attached only to the lower string', () async {
    final fixture = _fourStringFixture();
    final asset = await library.storeAsset(fixture, 'png');
    final now = DateTime.utc(2026, 7, 28);
    final draft = VisualChartDraft(
      id: 'chart',
      title: 'Seam review',
      artist: '',
      createdAt: now,
      updatedAt: now,
      strips: [
        VisualStrip(
          id: 'source-strip',
          assetHash: asset.hash,
          assetExtension: 'png',
          pixelWidth: 600,
          pixelHeight: 120,
        ),
      ],
    );
    final configuration = VisualTabTransformConfiguration(
      sourceLabels: const ['D', 'A', 'D', 'G'],
      sourceOpenMidis: const [38, 45, 50, 55],
      sourceCapo: 0,
      targetLabels: const ['B', 'E', 'A', 'D', 'G'],
      targetOpenMidis: const [35, 40, 45, 50, 55],
      targetCapo: 0,
      globalPitchChange: 0,
      routes: const [
        VisualStringRoute(sourceString: 0, targetString: 0, fretOffset: 3),
        VisualStringRoute(sourceString: 1, targetString: 2, fretOffset: 0),
        VisualStringRoute(sourceString: 2, targetString: 3, fretOffset: 0),
        VisualStringRoute(sourceString: 3, targetString: 4, fretOffset: 0),
      ],
    );

    final reviewed = await VisualTabTransformService(library).apply(
      draft: draft,
      analyses: [
        _analysis(
          tokenText: '3',
          tokenString: 0,
          riskSide: VisualConnectedComponentSide.unresolved,
        ),
      ],
      configuration: configuration,
    );
    expect(reviewed.strips, isNotEmpty);
  });

  test(
    'still requires review when a seam component connects both strings',
    () async {
      final fixture = _fourStringFixture();
      final asset = await library.storeAsset(fixture, 'png');
      final now = DateTime.utc(2026, 7, 28);
      final source = _analysis(
        tokenText: '3',
        tokenString: 0,
        riskSide: VisualConnectedComponentSide.unresolved,
      );
      final system = source.systems.single;
      final ambiguous = source.copyWith(
        systems: [
          system.copyWith(
            tokens: [
              ...system.tokens,
              const VisualTabToken(
                id: 'upper-fret',
                text: '5',
                rect: NormalizedRect(0.45, 0.42, 0.49, 0.48),
                kind: VisualTabTokenKind.fret,
                stringIndex: 1,
              ),
            ],
          ),
        ],
      );
      final draft = VisualChartDraft(
        id: 'ambiguous-seam',
        title: 'Ambiguous seam',
        artist: '',
        createdAt: now,
        updatedAt: now,
        strips: [
          VisualStrip(
            id: 'source-strip',
            assetHash: asset.hash,
            assetExtension: 'png',
            pixelWidth: 600,
            pixelHeight: 120,
          ),
        ],
      );

      expect(
        () => VisualTabTransformService(library).apply(
          draft: draft,
          analyses: [ambiguous],
          configuration: _dropDToFiveStringConfiguration(),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('connected notation'),
          ),
        ),
      );
    },
  );

  test('preserves a source row explicitly reviewed as unchanged', () async {
    final fixture = _fourStringFixture();
    final asset = await library.storeAsset(fixture, 'png');
    final now = DateTime.utc(2026, 8, 1);
    final strips = [
      for (var page = 1; page <= 2; page += 1)
        VisualStrip(
          id: 'source-$page',
          assetHash: asset.hash,
          assetExtension: 'png',
          pixelWidth: 600,
          pixelHeight: 120,
          sourcePage: page,
        ),
    ];
    final draft = VisualChartDraft(
      id: 'chart',
      title: 'All pages required',
      artist: '',
      createdAt: now,
      updatedAt: now,
      strips: strips,
    );
    final configuration = _dropDToFiveStringConfiguration();

    final transformed = await VisualTabTransformService(library).apply(
      draft: draft,
      analyses: [
        _analysis(stripId: 'source-1', tokenText: '9', tokenString: 0),
        const VisualTabAnalysis(
          stripId: 'source-2',
          sourceType: VisualTabSourceType.rasterOcr,
          keepUnchanged: true,
        ),
      ],
      configuration: configuration,
    );

    expect(transformed.strips, hasLength(2));
    expect(transformed.strips.last.id, 'source-2');
    expect(
      transformed.visualTabTransform!.audit,
      contains(contains('source-2 unchanged')),
    );
  });

  test('transforms every reviewed PDF page in source order', () async {
    final fixture = _fourStringFixture();
    final asset = await library.storeAsset(fixture, 'png');
    final now = DateTime.utc(2026, 8, 1);
    final strips = [
      for (var page = 1; page <= 3; page += 1)
        VisualStrip(
          id: 'source-$page',
          assetHash: asset.hash,
          assetExtension: 'png',
          pixelWidth: 600,
          pixelHeight: 120,
          sourcePage: page,
        ),
    ];
    final draft = VisualChartDraft(
      id: 'chart',
      title: 'All pages',
      artist: '',
      createdAt: now,
      updatedAt: now,
      strips: strips,
    );

    final transformed = await VisualTabTransformService(library).apply(
      draft: draft,
      analyses: [
        for (var page = 1; page <= 3; page += 1)
          _analysis(
            stripId: 'source-$page',
            tokenText: page == 1 ? '9' : '5',
            tokenString: 0,
          ),
      ],
      configuration: _dropDToFiveStringConfiguration(),
    );

    expect(
      transformed.strips.map((strip) => strip.sourcePage),
      orderedEquals([1, 2, 3]),
    );
    expect(transformed.visualTabTransform!.baseStrips, hasLength(3));
    expect(transformed.visualTabTransform!.analyses, hasLength(3));
  });

  test('overlapping duplicate fret proposals are rendered only once', () async {
    final fixture = _fourStringFixture();
    final asset = await library.storeAsset(fixture, 'png');
    final now = DateTime.utc(2026, 8, 1);
    VisualChartDraft draft(String id) => VisualChartDraft(
      id: id,
      title: 'Duplicate proposals',
      artist: '',
      createdAt: now,
      updatedAt: now,
      strips: [
        VisualStrip(
          id: 'source-strip',
          assetHash: asset.hash,
          assetExtension: 'png',
          pixelWidth: 600,
          pixelHeight: 120,
        ),
      ],
    );
    final rawSingle = _analysis(tokenText: '(0)', tokenString: 0);
    final rawSystem = rawSingle.systems.single;
    final single = rawSingle.copyWith(
      systems: [
        rawSystem.copyWith(
          tokens: [
            rawSystem.tokens.single.copyWith(
              rect: const NormalizedRect(0.270, 0.550, 0.280, 0.610),
            ),
          ],
        ),
      ],
    );
    final duplicateSystem = single.systems.single;
    final duplicate = single.copyWith(
      systems: [
        duplicateSystem.copyWith(
          tokens: [
            ...duplicateSystem.tokens,
            duplicateSystem.tokens.single.copyWith(
              text: '3',
              rect: const NormalizedRect(0.281, 0.535, 0.291, 0.595),
            ),
          ],
        ),
      ],
    );

    final service = VisualTabTransformService(library);
    final expected = await service.apply(
      draft: draft('single'),
      analyses: [single],
      configuration: _dropDToFiveStringConfiguration(),
    );
    final actual = await service.apply(
      draft: draft('duplicate'),
      analyses: [duplicate],
      configuration: _dropDToFiveStringConfiguration(),
    );

    expect(actual.strips.single.assetHash, expected.strips.single.assetHash);
  });

  test('parenthesized sustain inherits the preceding fret', () async {
    final fixture = _fourStringFixtureWithNarrowSustain();
    final asset = await library.storeAsset(fixture, 'png');
    final now = DateTime.utc(2026, 8, 1);
    VisualChartDraft draft(String id) => VisualChartDraft(
      id: id,
      title: 'Sustain OCR repair',
      artist: '',
      createdAt: now,
      updatedAt: now,
      strips: [
        VisualStrip(
          id: 'source-strip',
          assetHash: asset.hash,
          assetExtension: 'png',
          pixelWidth: 600,
          pixelHeight: 120,
        ),
      ],
    );
    VisualTabAnalysis analysis(String sustainText) {
      final source = _analysis(tokenText: '0', tokenString: 0);
      final system = source.systems.single;
      return source.copyWith(
        systems: [
          system.copyWith(
            tokens: [
              system.tokens.single.copyWith(
                rect: const NormalizedRect(0.12, 0.55, 0.15, 0.61),
              ),
              VisualTabToken(
                id: 'sustain',
                text: sustainText,
                rect: const NormalizedRect(0.25, 0.55, 0.30, 0.61),
                kind: VisualTabTokenKind.fret,
                stringIndex: 0,
              ),
            ],
          ),
        ],
      );
    }

    final service = VisualTabTransformService(library);
    final expected = await service.apply(
      draft: draft('correct-sustain'),
      analyses: [analysis('(0)')],
      configuration: _dropDToFiveStringConfiguration(),
    );
    final repaired = await service.apply(
      draft: draft('misread-sustain'),
      analyses: [analysis('(3)')],
      configuration: _dropDToFiveStringConfiguration(),
    );

    expect(repaired.strips.single.assetHash, expected.strips.single.assetHash);
  });

  test('parenthesized sustain inherits across detected source rows', () async {
    final fixture = _fourStringFixtureWithNarrowSustain();
    final asset = await library.storeAsset(fixture, 'png');
    final now = DateTime.utc(2026, 8, 11);
    VisualChartDraft draft(String id) => VisualChartDraft(
      id: id,
      title: 'Cross-row sustain repair',
      artist: '',
      createdAt: now,
      updatedAt: now,
      strips: [
        VisualStrip(
          id: 'played-row',
          assetHash: asset.hash,
          assetExtension: 'png',
          pixelWidth: 600,
          pixelHeight: 120,
        ),
        VisualStrip(
          id: 'sustain-row',
          assetHash: asset.hash,
          assetExtension: 'png',
          pixelWidth: 600,
          pixelHeight: 120,
        ),
      ],
    );
    List<VisualTabAnalysis> analyses(String sustainText) => [
      _analysis(stripId: 'played-row', tokenText: '0', tokenString: 0),
      _analysis(stripId: 'sustain-row', tokenText: sustainText, tokenString: 0),
    ];

    final service = VisualTabTransformService(library);
    final expected = await service.apply(
      draft: draft('correct-cross-row-sustain'),
      analyses: analyses('(0)'),
      configuration: _dropDToFiveStringConfiguration(),
    );
    final repaired = await service.apply(
      draft: draft('misread-cross-row-sustain'),
      analyses: analyses('(10)'),
      configuration: _dropDToFiveStringConfiguration(),
    );

    expect(repaired.strips[1].assetHash, expected.strips[1].assetHash);
    final repairedAnalysis = VisualTabAnalysis.fromJson(
      repaired.visualTabTransform!.analyses[1],
    );
    expect(repairedAnalysis.systems.single.tokens.single.text, '(0)');
    expect(
      repaired.visualTabTransform!.audit,
      contains(
        'Resolved 1 parenthesized sustain fret(s) from the preceding played '
        'fret across source rows.',
      ),
    );
  });

  test('parenthesized sustain clears the complete source glyph', () async {
    final fixture = _fourStringFixtureWithNarrowSustain();
    final asset = await library.storeAsset(fixture, 'png');
    final now = DateTime.utc(2026, 8, 1);
    final draft = VisualChartDraft(
      id: 'narrow-sustain',
      title: 'Narrow sustain geometry',
      artist: '',
      createdAt: now,
      updatedAt: now,
      strips: [
        VisualStrip(
          id: 'source-strip',
          assetHash: asset.hash,
          assetExtension: 'png',
          pixelWidth: 600,
          pixelHeight: 120,
        ),
      ],
    );
    final source = _analysis(tokenText: '(0)', tokenString: 0);
    final system = source.systems.single;
    final narrowGeometry = source.copyWith(
      systems: [
        system.copyWith(
          tokens: [
            system.tokens.single.copyWith(
              rect: const NormalizedRect(0.27, 0.55, 0.28, 0.61),
            ),
          ],
        ),
      ],
    );

    final transformed = await VisualTabTransformService(library).apply(
      draft: draft,
      analyses: [narrowGeometry],
      configuration: _dropDToFiveStringConfiguration(),
    );
    final outputBytes = await File(
      library.assetPath(
        transformed.strips.single.assetHash,
        transformed.strips.single.assetExtension,
      ),
    ).readAsBytes();

    expect(
      _redPixelsInRect(
        outputBytes,
        left: 130,
        top: 35,
        right: 205,
        bottom: 100,
      ),
      lessThanOrEqualTo(2),
      reason:
          'No visible source parentheses or zero may remain before (3) is drawn.',
    );
  });
}

VisualTabTransformConfiguration _dropDToFiveStringConfiguration() {
  return VisualTabTransformConfiguration(
    sourceLabels: const ['D', 'A', 'D', 'G'],
    sourceOpenMidis: const [38, 45, 50, 55],
    sourceCapo: 0,
    targetLabels: const ['B', 'E', 'A', 'D', 'G'],
    targetOpenMidis: const [35, 40, 45, 50, 55],
    targetCapo: 0,
    globalPitchChange: 0,
    routes: const [
      VisualStringRoute(sourceString: 0, targetString: 0, fretOffset: 3),
      VisualStringRoute(sourceString: 1, targetString: 2, fretOffset: 0),
      VisualStringRoute(sourceString: 2, targetString: 3, fretOffset: 0),
      VisualStringRoute(sourceString: 3, targetString: 4, fretOffset: 0),
    ],
  );
}

VisualTabAnalysis _analysis({
  String stripId = 'source-strip',
  String tokenId = 'fret',
  required String tokenText,
  required int tokenString,
  bool includeDeadNote = false,
  VisualConnectedComponentSide? riskSide,
}) {
  return VisualTabAnalysis(
    stripId: stripId,
    sourceType: VisualTabSourceType.rasterOcr,
    systems: [
      VisualTabSystem(
        id: 'system',
        rect: const NormalizedRect(0, 0.12, 1, 0.72),
        stringLines: const [0.22, 0.34, 0.46, 0.58],
        barLines: const [0.04, 0.96],
        connectedNotationRisks: [
          if (riskSide != null)
            VisualConnectedNotationRisk(
              id: 'risk',
              rect: const NormalizedRect(0.50, 0.48, 0.54, 0.54),
              gapIndex: 2,
              side: riskSide,
            ),
        ],
        tokens: [
          VisualTabToken(
            id: tokenId,
            text: tokenText,
            rect: const NormalizedRect(0.25, 0.55, 0.30, 0.61),
            kind: VisualTabTokenKind.fret,
            stringIndex: tokenString,
          ),
          if (includeDeadNote)
            const VisualTabToken(
              id: 'dead',
              text: 'X',
              rect: NormalizedRect(0.45, 0.43, 0.49, 0.49),
              kind: VisualTabTokenKind.deadNote,
              stringIndex: 1,
            ),
        ],
      ),
    ],
  );
}

Uint8List _fourStringFixture() {
  final image = img.Image(width: 600, height: 120)
    ..clear(img.ColorRgb8(248, 248, 248));
  for (final y in [26, 41, 56, 71]) {
    img.drawLine(
      image,
      x1: 20,
      y1: y,
      x2: 580,
      y2: y,
      color: img.ColorRgb8(30, 30, 30),
    );
  }
  for (final x in [20, 580]) {
    img.drawLine(
      image,
      x1: x,
      y1: 26,
      x2: x,
      y2: 71,
      color: img.ColorRgb8(30, 30, 30),
    );
  }
  for (final (label, y) in [('G', 26), ('D', 41), ('A', 56), ('D', 71)]) {
    img.drawString(
      image,
      label,
      font: img.arial14,
      x: 32,
      y: y - 7,
      color: img.ColorRgb8(220, 20, 20),
    );
  }
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _fourStringFixtureWithNarrowSustain() {
  final image = img.decodePng(_fourStringFixture())!;
  img.fillRect(
    image,
    x1: 145,
    y1: 57,
    x2: 190,
    y2: 84,
    color: img.ColorRgb8(248, 248, 248),
  );
  img.drawString(
    image,
    '(0)',
    font: img.arial24,
    x: 150,
    y: 59,
    color: img.ColorRgb8(220, 20, 20),
  );
  return Uint8List.fromList(img.encodePng(image));
}

List<int> _longHorizontalInkRows(Uint8List bytes) {
  final image = img.decodePng(bytes)!;
  final rows = <int>[];
  var active = false;
  for (var y = 0; y < image.height; y += 1) {
    var dark = 0;
    for (var x = 0; x < image.width; x += 1) {
      final pixel = image.getPixel(x, y);
      if (pixel.r < 90 && pixel.g < 90 && pixel.b < 90) dark += 1;
    }
    final next = dark / image.width > 0.7;
    if (next && !active) rows.add(y);
    active = next;
  }
  return rows;
}

int _darkPixelsInRect(
  Uint8List bytes, {
  required int left,
  required int top,
  required int right,
  required int bottom,
}) {
  final image = img.decodePng(bytes)!;
  var count = 0;
  for (var y = top; y < bottom.clamp(0, image.height); y += 1) {
    for (var x = left; x < right.clamp(0, image.width); x += 1) {
      final pixel = image.getPixel(x, y);
      if (pixel.r < 90 && pixel.g < 90 && pixel.b < 90) count += 1;
    }
  }
  return count;
}

int _redPixelsInRect(
  Uint8List bytes, {
  required int left,
  required int top,
  required int right,
  required int bottom,
}) {
  final image = img.decodePng(bytes)!;
  var count = 0;
  for (var y = top; y < bottom.clamp(0, image.height); y += 1) {
    for (var x = left; x < right.clamp(0, image.width); x += 1) {
      final pixel = image.getPixel(x, y);
      if (pixel.r > 150 && pixel.g < 80 && pixel.b < 80) count += 1;
    }
  }
  return count;
}

bool _isDark(img.Pixel pixel) => pixel.r < 90 && pixel.g < 90 && pixel.b < 90;

bool _hasDarkPixel(
  img.Image image, {
  required int y,
  required int left,
  required int right,
}) {
  for (var x = left; x < right; x += 1) {
    if (_isDark(image.getPixel(x, y))) return true;
  }
  return false;
}
