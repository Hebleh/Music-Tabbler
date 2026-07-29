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

  test('requires review for a component crossing the selected seam', () async {
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

    expect(
      () => VisualTabTransformService(library).apply(
        draft: draft,
        analyses: [
          _analysis(
            tokenText: '3',
            tokenString: 0,
            riskSide: VisualConnectedComponentSide.unresolved,
          ),
        ],
        configuration: configuration,
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('connected notation'),
        ),
      ),
    );

    final reviewed = await VisualTabTransformService(library).apply(
      draft: draft,
      analyses: [
        _analysis(
          tokenText: '3',
          tokenString: 0,
          riskSide: VisualConnectedComponentSide.lower,
        ),
      ],
      configuration: configuration,
    );
    expect(reviewed.strips, isNotEmpty);
  });
}

VisualTabAnalysis _analysis({
  required String tokenText,
  required int tokenString,
  bool includeDeadNote = false,
  VisualConnectedComponentSide? riskSide,
}) {
  return VisualTabAnalysis(
    stripId: 'source-strip',
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
            id: 'fret',
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
