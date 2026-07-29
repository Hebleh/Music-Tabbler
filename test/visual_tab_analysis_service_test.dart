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

    test('flags a non-bar component crossing a string insertion gap', () {
      final image = img.decodePng(
        _tabFixture(
          background: img.ColorRgb8(255, 255, 255),
          foreground: img.ColorRgb8(0, 0, 0),
        ),
      )!;
      img.drawLine(
        image,
        x1: 300,
        y1: 47,
        x2: 300,
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
    expect(deadNote.kind, VisualTabTokenKind.deadNote);
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
