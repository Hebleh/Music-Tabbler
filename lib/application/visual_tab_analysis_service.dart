import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../domain/visual_chart_models.dart';
import '../domain/visual_tab_transform_models.dart';
import 'service_contracts.dart';
import 'visual_image_processor.dart';

class VisualTabAnalysisService {
  VisualTabAnalysisService({
    required this.library,
    required this.textRecognition,
  });

  final ChartLibrary library;
  final TextRecognitionService textRecognition;
  final Map<String, Future<List<VisualTabTextCandidate>>> _positionedCache = {};
  final Map<String, Future<img.Image>> _geometryImageCache = {};
  static bool _pdfInitialized = false;

  Future<VisualTabAnalysis> analyze(
    VisualStrip strip, {
    required int sourceStringCount,
    bool preferPositionedPdf = true,
  }) async {
    if (sourceStringCount < 2 || sourceStringCount > 12) {
      throw const FormatException('Source tuning needs 2 to 12 strings.');
    }
    final deskewed = strip.deskewDegrees.abs() >= 0.0001;
    final geometry = deskewed
        ? detectVisualTabGeometry(
            const VisualImageProcessor().process(
              await File(
                library.assetPath(strip.assetHash, strip.assetExtension),
              ).readAsBytes(),
              strip.copyWith(
                treatment: VisualTreatment.original,
                lyricContrast: 1,
                highlights: const [],
              ),
            ),
            crop: const NormalizedRect.full(),
            expectedStringCount: sourceStringCount,
          )
        : detectVisualTabGeometryFromImage(
            await _geometryImageCache.putIfAbsent(
              '${strip.assetHash}.${strip.assetExtension}',
              () async => _decodeVisualTabImage(
                await File(
                  library.assetPath(strip.assetHash, strip.assetExtension),
                ).readAsBytes(),
              ),
            ),
            crop: strip.crop,
            expectedStringCount: sourceStringCount,
          );

    if (preferPositionedPdf &&
        !deskewed &&
        strip.sourceAssetHash != null &&
        strip.sourcePage != null) {
      final positioned = await _loadPositionedPdfCandidates(strip);
      final result = buildVisualTabAnalysis(
        stripId: strip.id,
        sourceType: VisualTabSourceType.positionedPdf,
        geometry: geometry,
        candidates: positioned,
      );
      if (result.systems.isNotEmpty && result.enabledFretTokenCount > 0) {
        final minimumUsefulTokens = math.max(4, result.systems.length * 2);
        if (result.enabledFretTokenCount < minimumUsefulTokens) {
          return result.copyWith(
            warnings: [
              ...result.warnings,
              'The positioned PDF contains too little usable fret text. '
                  'Use Raster / OCR in review for this row.',
            ],
          );
        }
        return result;
      }
      return result.copyWith(
        warnings: [
          ...result.warnings,
          'The positioned PDF contains no usable fret text for this row. '
              'Use Raster / OCR in review if the row contains tablature.',
        ],
      );
    }

    final candidates = await _recognizeRasterCandidates(
      strip,
      geometry: geometry,
      deskewed: deskewed,
    );
    return buildVisualTabAnalysis(
      stripId: strip.id,
      sourceType: VisualTabSourceType.rasterOcr,
      geometry: geometry,
      candidates: candidates,
    );
  }

  Future<List<VisualTabTextCandidate>> _recognizeRasterCandidates(
    VisualStrip strip, {
    required VisualTabGeometry geometry,
    required bool deskewed,
  }) async {
    if (deskewed || geometry.systems.isEmpty) {
      final recognized = await textRecognition.recognize(strip);
      return [
        for (final region in recognized.regions)
          VisualTabTextCandidate(text: region.text, rect: region.rect),
      ];
    }

    final candidates = <VisualTabTextCandidate>[];
    final preparedRecognizer = textRecognition is PreparedTextRecognitionService
        ? textRecognition as PreparedTextRecognitionService
        : null;
    final sourceImage = await _geometryImageCache.putIfAbsent(
      '${strip.assetHash}.${strip.assetExtension}',
      () async => _decodeVisualTabImage(
        await File(
          library.assetPath(strip.assetHash, strip.assetExtension),
        ).readAsBytes(),
      ),
    );
    for (final system in geometry.systems) {
      final spacing = _medianSpacing(system.stringLines);
      final localCrop = NormalizedRect(
        0,
        math.max(0, system.rect.top - spacing * 1.35),
        1,
        math.min(1, system.rect.bottom + spacing * 1.35),
      );
      final recognized = preparedRecognizer == null
          ? await textRecognition.recognize(
              strip.copyWith(
                crop: NormalizedRect(
                  strip.crop.left + localCrop.left * strip.crop.width,
                  strip.crop.top + localCrop.top * strip.crop.height,
                  strip.crop.left + localCrop.right * strip.crop.width,
                  strip.crop.top + localCrop.bottom * strip.crop.height,
                ).clamp(),
              ),
            )
          : await _recognizeTabGlyphCandidates(
              preparedRecognizer,
              _detectRasterGlyphCandidates(
                sourceImage,
                stripCrop: strip.crop,
                system: system,
              ),
            );
      for (final region in recognized.regions) {
        candidates.add(
          VisualTabTextCandidate(
            text: region.text,
            rect: preparedRecognizer == null
                ? NormalizedRect(
                    localCrop.left + region.rect.left * localCrop.width,
                    localCrop.top + region.rect.top * localCrop.height,
                    localCrop.left + region.rect.right * localCrop.width,
                    localCrop.top + region.rect.bottom * localCrop.height,
                  ).clamp()
                : region.rect,
            confidence: region.confidence,
          ),
        );
      }
    }
    return candidates;
  }

  Future<List<VisualTabTextCandidate>> _loadPositionedPdfCandidates(
    VisualStrip strip,
  ) async {
    final fullPage = await _positionedCache.putIfAbsent(
      '${strip.sourceAssetHash}:${strip.sourcePage}',
      () => _loadPositionedPdfPage(strip.sourceAssetHash!, strip.sourcePage!),
    );
    return [
      for (final candidate in fullPage)
        if (_assetRectToCropLocal(candidate.rect, strip.crop)
            case final localRect?)
          VisualTabTextCandidate(
            text: candidate.text,
            rect: localRect,
            confidence: candidate.confidence,
          ),
    ];
  }

  Future<List<VisualTabTextCandidate>> _loadPositionedPdfPage(
    String sourceAssetHash,
    int sourcePage,
  ) async {
    final path = library.assetPath(sourceAssetHash, 'pdf');
    if (!await File(path).exists()) return const [];
    if (!_pdfInitialized) {
      await pdfrxInitialize();
      _pdfInitialized = true;
    }
    final document = await PdfDocument.openFile(path);
    try {
      final pageIndex = sourcePage - 1;
      if (pageIndex < 0 || pageIndex >= document.pages.length) return const [];
      final page = document.pages[pageIndex];
      final text = await page.loadStructuredText();
      final candidates = <VisualTabTextCandidate>[];
      final tokenPattern = RegExp(r'\(\d{1,2}\)|\d{1,2}|[xX]');
      for (final fragment in text.fragments) {
        for (final match in tokenPattern.allMatches(fragment.text)) {
          final start = match.start.clamp(0, fragment.charRects.length);
          final end = match.end.clamp(start, fragment.charRects.length);
          if (start == end) continue;
          var bounds = fragment.charRects[start];
          for (var index = start + 1; index < end; index += 1) {
            bounds = bounds.merge(fragment.charRects[index]);
          }
          final fullRect = _pdfRectToNormalized(
            bounds.left,
            bounds.top,
            bounds.right,
            bounds.bottom,
            page.width,
            page.height,
          );
          candidates.add(
            VisualTabTextCandidate(text: match.group(0)!, rect: fullRect),
          );
        }
      }
      return candidates;
    } finally {
      document.dispose();
    }
  }
}

Future<MetadataSuggestion> _recognizeTabGlyphCandidates(
  PreparedTextRecognitionService recognizer,
  List<_RasterGlyphCandidate> candidates,
) async {
  if (candidates.isEmpty) return const MetadataSuggestion();
  const columns = 6;
  const tileWidth = 128;
  const tileHeight = 96;
  const glyphExtent = 64;
  final rows = (candidates.length / columns).ceil();
  final sheet = img.Image(
    width: columns * tileWidth,
    height: rows * tileHeight,
  );
  img.fill(sheet, color: img.ColorRgb8(255, 255, 255));
  for (var index = 0; index < candidates.length; index += 1) {
    final candidate = candidates[index];
    final scale = math.min(
      glyphExtent / math.max(1, candidate.image.width),
      glyphExtent / math.max(1, candidate.image.height),
    );
    final width = math.max(1, (candidate.image.width * scale).round());
    final height = math.max(1, (candidate.image.height * scale).round());
    final glyph = img.copyResize(
      candidate.image,
      width: width,
      height: height,
      interpolation: img.Interpolation.nearest,
    );
    final column = index % columns;
    final row = index ~/ columns;
    img.compositeImage(
      sheet,
      glyph,
      dstX: column * tileWidth + (tileWidth - width) ~/ 2,
      dstY: row * tileHeight + (tileHeight - height) ~/ 2,
      blend: img.BlendMode.direct,
    );
  }
  final recognized = await recognizer.recognizePreparedImage(
    Uint8List.fromList(img.encodePng(sheet, level: 2)),
  );
  final regions = <RecognizedTextRegion>[];
  final nativeLabels = <int, String>{};
  for (final region in recognized.regions) {
    final centerX = (region.rect.left + region.rect.right) / 2;
    final centerY = (region.rect.top + region.rect.bottom) / 2;
    final column = (centerX * columns).floor().clamp(0, columns - 1);
    final row = (centerY * rows).floor().clamp(0, rows - 1);
    final index = row * columns + column;
    if (index >= candidates.length || nativeLabels.containsKey(index)) continue;
    final match = RegExp(
      r'\(\d{1,2}\)|\d{1,2}|[xX]',
    ).firstMatch(region.text.trim());
    if (match == null) continue;
    nativeLabels[index] = match.group(0)!;
  }
  for (var index = 0; index < candidates.length; index += 1) {
    final classified = _classifyRasterGlyph(candidates[index].image);
    final nativeLabel = nativeLabels[index];
    if (classified == null && nativeLabel == null) continue;
    final agrees =
        classified != null &&
        nativeLabel != null &&
        classified.label.toUpperCase() == nativeLabel.toUpperCase();
    final label = agrees ? nativeLabel : classified?.label ?? nativeLabel!;
    final confidence = agrees
        ? math.max(0.82, classified.confidence)
        : classified?.confidence ?? 0.45;
    regions.add(
      RecognizedTextRegion(
        text: label,
        rect: candidates[index].rect,
        confidence: confidence,
      ),
    );
  }
  return MetadataSuggestion(regions: regions);
}

List<_RasterGlyphCandidate> _detectRasterGlyphCandidates(
  img.Image source, {
  required NormalizedRect stripCrop,
  required VisualTabSystemGeometry system,
}) {
  final left = (stripCrop.left * source.width).floor().clamp(
    0,
    source.width - 1,
  );
  final top = (stripCrop.top * source.height).floor().clamp(
    0,
    source.height - 1,
  );
  final right = (stripCrop.right * source.width).ceil().clamp(
    left + 1,
    source.width,
  );
  final bottom = (stripCrop.bottom * source.height).ceil().clamp(
    top + 1,
    source.height,
  );
  final image = img.copyCrop(
    source,
    x: left,
    y: top,
    width: right - left,
    height: bottom - top,
  );
  final background = _estimateBackgroundLuminance(image);
  final threshold = math.max(24.0, background < 110 ? 30.0 : 38.0);
  final spacingPixels =
      _medianSpacing(system.stringLines) * stripCrop.height * source.height;
  final halfBand = math.max(3, (spacingPixels * 0.58).round());
  final mergeGap = math.max(2, (spacingPixels * 0.34).round());
  final maximumWidth = math.max(8, (spacingPixels * 2.4).round());
  final barPixels = [
    for (final bar in system.barLines) (bar * image.width).round(),
  ];
  final contentLeft = barPixels.length >= 2 ? barPixels.first + 2 : 0;
  final contentRight = barPixels.length >= 2 ? barPixels.last - 2 : image.width;
  final candidates = <_RasterGlyphCandidate>[];

  for (final normalizedLine in system.stringLines) {
    final lineY = (normalizedLine * image.height).round();
    final bandTop = math.max(0, lineY - halfBand);
    final bandBottom = math.min(image.height, lineY + halfBand + 1);
    final occupiedColumns = <int>[];
    for (var x = 0; x < image.width; x += 1) {
      if (x < contentLeft || x > contentRight) continue;
      if (barPixels.any((bar) => (bar - x).abs() <= 1)) continue;
      var occupied = false;
      for (var y = bandTop; y < bandBottom; y += 1) {
        if ((y - lineY).abs() <= 1) continue;
        if ((_luminance(image.getPixel(x, y)) - background).abs() >=
            threshold) {
          occupied = true;
          break;
        }
      }
      if (occupied) occupiedColumns.add(x);
    }
    final clusters = _clusterCoordinatesWithGap(occupiedColumns, mergeGap);
    for (final cluster in clusters) {
      final glyphLeft = cluster.first;
      final glyphRight = cluster.last + 1;
      final glyphWidth = glyphRight - glyphLeft;
      if (glyphWidth > maximumWidth) continue;
      var inkTop = bandBottom;
      var inkBottom = bandTop;
      var inkPixels = 0;
      for (var y = bandTop; y < bandBottom; y += 1) {
        if ((y - lineY).abs() <= 1) continue;
        for (var x = glyphLeft; x < glyphRight; x += 1) {
          if ((_luminance(image.getPixel(x, y)) - background).abs() <
              threshold) {
            continue;
          }
          inkTop = math.min(inkTop, y);
          inkBottom = math.max(inkBottom, y + 1);
          inkPixels += 1;
        }
      }
      if (inkPixels < 3 ||
          inkBottom <= inkTop ||
          inkBottom - inkTop < spacingPixels * 0.24 ||
          inkTop <= bandTop ||
          inkBottom >= bandBottom) {
        continue;
      }
      final padding = math.max(2, (spacingPixels * 0.2).round());
      final patchLeft = math.max(0, glyphLeft - padding);
      final patchTop = math.max(0, inkTop - padding);
      final patchRight = math.min(image.width, glyphRight + padding);
      final patchBottom = math.min(image.height, inkBottom + padding);
      final patch = img.Image(
        width: patchRight - patchLeft,
        height: patchBottom - patchTop,
      );
      img.fill(patch, color: img.ColorRgb8(255, 255, 255));
      for (var y = patchTop; y < patchBottom; y += 1) {
        for (var x = patchLeft; x < patchRight; x += 1) {
          if ((y - lineY).abs() <= 1) continue;
          if ((_luminance(image.getPixel(x, y)) - background).abs() >=
              threshold) {
            patch.setPixel(x - patchLeft, y - patchTop, img.ColorRgb8(0, 0, 0));
          }
        }
      }
      candidates.add(
        _RasterGlyphCandidate(
          image: patch,
          rect: NormalizedRect(
            glyphLeft / image.width,
            inkTop / image.height,
            glyphRight / image.width,
            inkBottom / image.height,
          ).clamp(),
        ),
      );
    }
  }
  return candidates;
}

class _RasterGlyphCandidate {
  const _RasterGlyphCandidate({required this.image, required this.rect});

  final img.Image image;
  final NormalizedRect rect;
}

class _RasterGlyphTemplate {
  const _RasterGlyphTemplate({
    required this.label,
    required this.mask,
    required this.aspectRatio,
  });

  final String label;
  final List<bool> mask;
  final double aspectRatio;
}

List<_RasterGlyphTemplate>? _rasterGlyphTemplates;

({String label, double confidence})? _classifyRasterGlyph(img.Image image) {
  final normalized = _normalizeRasterGlyph(image);
  if (normalized == null) return null;
  final templates = _rasterGlyphTemplates ??= _buildRasterGlyphTemplates();
  String? bestLabel;
  var bestScore = 0.0;
  var secondScore = 0.0;
  for (final template in templates) {
    final score =
        _glyphDice(normalized.mask, template.mask) -
        (normalized.aspectRatio - template.aspectRatio).abs() * 0.08;
    if (score > bestScore) {
      if (template.label != bestLabel) secondScore = bestScore;
      bestScore = score;
      bestLabel = template.label;
    } else if (template.label != bestLabel && score > secondScore) {
      secondScore = score;
    }
  }
  if (bestLabel == null || bestScore < 0.42) {
    return null;
  }
  final margin = bestScore - secondScore;
  final confidence = ((bestScore - 0.35) / 0.45 * 0.72 + margin * 2.2)
      .clamp(0.05, 0.98)
      .toDouble();
  return (label: bestLabel, confidence: confidence);
}

List<_RasterGlyphTemplate> _buildRasterGlyphTemplates() {
  final labels = <String>[
    'X',
    for (var fret = 0; fret <= 36; fret += 1) '$fret',
    for (var fret = 0; fret <= 36; fret += 1) '($fret)',
  ];
  final templates = <_RasterGlyphTemplate>[];
  for (final label in labels) {
    for (final bold in [false, true]) {
      for (final cutFraction in <double?>[null, 0.4, 0.5, 0.6]) {
        final image = img.Image(width: 240, height: 96);
        img.fill(image, color: img.ColorRgb8(255, 255, 255));
        img.drawString(
          image,
          label,
          font: img.arial48,
          color: img.ColorRgb8(0, 0, 0),
        );
        if (bold) {
          final ink = <(int, int)>[];
          for (var y = 0; y < image.height; y += 1) {
            for (var x = 0; x < image.width - 1; x += 1) {
              if (_luminance(image.getPixel(x, y)) < 160) ink.add((x, y));
            }
          }
          for (final point in ink) {
            image.setPixel(point.$1 + 1, point.$2, img.ColorRgb8(0, 0, 0));
          }
        }
        if (cutFraction != null) {
          final bounds = _rasterGlyphInkBounds(image);
          if (bounds != null) {
            final cutY =
                bounds.$2 + ((bounds.$4 - bounds.$2) * cutFraction).round();
            for (var y = cutY - 1; y <= cutY + 1; y += 1) {
              if (y < 0 || y >= image.height) continue;
              for (var x = bounds.$1; x < bounds.$3; x += 1) {
                image.setPixel(x, y, img.ColorRgb8(255, 255, 255));
              }
            }
          }
        }
        final normalized = _normalizeRasterGlyph(image);
        if (normalized == null) continue;
        templates.add(
          _RasterGlyphTemplate(
            label: label,
            mask: normalized.mask,
            aspectRatio: normalized.aspectRatio,
          ),
        );
      }
    }
  }
  return templates;
}

({List<bool> mask, double aspectRatio})? _normalizeRasterGlyph(
  img.Image source,
) {
  final bounds = _rasterGlyphInkBounds(source);
  if (bounds == null) return null;
  final width = bounds.$3 - bounds.$1;
  final height = bounds.$4 - bounds.$2;
  if (width <= 0 || height <= 0) return null;
  final cropped = img.copyCrop(
    source,
    x: bounds.$1,
    y: bounds.$2,
    width: width,
    height: height,
  );
  const extent = 32;
  const inner = 28;
  final scale = math.min(inner / width, inner / height);
  final resized = img.copyResize(
    cropped,
    width: math.max(1, (width * scale).round()),
    height: math.max(1, (height * scale).round()),
    interpolation: img.Interpolation.nearest,
  );
  final mask = List<bool>.filled(extent * extent, false);
  final offsetX = (extent - resized.width) ~/ 2;
  final offsetY = (extent - resized.height) ~/ 2;
  for (var y = 0; y < resized.height; y += 1) {
    for (var x = 0; x < resized.width; x += 1) {
      if (_luminance(resized.getPixel(x, y)) < 160) {
        mask[(y + offsetY) * extent + x + offsetX] = true;
      }
    }
  }
  return (mask: mask, aspectRatio: width / height);
}

(int, int, int, int)? _rasterGlyphInkBounds(img.Image image) {
  var left = image.width;
  var top = image.height;
  var right = 0;
  var bottom = 0;
  for (var y = 0; y < image.height; y += 1) {
    for (var x = 0; x < image.width; x += 1) {
      if (_luminance(image.getPixel(x, y)) >= 160) continue;
      left = math.min(left, x);
      top = math.min(top, y);
      right = math.max(right, x + 1);
      bottom = math.max(bottom, y + 1);
    }
  }
  if (right <= left || bottom <= top) return null;
  return (left, top, right, bottom);
}

double _glyphDice(List<bool> left, List<bool> right) {
  var leftInk = 0;
  var rightInk = 0;
  var intersection = 0;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index]) leftInk += 1;
    if (right[index]) rightInk += 1;
    if (left[index] && right[index]) intersection += 1;
  }
  if (leftInk + rightInk == 0) return 0;
  return intersection * 2 / (leftInk + rightInk);
}

class VisualTabTextCandidate {
  const VisualTabTextCandidate({
    required this.text,
    required this.rect,
    this.confidence = 1,
  });

  final String text;
  final NormalizedRect rect;
  final double confidence;
}

class VisualTabGeometry {
  const VisualTabGeometry({required this.systems, this.warnings = const []});

  final List<VisualTabSystemGeometry> systems;
  final List<String> warnings;
}

class VisualTabSystemGeometry {
  const VisualTabSystemGeometry({
    required this.rect,
    required this.stringLines,
    this.barLines = const [],
    this.connectedNotationRisks = const [],
    this.confidence = 1,
  });

  final NormalizedRect rect;
  final List<double> stringLines;
  final List<double> barLines;
  final List<VisualConnectedNotationRisk> connectedNotationRisks;
  final double confidence;
}

VisualTabAnalysis buildVisualTabAnalysis({
  required String stripId,
  required VisualTabSourceType sourceType,
  required VisualTabGeometry geometry,
  required List<VisualTabTextCandidate> candidates,
}) {
  final systems = <VisualTabSystem>[];
  final assignedCandidateIndexes = <int>{};
  for (
    var systemIndex = 0;
    systemIndex < geometry.systems.length;
    systemIndex += 1
  ) {
    final detected = geometry.systems[systemIndex];
    final spacing = _medianSpacing(detected.stringLines);
    final tokens = <VisualTabToken>[];
    for (
      var candidateIndex = 0;
      candidateIndex < candidates.length;
      candidateIndex += 1
    ) {
      final candidate = candidates[candidateIndex];
      final centerX = (candidate.rect.left + candidate.rect.right) / 2;
      final centerY = (candidate.rect.top + candidate.rect.bottom) / 2;
      if (centerX < detected.rect.left || centerX > detected.rect.right) {
        continue;
      }
      var nearestString = 0;
      var nearestDistance = double.infinity;
      for (var index = 0; index < detected.stringLines.length; index += 1) {
        final distance = (detected.stringLines[index] - centerY).abs();
        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearestString = index;
        }
      }
      final kind = classifyVisualTabToken(
        candidate.text,
        signedDistance: centerY - detected.stringLines[nearestString],
        stringSpacing: spacing,
      );
      final assignedString =
          kind == VisualTabTokenKind.fret || kind == VisualTabTokenKind.deadNote
          ? detected.stringLines.length - 1 - nearestString
          : null;
      if (centerY < detected.rect.top - spacing * 3 ||
          centerY > detected.rect.bottom + spacing) {
        continue;
      }
      tokens.add(
        VisualTabToken(
          id: 'token_${systemIndex}_$candidateIndex',
          text: candidate.text.trim(),
          rect: candidate.rect,
          kind: kind,
          stringIndex: assignedString,
          confidence: candidate.confidence,
          enabled:
              sourceType != VisualTabSourceType.rasterOcr ||
              candidate.confidence >= 0.62,
        ),
      );
      assignedCandidateIndexes.add(candidateIndex);
    }
    final fretTokens = tokens.where((token) => token.isFretLike).length;
    if (sourceType == VisualTabSourceType.positionedPdf && fretTokens == 0) {
      continue;
    }
    final confidence = fretTokens == 0
        ? detected.confidence * 0.55
        : detected.confidence;
    systems.add(
      VisualTabSystem(
        id: 'system_$systemIndex',
        rect: detected.rect,
        stringLines: detected.stringLines,
        barLines: detected.barLines,
        tokens: tokens,
        connectedNotationRisks: detected.connectedNotationRisks,
        confidence: confidence,
      ),
    );
  }
  final warnings = <String>[
    ...geometry.warnings,
    if (systems.isEmpty) 'No tablature string systems were detected.',
    if (candidates.isEmpty)
      'No fret text was detected. Add or correct tokens in review.',
    if (candidates.isNotEmpty &&
        assignedCandidateIndexes.length < candidates.length)
      '${candidates.length - assignedCandidateIndexes.length} numeric text '
          'candidate(s) were left outside detected tab systems.',
  ];
  return VisualTabAnalysis(
    stripId: stripId,
    sourceType: sourceType,
    systems: systems,
    warnings: warnings,
  );
}

VisualTabTokenKind classifyVisualTabToken(
  String value, {
  required double signedDistance,
  required double stringSpacing,
}) {
  final text = value.trim();
  final sitsOnOrBelowString =
      signedDistance >= -stringSpacing * 0.62 &&
      signedDistance <= stringSpacing * 1.45;
  if (text.toUpperCase() == 'X') {
    return sitsOnOrBelowString
        ? VisualTabTokenKind.deadNote
        : VisualTabTokenKind.ambiguous;
  }
  if (!RegExp(r'^(?:\(\d{1,2}\)|\d{1,2})$').hasMatch(text)) {
    return VisualTabTokenKind.ambiguous;
  }
  if (sitsOnOrBelowString) {
    return VisualTabTokenKind.fret;
  }
  if (signedDistance.abs() <= stringSpacing * 1.45) {
    return VisualTabTokenKind.ambiguous;
  }
  return VisualTabTokenKind.measureNumber;
}

VisualTabGeometry detectVisualTabGeometry(
  Uint8List bytes, {
  required NormalizedRect crop,
  required int expectedStringCount,
}) {
  return detectVisualTabGeometryFromImage(
    _decodeVisualTabImage(bytes),
    crop: crop,
    expectedStringCount: expectedStringCount,
  );
}

img.Image _decodeVisualTabImage(Uint8List bytes) {
  var image = img.decodeImage(bytes);
  if (image == null) {
    throw const FormatException('Stored chart image is invalid.');
  }
  return img.bakeOrientation(image);
}

VisualTabGeometry detectVisualTabGeometryFromImage(
  img.Image sourceImage, {
  required NormalizedRect crop,
  required int expectedStringCount,
}) {
  var image = sourceImage;
  final left = (crop.left * image.width).floor().clamp(0, image.width - 1);
  final top = (crop.top * image.height).floor().clamp(0, image.height - 1);
  final right = (crop.right * image.width).ceil().clamp(left + 1, image.width);
  final bottom = (crop.bottom * image.height).ceil().clamp(
    top + 1,
    image.height,
  );
  image = img.copyCrop(
    image,
    x: left,
    y: top,
    width: right - left,
    height: bottom - top,
  );

  final background = _estimateBackgroundLuminance(image);
  final xStart = (image.width * 0.03).round();
  final xEnd = (image.width * 0.97).round();
  final threshold = math.max(24.0, background < 110 ? 30.0 : 38.0);
  final candidateRows = <int>[];
  for (var y = 0; y < image.height; y += 1) {
    var ink = 0;
    var longestRun = 0;
    var run = 0;
    for (var x = xStart; x < xEnd; x += 1) {
      final isInk =
          (_luminance(image.getPixel(x, y)) - background).abs() >= threshold;
      if (isInk) {
        ink += 1;
        run += 1;
        if (run > longestRun) longestRun = run;
      } else {
        run = 0;
      }
    }
    final width = math.max(1, xEnd - xStart);
    if (ink / width >= 0.28 || longestRun / width >= 0.22) {
      candidateRows.add(y);
    }
  }
  final clusteredRows = _clusterCoordinates(candidateRows)
      .map((cluster) => cluster.reduce((a, b) => a + b) / cluster.length)
      .toList(growable: false);
  final lineGroups = _findEquallySpacedGroups(
    clusteredRows,
    expectedStringCount,
    image.height,
  );
  final systems = <VisualTabSystemGeometry>[];
  for (final lines in lineGroups) {
    final spacingPixels = _medianSpacing(lines);
    final systemTop = math.max(0.0, lines.first - spacingPixels * 0.85);
    final systemBottom = math.min(
      image.height.toDouble(),
      lines.last + spacingPixels * 0.85,
    );
    final barLines = _detectBarLines(
      image,
      background: background,
      threshold: threshold,
      top: lines.first,
      bottom: lines.last,
    );
    final connectedNotationRisks = _detectConnectedNotationRisks(
      image,
      background: background,
      threshold: threshold,
      lines: lines,
      barLines: barLines,
    );
    systems.add(
      VisualTabSystemGeometry(
        rect: _safeNormalizedRect(
          0,
          systemTop / image.height,
          1,
          systemBottom / image.height,
        ),
        stringLines: [for (final line in lines) line / image.height],
        barLines: [for (final line in barLines) line / image.width],
        connectedNotationRisks: connectedNotationRisks,
        confidence: _spacingConfidence(lines),
      ),
    );
  }
  return VisualTabGeometry(
    systems: systems,
    warnings: [
      if (systems.isEmpty)
        'Raster geometry did not find $expectedStringCount evenly spaced '
            'string lines.',
    ],
  );
}

List<double> _detectBarLines(
  img.Image image, {
  required double background,
  required double threshold,
  required double top,
  required double bottom,
}) {
  final yStart = top.round().clamp(0, image.height - 1);
  final yEnd = bottom.round().clamp(yStart + 1, image.height);
  final candidateColumns = <int>[];
  for (var x = 0; x < image.width; x += 1) {
    var ink = 0;
    for (var y = yStart; y < yEnd; y += 1) {
      if ((_luminance(image.getPixel(x, y)) - background).abs() >= threshold) {
        ink += 1;
      }
    }
    if (ink / math.max(1, yEnd - yStart) >= 0.72) {
      candidateColumns.add(x);
    }
  }
  return _clusterCoordinates(candidateColumns)
      .map((cluster) => cluster.reduce((a, b) => a + b) / cluster.length)
      .toList(growable: false);
}

List<VisualConnectedNotationRisk> _detectConnectedNotationRisks(
  img.Image image, {
  required double background,
  required double threshold,
  required List<double> lines,
  required List<double> barLines,
}) {
  if (lines.length < 2) return const [];
  bool isInk(int x, int y) =>
      (_luminance(image.getPixel(x, y)) - background).abs() >= threshold;
  final risks = <VisualConnectedNotationRisk>[];
  for (var gapIndex = 0; gapIndex < lines.length - 1; gapIndex += 1) {
    final seam = ((lines[gapIndex] + lines[gapIndex + 1]) / 2).round();
    final radius = math.max(
      1,
      ((lines[gapIndex + 1] - lines[gapIndex]) * 0.12).round(),
    );
    final candidates = <int>[];
    for (var x = 2; x < image.width - 2; x += 1) {
      final center = isInk(x, seam);
      final upper = [
        for (var dx = -1; dx <= 1; dx += 1)
          isInk(x + dx, (seam - radius).clamp(0, image.height - 1)),
      ].any((value) => value);
      final lower = [
        for (var dx = -1; dx <= 1; dx += 1)
          isInk(x + dx, (seam + radius).clamp(0, image.height - 1)),
      ].any((value) => value);
      if (center && upper && lower) candidates.add(x);
    }
    final clusters = _clusterCoordinates(candidates);
    var riskIndex = 0;
    for (final cluster in clusters) {
      final centerX = cluster.reduce((a, b) => a + b) / cluster.length;
      if (barLines.any((bar) => (bar - centerX).abs() <= 4)) continue;
      final left = (cluster.first - 3).clamp(0, image.width - 1);
      final right = (cluster.last + 4).clamp(left + 1, image.width);
      final halfHeight = math.max(radius * 2, 3);
      final top = (seam - halfHeight).clamp(0, image.height - 1);
      final bottom = (seam + halfHeight + 1).clamp(top + 1, image.height);
      risks.add(
        VisualConnectedNotationRisk(
          id: 'gap_${gapIndex}_risk_${riskIndex++}',
          rect: _safeNormalizedRect(
            left / image.width,
            top / image.height,
            right / image.width,
            bottom / image.height,
          ),
          gapIndex: gapIndex,
        ),
      );
    }
  }
  return risks;
}

List<List<double>> _findEquallySpacedGroups(
  List<double> rows,
  int count,
  int imageHeight,
) {
  if (rows.length < count) return const [];
  final candidates = <List<double>>[];
  for (var start = 0; start <= rows.length - count; start += 1) {
    final group = rows.sublist(start, start + count);
    final spacing = _medianSpacing(group);
    if (spacing < math.max(2.0, imageHeight * 0.002)) continue;
    final tolerance = math.max(2.0, spacing * 0.28);
    var valid = true;
    for (var index = 1; index < group.length; index += 1) {
      if (((group[index] - group[index - 1]) - spacing).abs() > tolerance) {
        valid = false;
        break;
      }
    }
    if (valid) candidates.add(group);
  }
  candidates.sort((left, right) {
    final confidence = _spacingConfidence(
      right,
    ).compareTo(_spacingConfidence(left));
    if (confidence != 0) return confidence;
    return left.first.compareTo(right.first);
  });
  final accepted = <List<double>>[];
  for (final candidate in candidates) {
    final overlaps = accepted.any(
      (existing) =>
          candidate.first <= existing.last && candidate.last >= existing.first,
    );
    if (!overlaps) accepted.add(candidate);
  }
  accepted.sort((left, right) => left.first.compareTo(right.first));
  return accepted;
}

List<List<int>> _clusterCoordinates(List<int> values) {
  return _clusterCoordinatesWithGap(values, 2);
}

List<List<int>> _clusterCoordinatesWithGap(List<int> values, int maximumGap) {
  if (values.isEmpty) return const [];
  final clusters = <List<int>>[
    [values.first],
  ];
  for (final value in values.skip(1)) {
    if (value - clusters.last.last <= maximumGap) {
      clusters.last.add(value);
    } else {
      clusters.add([value]);
    }
  }
  return clusters;
}

double _spacingConfidence(List<double> lines) {
  if (lines.length < 2) return 0;
  final spacing = _medianSpacing(lines);
  if (spacing <= 0) return 0;
  var deviation = 0.0;
  for (var index = 1; index < lines.length; index += 1) {
    deviation += ((lines[index] - lines[index - 1]) - spacing).abs();
  }
  return (1 - deviation / ((lines.length - 1) * spacing)).clamp(0.0, 1.0);
}

double _medianSpacing(List<double> values) {
  if (values.length < 2) return 0.01;
  final spacings = <double>[
    for (var index = 1; index < values.length; index += 1)
      values[index] - values[index - 1],
  ]..sort();
  return spacings[spacings.length ~/ 2];
}

double _estimateBackgroundLuminance(img.Image image) {
  final samples = <double>[];
  final edgeX = math.max(1, image.width ~/ 12);
  final edgeY = math.max(1, image.height ~/ 12);
  for (var y = 0; y < image.height; y += edgeY) {
    for (final x in [0, image.width - 1]) {
      samples.add(_luminance(image.getPixel(x, y)));
    }
  }
  for (var x = 0; x < image.width; x += edgeX) {
    for (final y in [0, image.height - 1]) {
      samples.add(_luminance(image.getPixel(x, y)));
    }
  }
  samples.sort();
  return samples[samples.length ~/ 2];
}

double _luminance(img.Pixel pixel) =>
    pixel.r.toDouble() * 0.299 +
    pixel.g.toDouble() * 0.587 +
    pixel.b.toDouble() * 0.114;

NormalizedRect _pdfRectToNormalized(
  double left,
  double top,
  double right,
  double bottom,
  double pageWidth,
  double pageHeight,
) {
  return _safeNormalizedRect(
    left / pageWidth,
    1 - top / pageHeight,
    right / pageWidth,
    1 - bottom / pageHeight,
  );
}

NormalizedRect? _assetRectToCropLocal(
  NormalizedRect rect,
  NormalizedRect crop,
) {
  final left = math.max(rect.left, crop.left);
  final top = math.max(rect.top, crop.top);
  final right = math.min(rect.right, crop.right);
  final bottom = math.min(rect.bottom, crop.bottom);
  if (right <= left || bottom <= top) return null;
  return _safeNormalizedRect(
    (left - crop.left) / crop.width,
    (top - crop.top) / crop.height,
    (right - crop.left) / crop.width,
    (bottom - crop.top) / crop.height,
  );
}

NormalizedRect _safeNormalizedRect(
  double left,
  double top,
  double right,
  double bottom,
) {
  final safeLeft = left.clamp(0.0, 0.999);
  final safeTop = top.clamp(0.0, 0.999);
  final safeRight = right.clamp(safeLeft + 0.0001, 1.0);
  final safeBottom = bottom.clamp(safeTop + 0.0001, 1.0);
  return NormalizedRect(safeLeft, safeTop, safeRight, safeBottom);
}
