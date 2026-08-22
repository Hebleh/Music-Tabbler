import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';

import '../domain/visual_chart_models.dart';
import '../domain/visual_tab_transform_models.dart';
import 'service_contracts.dart';
import 'visual_image_processor.dart';

abstract interface class VisualTabAnalyzer {
  Future<VisualTabAnalysis> analyze(
    VisualStrip strip, {
    required int sourceStringCount,
    bool preferPositionedPdf = true,
  });
}

class VisualTabStringCountGuess {
  const VisualTabStringCountGuess({
    required this.stringCount,
    required this.geometryConfidence,
    required this.detectedBarLines,
    this.warning,
  });

  final int? stringCount;
  final double geometryConfidence;
  final int detectedBarLines;
  final String? warning;

  bool get rasterLikelyUsable =>
      stringCount != null &&
      geometryConfidence >= 0.80 &&
      detectedBarLines >= 2;
}

class VisualTabAnalysisService implements VisualTabAnalyzer {
  VisualTabAnalysisService({
    required this.library,
    required this.textRecognition,
  });

  final ChartLibrary library;
  final TextRecognitionService textRecognition;
  final Map<String, Future<List<VisualTabTextCandidate>>> _positionedCache = {};
  final Map<String, Future<img.Image>> _geometryImageCache = {};
  static bool _pdfInitialized = false;

  /// Uses the normal raster geometry detector on one source row to provide an
  /// editable early warning before the full OCR review starts.
  Future<VisualTabStringCountGuess> guessSourceStringCount(
    VisualStrip strip,
  ) async {
    try {
      final geometry = await _geometryForStrip(strip);
      if (geometry.systems.isEmpty) {
        return VisualTabStringCountGuess(
          stringCount: null,
          geometryConfidence: 0,
          detectedBarLines: 0,
          warning:
              geometry.warnings.firstOrNull ??
              'Raster geometry did not find a tab system in Row 1.',
        );
      }
      final system = geometry.systems.first;
      return VisualTabStringCountGuess(
        stringCount: system.stringLines.length,
        geometryConfidence: system.confidence,
        detectedBarLines: system.barLines.length,
        warning: geometry.systems.length > 1
            ? 'Row 1 contains multiple tab systems; the first system was used.'
            : null,
      );
    } catch (_) {
      return const VisualTabStringCountGuess(
        stringCount: null,
        geometryConfidence: 0,
        detectedBarLines: 0,
        warning: 'Raster preview could not read Row 1.',
      );
    }
  }

  @override
  Future<VisualTabAnalysis> analyze(
    VisualStrip strip, {
    required int sourceStringCount,
    bool preferPositionedPdf = true,
  }) async {
    if (!isSupportedVisualTabStringCount(sourceStringCount)) {
      throw const FormatException('Source tuning needs 2 to 12 strings.');
    }
    final deskewed = strip.deskewDegrees.abs() >= 0.0001;
    final geometry = await _geometryForStrip(
      strip,
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

    final rasterCandidates = await _recognizeRasterCandidates(
      strip,
      geometry: geometry,
      deskewed: deskewed,
    );
    final positionedCandidates =
        !deskewed && strip.sourceAssetHash != null && strip.sourcePage != null
        ? await _loadPositionedPdfCandidates(strip)
        : const <VisualTabTextCandidate>[];
    final candidates = mergeVisualTabCandidates(
      positioned: positionedCandidates,
      raster: rasterCandidates,
    );
    final result = buildVisualTabAnalysis(
      stripId: strip.id,
      sourceType: VisualTabSourceType.rasterOcr,
      geometry: geometry,
      candidates: candidates,
    );
    if (positionedCandidates.isEmpty) return result;
    return result.copyWith(
      warnings: [
        ...result.warnings,
        'Raster OCR was supplemented with positioned PDF text for measure '
            'labels and other selectable PDF text.',
      ],
    );
  }

  Future<VisualTabGeometry> _geometryForStrip(
    VisualStrip strip, {
    int? expectedStringCount,
  }) async {
    final deskewed = strip.deskewDegrees.abs() >= 0.0001;
    if (deskewed) {
      final bytes = const VisualImageProcessor().process(
        await File(
          library.assetPath(strip.assetHash, strip.assetExtension),
        ).readAsBytes(),
        strip.copyWith(
          treatment: VisualTreatment.original,
          lyricContrast: 1,
          highlights: const [],
        ),
      );
      return expectedStringCount == null
          ? detectVisualTabGeometryAnyStringCount(
              bytes,
              crop: const NormalizedRect.full(),
            )
          : detectVisualTabGeometry(
              bytes,
              crop: const NormalizedRect.full(),
              expectedStringCount: expectedStringCount,
            );
    }
    return _detectVisualTabGeometryFromImage(
      await _analysisImage(strip),
      crop: strip.crop,
      expectedStringCount: expectedStringCount,
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
    final sourceImage = await _analysisImage(strip);
    for (final system in geometry.systems) {
      final spacing = _medianSpacing(system.stringLines);
      final localCrop = NormalizedRect(
        0,
        math.max(0, system.rect.top - spacing * 1.35),
        1,
        math.min(1, system.rect.bottom + spacing * 1.35),
      );
      final systemStrip = strip.copyWith(
        crop: NormalizedRect(
          strip.crop.left + localCrop.left * strip.crop.width,
          strip.crop.top + localCrop.top * strip.crop.height,
          strip.crop.left + localCrop.right * strip.crop.width,
          strip.crop.top + localCrop.bottom * strip.crop.height,
        ).clamp(),
      );
      final List<RecognizedTextRegion> recognizedRegions;
      if (preparedRecognizer == null) {
        // A platform without prepared-image OCR keeps its normal contextual
        // recognizer. Its regions are mapped back from the system crop.
        final contextual = await textRecognition.recognize(systemStrip);
        recognizedRegions = [
          for (final region in _expandRecognizedRegions(contextual.regions))
            RecognizedTextRegion(
              text: region.text,
              rect: NormalizedRect(
                localCrop.left + region.rect.left * localCrop.width,
                localCrop.top + region.rect.top * localCrop.height,
                localCrop.left + region.rect.right * localCrop.width,
                localCrop.top + region.rect.bottom * localCrop.height,
              ).clamp(),
              confidence: region.confidence,
            ),
        ];
      } else {
        // Full-system Windows OCR repeatedly interprets tie curves as extra
        // zeroes. The isolated high-resolution path preserves the exact
        // Songsterr 12/9/5 shapes without promoting notation curves to frets.
        final isolated = await _recognizeTabGlyphCandidates(
          preparedRecognizer,
          _detectRasterGlyphCandidates(
            sourceImage,
            stripCrop: strip.crop,
            system: system,
          ),
        );
        recognizedRegions = isolated.regions;
      }
      for (final region in recognizedRegions) {
        candidates.add(
          VisualTabTextCandidate(
            text: region.text,
            rect: region.rect,
            confidence: region.confidence,
          ),
        );
      }
    }
    return candidates;
  }

  Future<img.Image> _analysisImage(VisualStrip strip) {
    final sourceHash = strip.sourceAssetHash;
    final sourcePage = strip.sourcePage;
    if (sourceHash == null || sourcePage == null) {
      return _geometryImageCache.putIfAbsent(
        '${strip.assetHash}.${strip.assetExtension}',
        () async => _decodeVisualTabImage(
          await File(
            library.assetPath(strip.assetHash, strip.assetExtension),
          ).readAsBytes(),
        ),
      );
    }
    return _geometryImageCache.putIfAbsent(
      'pdf:$sourceHash:$sourcePage:320dpi',
      () async {
        try {
          return await _renderPdfAnalysisPage(sourceHash, sourcePage);
        } catch (_) {
          // Imported drafts can outlive or omit their original PDF (and older
          // test fixtures intentionally provide only the stored page image).
          // Analysis must remain available from the content-addressed display
          // asset rather than turning that recoverable case into a hard error.
          return _decodeVisualTabImage(
            await File(
              library.assetPath(strip.assetHash, strip.assetExtension),
            ).readAsBytes(),
          );
        }
      },
    );
  }

  Future<img.Image> _renderPdfAnalysisPage(
    String sourceAssetHash,
    int sourcePage,
  ) async {
    if (!_pdfInitialized) {
      await pdfrxFlutterInitialize();
      _pdfInitialized = true;
    }
    final path = library.assetPath(sourceAssetHash, 'pdf');
    final document = await PdfDocument.openFile(path);
    try {
      final pageIndex = sourcePage - 1;
      if (pageIndex < 0 || pageIndex >= document.pages.length) {
        throw FormatException('PDF page $sourcePage is unavailable.');
      }
      final page = document.pages[pageIndex];
      const scale = 320.0 / 72.0;
      final rendered = await page.render(
        fullWidth: page.width * scale,
        fullHeight: page.height * scale,
      );
      if (rendered == null) {
        throw FormatException('PDF page $sourcePage could not render.');
      }
      try {
        return rendered.createImageNF();
      } finally {
        rendered.dispose();
      }
    } finally {
      document.dispose();
    }
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
      await pdfrxFlutterInitialize();
      _pdfInitialized = true;
    }
    final document = await PdfDocument.openFile(path);
    try {
      final pageIndex = sourcePage - 1;
      if (pageIndex < 0 || pageIndex >= document.pages.length) return const [];
      final page = document.pages[pageIndex];
      final text = await page.loadStructuredText();
      final candidates = <VisualTabTextCandidate>[];
      for (final fragment in text.fragments) {
        final runes = fragment.text.runes.toList(growable: false);
        final glyphCount = math.min(runes.length, fragment.charRects.length);
        var token = '';
        PdfRect? tokenBounds = fragment.charRects.isEmpty
            ? null
            : fragment.charRects.first;
        PdfRect? previousBounds;

        void flushToken() {
          if (token.isEmpty || tokenBounds == null) return;
          if (!RegExp(r'^(?:\(\d+\)|\d+|[xX])$').hasMatch(token)) {
            token = '';
            previousBounds = null;
            return;
          }
          final fullRect = _pdfRectToNormalized(
            tokenBounds.left,
            tokenBounds.top,
            tokenBounds.right,
            tokenBounds.bottom,
            page.width,
            page.height,
          );
          candidates.add(VisualTabTextCandidate(text: token, rect: fullRect));
          token = '';
          previousBounds = null;
        }

        for (var index = 0; index < glyphCount; index += 1) {
          final character = String.fromCharCode(runes[index]);
          final isTokenGlyph = RegExp(r'[0-9xX()]').hasMatch(character);
          if (!isTokenGlyph) {
            flushToken();
            continue;
          }
          final bounds = fragment.charRects[index];
          if (token.isNotEmpty &&
              !_positionedPdfGlyphsAreAdjacent(previousBounds, bounds)) {
            flushToken();
          }
          if (token.isEmpty) {
            token = character;
            tokenBounds = bounds;
          } else {
            token += character;
            tokenBounds = tokenBounds!.merge(bounds);
          }
          previousBounds = bounds;
        }
        flushToken();
      }
      return candidates;
    } finally {
      document.dispose();
    }
  }
}

List<RecognizedTextRegion> _expandRecognizedRegions(
  List<RecognizedTextRegion> regions,
) {
  final expanded = <RecognizedTextRegion>[];
  final tokenPattern = RegExp(r'\(\d{1,2}\)|\d{1,2}|[xX]');
  for (final region in regions) {
    final matches = tokenPattern
        .allMatches(region.text)
        .toList(growable: false);
    if (matches.isEmpty) continue;
    if (matches.length == 1) {
      expanded.add(
        RecognizedTextRegion(
          text: matches.single.group(0)!,
          rect: region.rect,
          confidence: region.confidence,
        ),
      );
      continue;
    }
    final segmentWidth = region.rect.width / matches.length;
    for (var index = 0; index < matches.length; index += 1) {
      expanded.add(
        RecognizedTextRegion(
          text: matches[index].group(0)!,
          rect: NormalizedRect(
            region.rect.left + segmentWidth * index,
            region.rect.top,
            region.rect.left + segmentWidth * (index + 1),
            region.rect.bottom,
          ).clamp(),
          confidence: region.confidence,
        ),
      );
    }
  }
  return expanded;
}

bool _positionedPdfGlyphsAreAdjacent(PdfRect? previous, PdfRect? next) {
  if (previous == null || next == null) return false;
  final previousHeight = (previous.bottom - previous.top).abs().toDouble();
  final nextHeight = (next.bottom - next.top).abs().toDouble();
  final height = math.max(previousHeight, nextHeight);
  final previousCenter = (previous.top + previous.bottom) / 2;
  final nextCenter = (next.top + next.bottom) / 2;
  final sameBaseline =
      (previousCenter - nextCenter).abs() <= math.max(0.8, height * 0.42);
  final horizontalGap = next.left - previous.right;
  final followsHorizontally =
      horizontalGap >= -height * 0.18 &&
      horizontalGap <= math.max(0.8, height * 0.24);
  return sameBaseline && followsHorizontally;
}

/// Keeps exact positioned-PDF labels (notably parenthesized sustain frets)
/// and supplements them with raster-only detections. Candidates occupying the
/// same glyph position are not duplicated in the review model.
List<VisualTabTextCandidate> mergeVisualTabCandidates({
  required List<VisualTabTextCandidate> positioned,
  required List<VisualTabTextCandidate> raster,
}) {
  final merged = <VisualTabTextCandidate>[];
  final usedRaster = <int>{};
  for (final candidate in positioned) {
    var overlappingIndex = -1;
    for (var index = 0; index < raster.length; index += 1) {
      if (usedRaster.contains(index)) continue;
      if (_candidateRectsOverlap(candidate.rect, raster[index].rect)) {
        overlappingIndex = index;
        break;
      }
    }
    if (overlappingIndex < 0) {
      merged.add(candidate);
      continue;
    }
    usedRaster.add(overlappingIndex);
    final rasterCandidate = raster[overlappingIndex];
    final positionedBare = candidate.text.replaceAll(RegExp(r'[()]'), '');
    final rasterBare = rasterCandidate.text.replaceAll(RegExp(r'[()]'), '');
    final matchingFret =
        positionedBare.toUpperCase() == rasterBare.toUpperCase();
    final label = matchingFret && rasterCandidate.text.startsWith('(')
        ? rasterCandidate.text
        : candidate.text;
    // The PDF text layer has the more reliable label (notably 12 vs a raster
    // fragment), while the raster detector has coordinates aligned to the
    // reviewed strip. Keeping the raster rectangle prevents a slightly
    // displaced PDF glyph from suppressing a valid sustain below the string.
    merged.add(
      VisualTabTextCandidate(
        text: label,
        rect: rasterCandidate.rect,
        confidence: math.max(candidate.confidence, rasterCandidate.confidence),
      ),
    );
  }
  for (var index = 0; index < raster.length; index += 1) {
    if (!usedRaster.contains(index)) merged.add(raster[index]);
  }
  return List.unmodifiable(merged);
}

bool _candidateRectsOverlap(NormalizedRect left, NormalizedRect right) {
  final overlapLeft = math.max(left.left, right.left);
  final overlapTop = math.max(left.top, right.top);
  final overlapRight = math.min(left.right, right.right);
  final overlapBottom = math.min(left.bottom, right.bottom);
  if (overlapRight <= overlapLeft || overlapBottom <= overlapTop) return false;
  final overlapArea =
      (overlapRight - overlapLeft) * (overlapBottom - overlapTop);
  final smallerArea = math.min(
    left.width * left.height,
    right.width * right.height,
  );
  return smallerArea > 0 && overlapArea / smallerArea >= 0.35;
}

Future<MetadataSuggestion> _recognizeTabGlyphCandidates(
  PreparedTextRecognitionService recognizer,
  List<_RasterGlyphCandidate> candidates,
) async {
  if (candidates.isEmpty) return const MetadataSuggestion();
  // One candidate per OCR row prevents the Windows recognizer from combining
  // adjacent fret tiles into a single text region. The former six-column
  // sheet often read `12 9 9 9 9 5 5` as only a few regions, then mapped each
  // combined region back to one tile and silently lost the other notes.
  const columns = 1;
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
      // Cubic enlargement gives the native OCR engine continuous curves.
      // Nearest-neighbour magnified the two-pixel staff-line cut into a large
      // blocky notch, which made the Songsterr 9 glyph look like a 7.
      interpolation: img.Interpolation.cubic,
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
  final nativeLabels = <int, ({String label, double confidence})>{};
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
    nativeLabels[index] = (
      label: match.group(0)!,
      confidence: region.confidence,
    );
  }
  final rawClassifications = <({String label, double confidence})?>[
    for (final candidate in candidates)
      _classifyParenthesizedRasterGlyph(candidate.image) ??
          _classifySeparatedRasterDigits(candidate.image) ??
          _classifyNarrowRasterOne(candidate.image) ??
          _classifyRasterGlyph(candidate.image),
  ];
  final repeatedClassifications = _stabilizeRepeatedRasterGlyphs(
    candidates,
    rawClassifications,
    nativeLabels,
  );
  final chordClassifications = _stabilizeRasterChordColumns(
    candidates,
    repeatedClassifications,
    nativeLabels,
  );
  final classifications = _stabilizeRasterSustainColumns(
    candidates,
    chordClassifications,
    nativeLabels,
  );
  for (var index = 0; index < candidates.length; index += 1) {
    final classified = classifications[index];
    final native = nativeLabels[index];
    final nativeLabel = native?.label;
    if (classified == null && nativeLabel == null) continue;
    final classifiedBare = classified?.label.replaceAll(RegExp(r'[()]'), '');
    final nativeBare = nativeLabel?.replaceAll(RegExp(r'[()]'), '');
    final parenthesizedCandidate = classified?.label.startsWith('(') ?? false;
    final nativeFret =
        nativeBare != null && RegExp(r'^\d{1,2}$').hasMatch(nativeBare);
    final agrees =
        classified != null &&
        nativeLabel != null &&
        classifiedBare!.toUpperCase() == nativeBare!.toUpperCase();
    // Prefer the deterministic image classifier only when it is itself
    // confident. The Windows OCR engine repeatedly labels compact Songsterr 5
    // and 9 glyphs as 7, but low-confidence deterministic guesses on tightly
    // spaced multi-string chords must not override a stronger native result.
    const deterministicDisagreementThreshold = 0.72;
    final preferNativeDisagreement =
        !agrees &&
        classified != null &&
        nativeLabel != null &&
        classified.confidence < deterministicDisagreementThreshold;
    final label = parenthesizedCandidate && nativeFret
        ? '($nativeBare)'
        : agrees
        ? (classified.label.startsWith('(') ? '($nativeBare)' : nativeLabel)
        : preferNativeDisagreement
        ? nativeLabel
        : classified?.label ?? nativeLabel!;
    final normalizedGlyph = _normalizeRasterGlyph(candidates[index].image);
    if (normalizedGlyph != null) {
      final isParenthesized = label.startsWith('(') && label.endsWith(')');
      // Shallow tie/slide fragments have a very wide ink box and were being
      // matched to ordinary digits. Preserve deliberately parenthesized
      // sustain frets, but never promote a wide notation stroke to a number.
      if (normalizedGlyph.aspectRatio > 1.35 &&
          (!isParenthesized || normalizedGlyph.aspectRatio > 2.5)) {
        continue;
      }
    }
    final confidence = parenthesizedCandidate && nativeFret
        ? math.max(0.72, native!.confidence.clamp(0.0, 1.0).toDouble())
        : agrees
        ? math.max(0.82, math.max(classified.confidence, native!.confidence))
        : preferNativeDisagreement
        ? native!.confidence.clamp(0.0, 1.0).toDouble()
        : classified?.confidence ??
              native!.confidence.clamp(0.0, 1.0).toDouble();
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

List<({String label, double confidence})?> _stabilizeRepeatedRasterGlyphs(
  List<_RasterGlyphCandidate> candidates,
  List<({String label, double confidence})?> classifications,
  Map<int, ({String label, double confidence})> nativeLabels,
) {
  const reliableConfidence = 0.72;
  const minimumReliablePeerSimilarity = 0.82;
  const minimumRepeatedPeerSimilarity = 0.64;
  final normalized = [
    for (final candidate in candidates) _normalizeRasterGlyph(candidate.image),
  ];
  return [
    for (var index = 0; index < candidates.length; index += 1)
      () {
        final current = classifications[index];
        if (current != null && current.confidence >= reliableConfidence) {
          return current;
        }
        ({String label, double confidence})? bestAnchor;
        var bestSimilarity = 0.0;
        final currentGlyph = normalized[index];
        if (currentGlyph == null) return current;
        for (var peerIndex = 0; peerIndex < candidates.length; peerIndex += 1) {
          if (peerIndex == index) continue;
          final peer = nativeLabels[peerIndex] ?? classifications[peerIndex];
          final peerGlyph = normalized[peerIndex];
          if (peer == null ||
              peer.confidence < reliableConfidence ||
              peerGlyph == null ||
              (currentGlyph.aspectRatio - peerGlyph.aspectRatio).abs() > 0.16) {
            continue;
          }
          final similarity = _glyphDice(currentGlyph.mask, peerGlyph.mask);
          if (similarity < minimumReliablePeerSimilarity ||
              similarity <= bestSimilarity) {
            continue;
          }
          bestAnchor = peer;
          bestSimilarity = similarity;
        }
        if (bestAnchor != null) {
          return (
            label: bestAnchor.label,
            confidence: math.max(
              reliableConfidence,
              math.min(0.92, bestAnchor.confidence * bestSimilarity),
            ),
          );
        }

        // A slide or tie can deform a real fret enough to lower bitmap
        // similarity even though the deterministic classifier still reads
        // the correct digit. Recover only a locally repeated label bracketed
        // by reliable peers on the same string. Requiring agreement on both
        // sides prevents an isolated curve fragment from becoming a note.
        final currentBare = current?.label.replaceAll(RegExp(r'[()]'), '');
        if (current != null &&
            current.confidence >= 0.35 &&
            currentBare != null &&
            RegExp(r'^\d{1,2}$').hasMatch(currentBare)) {
          final currentCenterX =
              (candidates[index].rect.left + candidates[index].rect.right) / 2;
          var matchingPeerBefore = false;
          var matchingPeerAfter = false;
          for (
            var peerIndex = 0;
            peerIndex < candidates.length;
            peerIndex += 1
          ) {
            if (peerIndex == index ||
                candidates[peerIndex].lineIndex !=
                    candidates[index].lineIndex) {
              continue;
            }
            final peer = nativeLabels[peerIndex] ?? classifications[peerIndex];
            if (peer == null || peer.confidence < 0.62) continue;
            final peerBare = peer.label.replaceAll(RegExp(r'[()]'), '');
            if (peerBare != currentBare) continue;
            final peerCenterX =
                (candidates[peerIndex].rect.left +
                    candidates[peerIndex].rect.right) /
                2;
            final distance = peerCenterX - currentCenterX;
            if (distance.abs() > 0.20) continue;
            if (distance < 0) matchingPeerBefore = true;
            if (distance > 0) matchingPeerAfter = true;
          }
          if (matchingPeerBefore && matchingPeerAfter) {
            return (label: current.label, confidence: 0.70);
          }
        }

        // A repeated run can be more reliable than any one tiny OCR crop.
        // This is common in dense 7/8-string sources where the same narrow
        // fret is drawn dozens of times, but it is independent of the actual
        // string count and label. Promote only a visually coherent family
        // with a clear label majority; mixed passages remain untouched.
        final votes = <String, double>{};
        final peerCounts = <String, int>{};
        for (var peerIndex = 0; peerIndex < candidates.length; peerIndex += 1) {
          final peer = nativeLabels[peerIndex] ?? classifications[peerIndex];
          final peerGlyph = normalized[peerIndex];
          if (peer == null || peerGlyph == null) continue;
          if ((currentGlyph.aspectRatio - peerGlyph.aspectRatio).abs() > 0.18) {
            continue;
          }
          final similarity = _glyphDice(currentGlyph.mask, peerGlyph.mask);
          if (similarity < minimumRepeatedPeerSimilarity) continue;
          final bare = peer.label.replaceAll(RegExp(r'[()]'), '');
          if (!RegExp(
            r'^(?:\d{1,2}|X)$',
            caseSensitive: false,
          ).hasMatch(bare)) {
            continue;
          }
          final label = peer.label.toUpperCase();
          votes[label] = (votes[label] ?? 0) + math.max(0.15, peer.confidence);
          peerCounts[label] = (peerCounts[label] ?? 0) + 1;
        }
        if (votes.isEmpty) return current;
        final ranked = votes.entries.toList()
          ..sort((left, right) => right.value.compareTo(left.value));
        final winner = ranked.first;
        final totalWeight = votes.values.reduce((left, right) => left + right);
        final winnerCount = peerCounts[winner.key] ?? 0;
        if (winnerCount < 3 || winner.value / totalWeight < 0.70) {
          // Slides and tie endpoints can distort a very narrow digit enough
          // to defeat bitmap similarity. Use the dominant narrow glyph on
          // the same string only when a long, unambiguous repeated run exists.
          // Wider glyphs are deliberately excluded so a terminal 3/5/7 in a
          // repeated run is never rewritten to match its neighbours.
          if (currentGlyph.aspectRatio > 0.50) return current;
          final lineVotes = <String, int>{};
          var eligiblePeers = 0;
          final currentCenterX =
              (candidates[index].rect.left + candidates[index].rect.right) / 2;
          for (
            var peerIndex = 0;
            peerIndex < candidates.length;
            peerIndex += 1
          ) {
            if (candidates[peerIndex].lineIndex !=
                candidates[index].lineIndex) {
              continue;
            }
            final peerCenterX =
                (candidates[peerIndex].rect.left +
                    candidates[peerIndex].rect.right) /
                2;
            if ((peerCenterX - currentCenterX).abs() > 0.20) continue;
            final peer = nativeLabels[peerIndex] ?? classifications[peerIndex];
            final peerGlyph = normalized[peerIndex];
            if (peer == null ||
                peerGlyph == null ||
                peerGlyph.aspectRatio > 0.55 ||
                !RegExp(r'^\d$').hasMatch(peer.label)) {
              continue;
            }
            eligiblePeers += 1;
            lineVotes[peer.label] = (lineVotes[peer.label] ?? 0) + 1;
          }
          if (lineVotes.isEmpty) return current;
          final lineWinner = lineVotes.entries.toList()
            ..sort((left, right) => right.value.compareTo(left.value));
          if (lineWinner.first.value < 5 ||
              lineWinner.first.value / eligiblePeers < 0.75) {
            return current;
          }
          return (label: lineWinner.first.key, confidence: 0.70);
        }
        return (
          label: winner.key,
          // Strong enough to surface as an editable proposal, but below the
          // native-OCR disagreement threshold so a platform reading can still
          // correct a rare different note at the end of the run.
          confidence: math.min(0.71, 0.66 + winnerCount * 0.005),
        );
      }(),
  ];
}

bool _rasterCandidatesAreColumnAligned(
  List<_RasterGlyphCandidate> candidates,
  int index,
  int peerIndex,
) {
  final candidate = candidates[index];
  final peerCandidate = candidates[peerIndex];
  final centerX = (candidate.rect.left + candidate.rect.right) / 2;
  final peerCenterX = (peerCandidate.rect.left + peerCandidate.rect.right) / 2;
  final tolerance =
      math.max(candidate.rect.width, peerCandidate.rect.width) * 0.75 + 0.0015;
  return (peerCenterX - centerX).abs() <= tolerance;
}

List<({String label, double confidence})?> _stabilizeRasterChordColumns(
  List<_RasterGlyphCandidate> candidates,
  List<({String label, double confidence})?> classifications,
  Map<int, ({String label, double confidence})> nativeLabels,
) {
  return [
    for (var index = 0; index < candidates.length; index += 1)
      () {
        final current = classifications[index] ?? nativeLabels[index];
        if (current == null || current.confidence >= 0.62) return current;
        final bare = current.label.replaceAll(RegExp(r'[()]'), '');
        if (current.confidence < 0.35 || !RegExp(r'^\d{1,2}$').hasMatch(bare)) {
          return current;
        }
        final alignedLines = <int>{candidates[index].lineIndex};
        for (var peerIndex = 0; peerIndex < candidates.length; peerIndex += 1) {
          if (peerIndex == index ||
              candidates[peerIndex].lineIndex == candidates[index].lineIndex ||
              !_rasterCandidatesAreColumnAligned(
                candidates,
                index,
                peerIndex,
              )) {
            continue;
          }
          final peer = classifications[peerIndex] ?? nativeLabels[peerIndex];
          if (peer == null || peer.confidence < 0.62) continue;
          final peerBare = peer.label.replaceAll(RegExp(r'[()]'), '');
          if (!RegExp(r'^\d{1,2}$').hasMatch(peerBare)) continue;
          alignedLines.add(candidates[peerIndex].lineIndex);
        }
        if (alignedLines.length < 3) return current;
        final sortedLines = alignedLines.toList()..sort();
        final hasConsecutiveThree = [
          for (var start = 0; start <= sortedLines.length - 3; start += 1)
            sortedLines[start + 1] == sortedLines[start] + 1 &&
                sortedLines[start + 2] == sortedLines[start] + 2,
        ].contains(true);
        return hasConsecutiveThree
            ? (label: current.label, confidence: 0.70)
            : current;
      }(),
  ];
}

List<({String label, double confidence})?> _stabilizeRasterSustainColumns(
  List<_RasterGlyphCandidate> candidates,
  List<({String label, double confidence})?> classifications,
  Map<int, ({String label, double confidence})> nativeLabels,
) {
  final parenthesized = [
    for (var index = 0; index < candidates.length; index += 1)
      () {
        final current = classifications[index] ?? nativeLabels[index];
        if (current == null ||
            !RegExp(r'^\(\d{1,2}\)$').hasMatch(current.label)) {
          return classifications[index];
        }
        if (current.confidence >= 0.62) return current;
        final hasReliableParenthesizedPeer =
            [
              for (
                var peerIndex = 0;
                peerIndex < candidates.length;
                peerIndex += 1
              )
                peerIndex,
            ].any((peerIndex) {
              if (peerIndex == index ||
                  candidates[peerIndex].lineIndex ==
                      candidates[index].lineIndex ||
                  !_rasterCandidatesAreColumnAligned(
                    candidates,
                    index,
                    peerIndex,
                  )) {
                return false;
              }
              final peer =
                  classifications[peerIndex] ?? nativeLabels[peerIndex];
              return peer != null &&
                  peer.confidence >= 0.62 &&
                  RegExp(r'^\(\d{1,2}\)$').hasMatch(peer.label);
            });
        return hasReliableParenthesizedPeer
            ? (label: current.label, confidence: 0.70)
            : classifications[index];
      }(),
  ];

  return [
    for (var index = 0; index < candidates.length; index += 1)
      () {
        final current = parenthesized[index] ?? nativeLabels[index];
        if (current == null || current.label.startsWith('(')) return current;
        final bare = current.label.replaceAll(RegExp(r'[()]'), '');
        if (!RegExp(r'^\d{1,2}$').hasMatch(bare)) return current;
        final alignedSustainLines = <int>{};
        for (var peerIndex = 0; peerIndex < candidates.length; peerIndex += 1) {
          if (peerIndex == index ||
              candidates[peerIndex].lineIndex == candidates[index].lineIndex) {
            continue;
          }
          final peer = parenthesized[peerIndex] ?? nativeLabels[peerIndex];
          if (peer == null ||
              peer.confidence < 0.62 ||
              !RegExp(r'^\(\d{1,2}\)$').hasMatch(peer.label)) {
            continue;
          }
          if (!_rasterCandidatesAreColumnAligned(
            candidates,
            index,
            peerIndex,
          )) {
            continue;
          }
          alignedSustainLines.add(candidates[peerIndex].lineIndex);
        }
        // A tied chord is one physical column. Two independently recognized
        // parenthesized peers establish that the intervening low-confidence
        // digit is another sustain, without assuming a string count or pitch.
        if (alignedSustainLines.length < 2) return current;
        return (label: '($bare)', confidence: 0.70);
      }(),
  ];
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
  // Keep thin ties/slides from joining a fret to the next note. Multi-digit
  // frets are joined explicitly after their individual ink components have
  // been isolated.
  final mergeGap = math.max(2, (spacingPixels * 0.12).round());
  final maximumWidth = math.max(8, (spacingPixels * 2.4).round());
  final minimumColumnInk = math.max(2, (spacingPixels * 0.2).ceil());
  final barPixels = [
    for (final bar in system.barLines) (bar * image.width).round(),
  ];
  final contentLeft = barPixels.length >= 2 ? barPixels.first + 2 : 0;
  final contentRight = barPixels.length >= 2 ? barPixels.last - 2 : image.width;
  final candidates = <_RasterGlyphCandidate>[];

  for (
    var lineIndex = 0;
    lineIndex < system.stringLines.length;
    lineIndex += 1
  ) {
    final normalizedLine = system.stringLines[lineIndex];
    final lineY = (normalizedLine * image.height).round();
    final bandTop = math.max(0, lineY - halfBand);
    // Songsterr draws tied/parenthesized sustain frets slightly below the
    // lowest string. Widen only that outer half-band, but stop before the
    // rhythm stems below it. The previous two-string-spacing reach joined
    // ordinary frets to their rhythm stems and rejected the whole component.
    final lowerReach = lineIndex == system.stringLines.length - 1
        ? math.max(halfBand, (spacingPixels * 0.95).round())
        : halfBand;
    final bandBottom = math.min(image.height, lineY + lowerReach + 1);
    final occupiedColumns = <int>[];
    for (var x = 0; x < image.width; x += 1) {
      if (x < contentLeft || x > contentRight) continue;
      if (barPixels.any((bar) => (bar - x).abs() <= 1)) continue;
      var columnInk = 0;
      for (var y = bandTop; y < bandBottom; y += 1) {
        if ((y - lineY).abs() <= 1) continue;
        if ((_luminance(image.getPixel(x, y)) - background).abs() >=
            threshold) {
          columnInk += 1;
        }
      }
      // Slides, ties, and staff remnants are typically only one or two pixels
      // thick. Requiring a short vertical run keeps them from joining two fret
      // glyphs into one oversized component while retaining digit stems.
      if (columnInk >= minimumColumnInk) occupiedColumns.add(x);
    }
    final clusters = _clusterCoordinatesWithGap(occupiedColumns, mergeGap);
    for (final cluster in clusters) {
      final glyphLeft = cluster.first;
      final glyphRight = cluster.last + 1;
      final glyphWidth = glyphRight - glyphLeft;
      if (glyphWidth > maximumWidth) continue;
      final glyphCenter = (glyphLeft + glyphRight) / 2;
      final isNarrowBarFragment =
          glyphWidth <= spacingPixels * 0.45 &&
          barPixels.any(
            (bar) => (bar - glyphCenter).abs() <= spacingPixels * 0.3,
          );
      if (isNarrowBarFragment) continue;
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
          inkBottom - inkTop < spacingPixels * 0.48 ||
          inkBottom - inkTop > spacingPixels * 1.3) {
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
      var stringInkColumns = 0;
      for (var x = glyphLeft; x < glyphRight; x += 1) {
        if ((_luminance(image.getPixel(x, lineY)) - background).abs() >=
            threshold) {
          stringInkColumns += 1;
        }
      }
      // Songsterr and many notation programs interrupt the string behind fret
      // numbers. Preserve that intact glyph. Only erase a line when it truly
      // spans most of the candidate (the 9mm-style source where strings run
      // through digits), then reconnect the digit stroke locally.
      final eraseStringLine = stringInkColumns / glyphWidth >= 0.6;
      for (var y = patchTop; y < patchBottom; y += 1) {
        for (var x = patchLeft; x < patchRight; x += 1) {
          // Padding gives isolated OCR breathing room; it must remain white.
          // Copying neighbouring pixels into that padding pulled tie tails and
          // rhythm stems into parenthesized sustain glyphs, making `(0)` too
          // wide to classify and promoting those notation fragments instead.
          if (x < glyphLeft || x >= glyphRight) continue;
          if (eraseStringLine && (y - lineY).abs() <= 1) continue;
          if ((_luminance(image.getPixel(x, y)) - background).abs() >=
              threshold) {
            patch.setPixel(x - patchLeft, y - patchTop, img.ColorRgb8(0, 0, 0));
          }
        }
      }
      if (eraseStringLine) {
        _repairRasterGlyphAcrossStringLine(patch, lineY - patchTop);
      }
      candidates.add(
        _RasterGlyphCandidate(
          image: patch,
          lineIndex: lineIndex,
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
  return _joinAdjacentRasterDigits(candidates, spacingPixels, image.width);
}

/// Reconnects only ink strokes that continue on both sides of the removed
/// tablature string. The detector deliberately erases the string line so it
/// cannot become part of every digit; without this small inpaint, however,
/// closed glyphs such as 0 and 9 are split into shapes that OCR commonly reads
/// as 7. Requiring nearby ink above and below avoids redrawing the staff line
/// through the whole token patch.
void _repairRasterGlyphAcrossStringLine(img.Image glyph, int stringY) {
  if (stringY < 2 || stringY >= glyph.height - 2) return;
  bool hasInkNear(int centerX, int y) {
    if (y < 0 || y >= glyph.height) return false;
    for (
      var x = math.max(0, centerX - 1);
      x <= math.min(glyph.width - 1, centerX + 1);
      x += 1
    ) {
      if (_luminance(glyph.getPixel(x, y)) < 160) return true;
    }
    return false;
  }

  for (var x = 0; x < glyph.width; x += 1) {
    final continuesAbove =
        hasInkNear(x, stringY - 2) || hasInkNear(x, stringY - 3);
    final continuesBelow =
        hasInkNear(x, stringY + 2) || hasInkNear(x, stringY + 3);
    if (!continuesAbove || !continuesBelow) continue;
    for (var y = stringY - 1; y <= stringY + 1; y += 1) {
      glyph.setPixel(x, y, img.ColorRgb8(0, 0, 0));
    }
  }
}

List<_RasterGlyphCandidate> _joinAdjacentRasterDigits(
  List<_RasterGlyphCandidate> candidates,
  double spacingPixels,
  int sourceWidth,
) {
  if (candidates.length < 2) return candidates;
  final sorted = [...candidates]
    ..sort((left, right) {
      final line = left.lineIndex.compareTo(right.lineIndex);
      return line != 0 ? line : left.rect.left.compareTo(right.rect.left);
    });
  final joined = <_RasterGlyphCandidate>[];
  var current = sorted.first;
  for (var index = 1; index < sorted.length; index += 1) {
    final next = sorted[index];
    final currentCenter = (current.rect.top + current.rect.bottom) / 2;
    final nextCenter = (next.rect.top + next.rect.bottom) / 2;
    final normalizedHeight = math.max(current.rect.height, next.rect.height);
    final horizontalGapPixels =
        (next.rect.left - current.rect.right) * sourceWidth;
    final sameBaseline =
        (currentCenter - nextCenter).abs() <= normalizedHeight * 0.3;
    final canJoin =
        current.lineIndex == next.lineIndex &&
        sameBaseline &&
        horizontalGapPixels >= -spacingPixels * 0.45 &&
        horizontalGapPixels <= spacingPixels * 0.35;
    if (!canJoin) {
      joined.add(current);
      current = next;
      continue;
    }

    final gap = horizontalGapPixels.round();
    final top = math.min(current.rect.top, next.rect.top);
    final bottom = math.max(current.rect.bottom, next.rect.bottom);
    final height = math.max(current.image.height, next.image.height);
    final combined = img.Image(
      width: current.image.width + gap + next.image.width,
      height: height,
    );
    img.fill(combined, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(combined, current.image, blend: img.BlendMode.direct);
    img.compositeImage(
      combined,
      next.image,
      dstX: current.image.width + gap,
      blend: img.BlendMode.direct,
    );
    // Keep greedily extending the current token. This is required for a
    // three-component parenthesized sustain such as `(0)`; the former
    // pairwise loop joined only two pieces and emitted the final parenthesis
    // as another fret.
    current = _RasterGlyphCandidate(
      image: combined,
      lineIndex: current.lineIndex,
      rect: NormalizedRect(
        current.rect.left,
        top,
        next.rect.right,
        bottom,
      ).clamp(),
    );
  }
  joined.add(current);
  return joined;
}

class _RasterGlyphCandidate {
  const _RasterGlyphCandidate({
    required this.image,
    required this.rect,
    required this.lineIndex,
  });

  final img.Image image;
  final NormalizedRect rect;
  final int lineIndex;
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
  final correctedLabel = _correctRasterZeroEight(bestLabel, image);
  if (correctedLabel != bestLabel) {
    // The compact Songsterr zero is closer to the bundled Arial `8` template
    // than to Arial `0`, especially after the staff line has been removed.
    // Topology is the stable distinction: an intact 8 has two enclosed loops,
    // while the source zeroes in bars 98/137/138 have one. Keep this correction
    // at glyph classification so every caller uses the same label.
    return (
      label: correctedLabel,
      confidence: math.max(0.68, confidence * 0.96),
    );
  }
  return (label: bestLabel, confidence: confidence);
}

({String label, double confidence})? _classifyNarrowRasterOne(img.Image image) {
  final normalized = _normalizeRasterGlyph(image);
  if (normalized == null || normalized.aspectRatio > 0.32) return null;
  if (_countEnclosedRasterGlyphHoles(image) != 0) return null;
  if (!_looksLikeVerticalRasterStem(image)) return null;
  // The compact Songsterr `1` can collapse to a two-pixel stem after the tab
  // line is removed. Arial template matching then alternates between null and
  // `7`, especially inside stacked chords and beside slide curves. A true 7
  // in the same source is materially wider (about 0.39-0.43 of its height).
  // Keep this below the native-disagreement threshold so another font's OCR
  // can still correct a genuinely narrow 7.
  return (label: '1', confidence: 0.70);
}

bool _looksLikeVerticalRasterStem(img.Image image) {
  final bounds = _rasterGlyphInkBounds(image);
  if (bounds == null) return false;
  final width = bounds.$3 - bounds.$1;
  final height = bounds.$4 - bounds.$2;
  if (width <= 0 || height < 4) return false;

  var strongestColumn = 0;
  for (var x = bounds.$1; x < bounds.$3; x += 1) {
    var ink = 0;
    for (var y = bounds.$2; y < bounds.$4; y += 1) {
      if (_luminance(image.getPixel(x, y)) < 160) ink += 1;
    }
    strongestColumn = math.max(strongestColumn, ink);
  }
  if (strongestColumn / height < 0.72) return false;

  double inkCenterX(int top, int bottom) {
    var weightedX = 0.0;
    var ink = 0;
    for (var y = top; y < bottom; y += 1) {
      for (var x = bounds.$1; x < bounds.$3; x += 1) {
        if (_luminance(image.getPixel(x, y)) >= 160) continue;
        weightedX += x;
        ink += 1;
      }
    }
    return ink == 0 ? double.nan : weightedX / ink;
  }

  final third = math.max(1, height ~/ 3);
  final upperCenter = inkCenterX(bounds.$2, bounds.$2 + third);
  final lowerCenter = inkCenterX(bounds.$4 - third, bounds.$4);
  if (upperCenter.isNaN || lowerCenter.isNaN) return false;
  // A slide fragment can be just as narrow as `1`, but its ink travels across
  // the crop. Require the dominant stroke to remain vertically aligned.
  return (upperCenter - lowerCenter).abs() <= math.max(0.75, width * 0.25);
}

/// Disambiguates the visually similar compact zero and eight used by raster
/// tab sources. Exposed for a typography-level regression fixture.
String correctVisualTabRasterZeroEight(String candidate, Uint8List glyphBytes) {
  final image = img.decodeImage(glyphBytes);
  if (image == null) throw const FormatException('Raster glyph is invalid.');
  return _correctRasterZeroEight(candidate, img.bakeOrientation(image));
}

String _correctRasterZeroEight(String candidate, img.Image image) =>
    candidate == '8' && _countEnclosedRasterGlyphHoles(image) < 2
    ? '0'
    : candidate;

int _countEnclosedRasterGlyphHoles(img.Image image) {
  final bounds = _rasterGlyphInkBounds(image);
  if (bounds == null) return 0;
  final width = bounds.$3 - bounds.$1;
  final height = bounds.$4 - bounds.$2;
  if (width < 3 || height < 3) return 0;
  final background = List<bool>.filled(width * height, false);
  for (var y = 0; y < height; y += 1) {
    for (var x = 0; x < width; x += 1) {
      background[y * width + x] =
          _luminance(image.getPixel(bounds.$1 + x, bounds.$2 + y)) >= 160;
    }
  }
  final visited = List<bool>.filled(background.length, false);
  var holes = 0;
  for (var start = 0; start < background.length; start += 1) {
    if (!background[start] || visited[start]) continue;
    final queue = <int>[start];
    visited[start] = true;
    var touchesEdge = false;
    var area = 0;
    for (var cursor = 0; cursor < queue.length; cursor += 1) {
      final current = queue[cursor];
      final x = current % width;
      final y = current ~/ width;
      area += 1;
      touchesEdge =
          touchesEdge || x == 0 || y == 0 || x == width - 1 || y == height - 1;
      for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final nextX = x + dx;
        final nextY = y + dy;
        if (nextX < 0 || nextX >= width || nextY < 0 || nextY >= height) {
          continue;
        }
        final next = nextY * width + nextX;
        if (!background[next] || visited[next]) continue;
        visited[next] = true;
        queue.add(next);
      }
    }
    if (!touchesEdge && area >= 2) holes += 1;
  }
  return holes;
}

({String label, double confidence})? _classifyParenthesizedRasterGlyph(
  img.Image image,
) {
  final bounds = _rasterGlyphInkBounds(image);
  if (bounds == null) return null;
  final width = bounds.$3 - bounds.$1;
  final height = bounds.$4 - bounds.$2;
  // Parentheses make the complete glyph almost square. Ordinary fret digits
  // remain materially narrower even when the tablature line is repaired.
  if (width < 7 || height < 7 || width / height < 0.62) return null;
  if (_countSubstantialInkComponents(image, bounds) < 3) return null;

  bool regionHasInk(int left, int right) {
    for (var y = bounds.$2; y < bounds.$4; y += 1) {
      for (var x = left; x < right; x += 1) {
        if (_luminance(image.getPixel(x, y)) < 160) return true;
      }
    }
    return false;
  }

  final leftEnd = bounds.$1 + (width * 0.28).round();
  final centerLeft = bounds.$1 + (width * 0.3).round();
  final centerRight = bounds.$1 + (width * 0.7).round();
  final rightStart = bounds.$1 + (width * 0.72).round();
  if (!regionHasInk(bounds.$1, leftEnd) ||
      !regionHasInk(centerLeft, centerRight) ||
      !regionHasInk(rightStart, bounds.$3)) {
    return null;
  }

  final center = img.copyCrop(
    image,
    x: centerLeft,
    y: bounds.$2,
    width: math.max(1, centerRight - centerLeft),
    height: height,
  );
  final classified = _classifyRasterGlyph(center);
  if (classified == null || !RegExp(r'^\d{1,2}$').hasMatch(classified.label)) {
    return null;
  }
  return (
    label: '(${classified.label})',
    confidence: math.max(0.72, classified.confidence * 0.92),
  );
}

({String label, double confidence})? _classifySeparatedRasterDigits(
  img.Image image,
) {
  final bounds = _rasterGlyphInkBounds(image);
  if (bounds == null) return null;
  final height = bounds.$4 - bounds.$2;
  if (height < 5) return null;
  final occupied = <int>[];
  for (var x = bounds.$1; x < bounds.$3; x += 1) {
    var ink = 0;
    for (var y = bounds.$2; y < bounds.$4; y += 1) {
      if (_luminance(image.getPixel(x, y)) < 160) ink += 1;
    }
    if (ink >= math.max(1, (height * 0.08).round())) occupied.add(x);
  }
  final clusters = _clusterCoordinatesWithGap(occupied, 2)
      .where((cluster) {
        var top = bounds.$4;
        var bottom = bounds.$2;
        var area = 0;
        for (var y = bounds.$2; y < bounds.$4; y += 1) {
          for (var x = cluster.first; x <= cluster.last; x += 1) {
            if (_luminance(image.getPixel(x, y)) >= 160) continue;
            top = math.min(top, y);
            bottom = math.max(bottom, y + 1);
            area += 1;
          }
        }
        return area >= 3 && bottom - top >= height * 0.58;
      })
      .toList(growable: false);
  if (clusters.length != 2) return null;

  final labels = <String>[];
  final confidences = <double>[];
  for (final cluster in clusters) {
    final left = math.max(bounds.$1, cluster.first - 1);
    final right = math.min(bounds.$3, cluster.last + 2);
    final part = img.copyCrop(
      image,
      x: left,
      y: bounds.$2,
      width: right - left,
      height: height,
    );
    final classified = part.width <= height * 0.24
        ? (label: '1', confidence: 0.80)
        : _classifyRasterGlyph(part);
    if (classified == null || !RegExp(r'^\d$').hasMatch(classified.label)) {
      return null;
    }
    labels.add(classified.label);
    confidences.add(classified.confidence);
  }
  final label = labels.join();
  final fret = int.tryParse(label);
  if (fret == null || fret > 36) return null;
  return (
    label: label,
    confidence: math.max(0.72, confidences.reduce(math.min) * 0.92),
  );
}

int _countSubstantialInkComponents(
  img.Image image,
  (int, int, int, int) bounds,
) {
  final width = bounds.$3 - bounds.$1;
  final height = bounds.$4 - bounds.$2;
  final ink = List<bool>.filled(width * height, false);
  var totalInk = 0;
  for (var y = 0; y < height; y += 1) {
    for (var x = 0; x < width; x += 1) {
      final value =
          _luminance(image.getPixel(bounds.$1 + x, bounds.$2 + y)) < 160;
      ink[y * width + x] = value;
      if (value) totalInk += 1;
    }
  }
  final visited = List<bool>.filled(ink.length, false);
  final minimumArea = math.max(2, (totalInk * 0.055).round());
  var substantial = 0;
  for (var start = 0; start < ink.length; start += 1) {
    if (!ink[start] || visited[start]) continue;
    final queue = <int>[start];
    visited[start] = true;
    var area = 0;
    var top = height;
    var bottom = 0;
    for (var cursor = 0; cursor < queue.length; cursor += 1) {
      final current = queue[cursor];
      final x = current % width;
      final y = current ~/ width;
      area += 1;
      top = math.min(top, y);
      bottom = math.max(bottom, y + 1);
      for (var dy = -1; dy <= 1; dy += 1) {
        for (var dx = -1; dx <= 1; dx += 1) {
          if (dx == 0 && dy == 0) continue;
          final nextX = x + dx;
          final nextY = y + dy;
          if (nextX < 0 || nextX >= width || nextY < 0 || nextY >= height) {
            continue;
          }
          final next = nextY * width + nextX;
          if (!ink[next] || visited[next]) continue;
          visited[next] = true;
          queue.add(next);
        }
      }
    }
    if (area >= minimumArea && bottom - top >= height * 0.32) {
      substantial += 1;
    }
  }
  return substantial;
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
    this.openingSignatureRects = const [],
    this.confidence = 1,
  });

  final NormalizedRect rect;
  final List<double> stringLines;
  final List<double> barLines;
  final List<VisualConnectedNotationRisk> connectedNotationRisks;
  final List<NormalizedRect> openingSignatureRects;
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
          centerY > detected.rect.bottom + spacing * 2.0) {
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
    if (sourceType == VisualTabSourceType.rasterOcr &&
        detected.openingSignatureRects.isNotEmpty) {
      tokens.removeWhere(
        (token) =>
            token.isFretLike &&
            detected.openingSignatureRects.any(
              (rect) => _candidateRectsOverlap(rect, token.rect),
            ),
      );
    }
    for (var index = 0; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (!token.isFretLike) continue;
      final overlapsConnectedNotation = detected.connectedNotationRisks.any(
        (risk) => _candidateRectsOverlap(risk.rect, token.rect),
      );
      if (!overlapsConnectedNotation) continue;
      tokens[index] = token.copyWith(
        kind: VisualTabTokenKind.ambiguous,
        clearStringIndex: true,
        enabled: false,
      );
    }
    if (detected.barLines.isNotEmpty) {
      final firstBar = detected.barLines.first;
      final timeSignatureIndexes = <int>{};
      for (var index = 0; index < tokens.length; index += 1) {
        final token = tokens[index];
        if (!token.isFretLike || !RegExp(r'^\d$').hasMatch(token.text)) {
          continue;
        }
        final centerX = (token.rect.left + token.rect.right) / 2;
        final nextBar = detected.barLines.length > 1
            ? detected.barLines[1]
            : firstBar + spacing * 8;
        final directNearOpening =
            centerX <= detected.rect.left + spacing * 0.85 ||
            (centerX - firstBar).abs() <= spacing * 0.25;
        final largeGlyph = token.rect.height >= spacing * 1.05;
        final inOpeningSignatureZone =
            largeGlyph &&
            centerX >= firstBar - spacing &&
            centerX <= firstBar + (nextBar - firstBar) * 0.45;
        final nearOpening = directNearOpening || inOpeningSignatureZone;
        if (!nearOpening) continue;
        final isStackedTimeSignature = tokens.any((other) {
          if (identical(other, token) ||
              !other.isFretLike ||
              other.text != token.text ||
              other.stringIndex == token.stringIndex) {
            return false;
          }
          final otherCenterX = (other.rect.left + other.rect.right) / 2;
          final peerIsLarge = other.rect.height >= spacing * 1.05;
          return (directNearOpening || peerIsLarge) &&
              (otherCenterX - centerX).abs() <= spacing * 0.20;
        });
        if (!isStackedTimeSignature) continue;
        timeSignatureIndexes.add(index);
      }
      for (final index
          in timeSignatureIndexes.toList()
            ..sort((left, right) => right.compareTo(left))) {
        tokens.removeAt(index);
      }
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
  if (!RegExp(r'^(?:\(\d+\)|\d+)$').hasMatch(text)) {
    return VisualTabTokenKind.ambiguous;
  }
  final numericText = text.startsWith('(')
      ? text.substring(1, text.length - 1)
      : text;
  final fret = int.tryParse(numericText);
  // Bass frets outside the transformer's supported 0..36 range are labels,
  // measure numbers, or OCR errors. Never allow them to enter a transform as
  // musical fret data (the real fixture previously treated measure 44 as a
  // fret and aborted the entire Drop-D -> BEADG operation).
  if (fret == null || fret > 36) return VisualTabTokenKind.measureNumber;
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

/// Detects complete tab systems without assuming a particular string count.
///
/// The image is decoded and scanned once; supported counts are compared only
/// against the resulting horizontal-line coordinates. This keeps Gig reflow
/// and future count-independent consumers on the same geometry rules as the
/// explicitly configured analysis workflow.
VisualTabGeometry detectVisualTabGeometryAnyStringCount(
  Uint8List bytes, {
  required NormalizedRect crop,
}) {
  return _detectVisualTabGeometryFromImage(
    _decodeVisualTabImage(bytes),
    crop: crop,
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
  return _detectVisualTabGeometryFromImage(
    sourceImage,
    crop: crop,
    expectedStringCount: expectedStringCount,
  );
}

VisualTabGeometry _detectVisualTabGeometryFromImage(
  img.Image sourceImage, {
  required NormalizedRect crop,
  int? expectedStringCount,
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
  final lineGroups = expectedStringCount == null
      ? _findSupportedStringLineGroups(clusteredRows, image.height)
      : _findEquallySpacedGroups(
          clusteredRows,
          expectedStringCount,
          image.height,
        );
  final detectedOtherCounts = expectedStringCount != null && lineGroups.isEmpty
      ? [
          for (
            var count = minimumVisualTabStringCount;
            count <= maximumVisualTabStringCount;
            count += 1
          )
            if (count != expectedStringCount &&
                _findEquallySpacedGroups(
                  clusteredRows,
                  count,
                  image.height,
                ).isNotEmpty)
              count,
        ]
      : const <int>[];
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
    final rawConnectedNotationRisks = _detectConnectedNotationRisks(
      image,
      background: background,
      threshold: threshold,
      lines: lines,
      barLines: barLines,
    );
    final normalizedRect = _safeNormalizedRect(
      0,
      systemTop / image.height,
      1,
      systemBottom / image.height,
    );
    final normalizedLines = [for (final line in lines) line / image.height];
    final normalizedBarLines = [
      for (final line in barLines) line / image.width,
    ];
    final provisionalSystem = VisualTabSystemGeometry(
      rect: normalizedRect,
      stringLines: normalizedLines,
      barLines: normalizedBarLines,
      connectedNotationRisks: rawConnectedNotationRisks,
      confidence: _spacingConfidence(lines),
    );
    final openingSignatureRects = _detectOpeningSignatureRects(
      _detectRasterGlyphCandidates(
        image,
        stripCrop: const NormalizedRect.full(),
        system: provisionalSystem,
      ),
      connectedNotationRisks: rawConnectedNotationRisks,
      barLines: normalizedBarLines,
      stringSpacing: spacingPixels / image.width,
      systemRect: normalizedRect,
      stringCount: lines.length,
    );
    final connectedNotationRisks = rawConnectedNotationRisks
        .where(
          (risk) => !openingSignatureRects.any(
            (signature) => _candidateRectsOverlap(signature, risk.rect),
          ),
        )
        .toList(growable: false);
    systems.add(
      VisualTabSystemGeometry(
        rect: normalizedRect,
        stringLines: normalizedLines,
        barLines: normalizedBarLines,
        connectedNotationRisks: connectedNotationRisks,
        openingSignatureRects: openingSignatureRects,
        confidence: _spacingConfidence(lines),
      ),
    );
  }
  return VisualTabGeometry(
    systems: systems,
    warnings: [
      if (systems.isEmpty)
        if (expectedStringCount == null)
          'Raster geometry did not find a supported evenly spaced string system.'
        else if (detectedOtherCounts.length == 1)
          'Raster geometry found ${detectedOtherCounts.single} strings while '
              '$expectedStringCount source strings were selected.'
        else
          'Raster geometry did not find $expectedStringCount evenly spaced '
              'string lines.',
    ],
  );
}

List<List<double>> _findSupportedStringLineGroups(
  List<double> rows,
  int imageHeight,
) {
  final candidates =
      <List<double>>[
        for (
          var count = minimumVisualTabStringCount;
          count <= maximumVisualTabStringCount;
          count += 1
        )
          ..._findEquallySpacedGroups(rows, count, imageHeight),
      ]..sort((left, right) {
        final confidence = _spacingConfidence(
          right,
        ).compareTo(_spacingConfidence(left));
        if (confidence != 0) return confidence;
        return right.length.compareTo(left.length);
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
    final upperLine = lines[gapIndex];
    final lowerLine = lines[gapIndex + 1];
    final spacing = lowerLine - upperLine;
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
      final searchRadius = math.max(5, (spacing * 1.15).round());
      final searchLeft = (centerX.round() - searchRadius).clamp(
        0,
        image.width - 1,
      );
      final searchRight = (centerX.round() + searchRadius).clamp(
        searchLeft + 1,
        image.width,
      );
      final lineBand = math.max(1, (spacing * 0.08).round());

      List<int> inkColumnsNear(double y) {
        final columns = <int>[];
        final yStart = (y.round() - lineBand).clamp(0, image.height - 1);
        final yEnd = (y.round() + lineBand).clamp(yStart + 1, image.height);
        for (var x = searchLeft; x < searchRight; x += 1) {
          var touches = false;
          for (var row = yStart; row < yEnd; row += 1) {
            if (isInk(x, row)) {
              touches = true;
              break;
            }
          }
          if (touches) columns.add(x);
        }
        return columns;
      }

      List<int> nearestInkCluster(List<int> columns) {
        final clusters = _clusterCoordinatesWithGap(columns, 2);
        if (clusters.isEmpty) return const [];
        clusters.sort((left, right) {
          double distance(List<int> cluster) =>
              ((cluster.first + cluster.last) / 2 - centerX).abs();
          return distance(left).compareTo(distance(right));
        });
        return clusters.first;
      }

      // Sample just inside the gap rather than on the string pixels. Sampling
      // the strings themselves would make every full-width horizontal line
      // look connected to a narrow rest stem.
      final upperColumns = nearestInkCluster(
        inkColumnsNear(upperLine + spacing * 0.30),
      );
      final lowerColumns = nearestInkCluster(
        inkColumnsNear(lowerLine - spacing * 0.30),
      );
      if (upperColumns.isEmpty || lowerColumns.isEmpty) continue;
      final upperCenter =
          upperColumns.reduce((a, b) => a + b) / upperColumns.length;
      final lowerCenter =
          lowerColumns.reduce((a, b) => a + b) / lowerColumns.length;
      final horizontalTravel = (upperCenter - lowerCenter).abs();
      final combinedLeft = math.min(upperColumns.first, lowerColumns.first);
      final combinedRight = math.max(upperColumns.last, lowerColumns.last);
      final horizontalSpan = combinedRight - combinedLeft + 1;

      // A rest stem or a stacked time-signature digit can cross the midpoint
      // between strings, but it does not connect musical ink at both strings
      // with meaningful horizontal or diagonal travel. Only surface the seam
      // when moving one string could visibly tear such a connector.
      final hasConnectorShape =
          horizontalTravel >= math.max(4.0, spacing * 0.48) ||
          horizontalSpan >= math.max(10.0, spacing * 1.25);
      if (!hasConnectorShape) continue;

      final left = (combinedLeft - 2).clamp(0, image.width - 1);
      final right = (combinedRight + 3).clamp(left + 1, image.width);
      final top = (upperLine - lineBand).round().clamp(0, image.height - 1);
      final bottom = (lowerLine + lineBand + 1).round().clamp(
        top + 1,
        image.height,
      );
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

List<NormalizedRect> _detectOpeningSignatureRects(
  List<_RasterGlyphCandidate> candidates, {
  required List<VisualConnectedNotationRisk> connectedNotationRisks,
  required List<double> barLines,
  required double stringSpacing,
  required NormalizedRect systemRect,
  required int stringCount,
}) {
  if (candidates.isEmpty ||
      connectedNotationRisks.isEmpty ||
      barLines.isEmpty) {
    return const [];
  }
  final opening =
      candidates
          .where((candidate) {
            final centerX = (candidate.rect.left + candidate.rect.right) / 2;
            return _isOpeningSignatureX(centerX, barLines, stringSpacing);
          })
          .toList(growable: false)
        ..sort((left, right) {
          final leftCenter = (left.rect.left + left.rect.right) / 2;
          final rightCenter = (right.rect.left + right.rect.right) / 2;
          return leftCenter.compareTo(rightCenter);
        });
  if (opening.isEmpty) return const [];
  final columns = <List<_RasterGlyphCandidate>>[];
  for (final candidate in opening) {
    final centerX = (candidate.rect.left + candidate.rect.right) / 2;
    if (columns.isEmpty) {
      columns.add([candidate]);
      continue;
    }
    final previous = columns.last.last;
    final previousCenter = (previous.rect.left + previous.rect.right) / 2;
    if ((centerX - previousCenter).abs() <= stringSpacing) {
      columns.last.add(candidate);
    } else {
      columns.add([candidate]);
    }
  }

  final minimumCoveredStrings = math.min(4, stringCount);
  final signatures = <NormalizedRect>[];
  for (final column in columns) {
    final coveredStrings = column
        .map((candidate) => candidate.lineIndex)
        .toSet();
    if (coveredStrings.length < minimumCoveredStrings) continue;
    final left = column
        .map((candidate) => candidate.rect.left)
        .reduce(math.min);
    final right = column
        .map((candidate) => candidate.rect.right)
        .reduce(math.max);
    final centerX = (left + right) / 2;
    final intersectsPhysicalSeam = connectedNotationRisks.any((risk) {
      final riskCenter = (risk.rect.left + risk.rect.right) / 2;
      return (riskCenter - centerX).abs() <= stringSpacing * 1.5;
    });
    if (!intersectsPhysicalSeam) continue;
    signatures.add(
      _safeNormalizedRect(
        left - stringSpacing * 0.55,
        systemRect.top,
        right + stringSpacing * 0.55,
        systemRect.bottom,
      ),
    );
  }
  return signatures;
}

bool _isOpeningSignatureX(double x, List<double> barLines, double spacing) {
  if (barLines.isEmpty) return false;
  final firstBar = barLines.first;
  final nextBar = barLines.length > 1 ? barLines[1] : firstBar + spacing * 8;
  return x >= firstBar - spacing && x <= firstBar + (nextBar - firstBar) * 0.45;
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
    // Never accept a partial window from a larger tab system. Previously an
    // eight-string source analyzed as seven strings looked geometrically
    // valid because either seven-line subset was evenly spaced. Tokens then
    // mapped to the wrong strings and the omitted outer line was interpreted
    // as notation. Require the candidate to be a maximal equally spaced run.
    if (valid && start > 0) {
      final previousSpacing = group.first - rows[start - 1];
      if ((previousSpacing - spacing).abs() <= tolerance) valid = false;
    }
    if (valid && start + count < rows.length) {
      final nextSpacing = rows[start + count] - group.last;
      if ((nextSpacing - spacing).abs() <= tolerance) valid = false;
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
