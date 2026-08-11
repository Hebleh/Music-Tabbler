import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../domain/visual_chart_models.dart';
import '../domain/visual_tab_transform_models.dart';
import 'highlight_geometry.dart';
import 'service_contracts.dart';
import 'visual_deskew.dart';

class VisualTabTransformService {
  const VisualTabTransformService(this.library);

  final ChartLibrary library;

  Future<VisualChartDraft> apply({
    required VisualChartDraft draft,
    required List<VisualTabAnalysis> analyses,
    required VisualTabTransformConfiguration configuration,
  }) async {
    final baseStrips = draft.visualTabTransform?.baseStrips ?? draft.strips;
    final analysesByStrip = {
      for (final analysis in analyses) analysis.stripId: analysis,
    };
    if (baseStrips.any((strip) {
      final analysis = analysesByStrip[strip.id];
      return analysis == null || !analysis.isReviewed;
    })) {
      throw const FormatException(
        'Every original row must be reviewed. Run Raster / OCR all rows, then '
        'repair a blocked row or explicitly keep it unchanged.',
      );
    }
    final sustainResolution = _resolveSustainFretsAcrossRows(
      baseStrips,
      analysesByStrip,
    );

    final transformed = <VisualStrip>[];
    var relabelNextSystem = true;
    for (final strip in baseStrips) {
      final analysis = sustainResolution.byStrip[strip.id]!;
      if (analysis.keepUnchanged) {
        transformed.add(strip);
        continue;
      }
      final bytes = await File(
        library.assetPath(strip.assetHash, strip.assetExtension),
      ).readAsBytes();
      final rendered = await compute(_renderVisualTabSystems, {
        'bytes': bytes,
        'strip': strip.toJson(),
        'analysis': analysis.toJson(),
        'configuration': configuration.toJson(),
        'relabelFirstSystem': relabelNextSystem,
      });
      if (rendered.isNotEmpty) {
        relabelNextSystem = false;
      }
      for (var index = 0; index < rendered.length; index += 1) {
        final item = rendered[index];
        final imageBytes = item['bytes']! as Uint8List;
        final asset = await library.storeAsset(imageBytes, 'png');
        final renderedSystem = VisualTabSystem.fromJson(
          (item['system']! as Map).cast<String, Object?>(),
        );
        transformed.add(
          _transformedStrip(
            source: strip,
            system: renderedSystem,
            configuration: configuration,
            assetHash: asset.hash,
            width: item['width']! as int,
            height: item['height']! as int,
            insertionSeams:
                (item['insertionSeams'] as List?)
                    ?.map((value) => (value as num).toDouble())
                    .toList(growable: false) ??
                const [],
            insertionBandHeight:
                (item['insertionBandHeight'] as num?)?.toDouble() ?? 0,
          ),
        );
      }
    }
    if (transformed.isEmpty) {
      throw const FormatException(
        'No reviewed tablature systems were available to transform.',
      );
    }
    final record = VisualTabTransformRecord(
      id: draft.visualTabTransform?.id ?? IdFactory.next('visual_transform'),
      appliedAt: DateTime.now().toUtc(),
      baseStrips: List.unmodifiable(baseStrips),
      configuration: configuration.toJson(),
      analyses: sustainResolution.ordered
          .map((analysis) => analysis.toJson())
          .toList(),
      audit: [
        'Applied ${configuration.globalPitchChange >= 0 ? "+" : ""}'
            '${configuration.globalPitchChange} global pitch change.',
        if (configuration.selectedStringPitchChanges.isNotEmpty)
          'Used ${configuration.selectedStringPitchChanges.length} '
              'selected-string pitch override(s).',
        if (configuration.unusedTargetStrings.isNotEmpty)
          'Added ${configuration.unusedTargetStrings.length} unused target '
              'string(s): '
              '${configuration.unusedTargetStrings.map((index) => index + 1).join(', ')}.',
        if (sustainResolution.corrected > 0)
          'Resolved ${sustainResolution.corrected} parenthesized sustain '
              'fret(s) from the preceding played fret across source rows.',
        for (final analysis in sustainResolution.ordered)
          if (analysis.keepUnchanged)
            'Kept source row ${analysis.stripId} unchanged after explicit '
                'review because it had no usable detected fret tokens.',
        for (final route in configuration.routes)
          if (route.hasManualOverride && route.manualOffset != route.fretOffset)
            'Route ${route.sourceString + 1} -> '
                '${route.targetString + 1} uses a manual offset that '
                'does not match the calculated pitch.',
      ],
    );
    return draft.copyWith(
      strips: List.unmodifiable(transformed),
      visualTabTransform: record,
    );
  }

  VisualChartDraft remove(VisualChartDraft draft) {
    final transform = draft.visualTabTransform;
    if (transform == null) return draft;
    return draft.copyWith(
      strips: transform.baseStrips,
      clearVisualTabTransform: true,
    );
  }
}

({
  Map<String, VisualTabAnalysis> byStrip,
  List<VisualTabAnalysis> ordered,
  int corrected,
})
_resolveSustainFretsAcrossRows(
  List<VisualStrip> strips,
  Map<String, VisualTabAnalysis> analysesByStrip,
) {
  final lastFretByString = <int, int>{};
  final resolvedByStrip = <String, VisualTabAnalysis>{};
  final ordered = <VisualTabAnalysis>[];
  var corrected = 0;
  for (final strip in strips) {
    final analysis = analysesByStrip[strip.id]!;
    if (analysis.keepUnchanged) {
      lastFretByString.clear();
      resolvedByStrip[strip.id] = analysis;
      ordered.add(analysis);
      continue;
    }
    final systems = <VisualTabSystem>[];
    for (final system in analysis.systems) {
      final tokens = [...system.tokens];
      final tokenIndexes = List<int>.generate(tokens.length, (index) => index)
        ..sort(
          (left, right) =>
              tokens[left].rect.left.compareTo(tokens[right].rect.left),
        );
      for (final index in tokenIndexes) {
        final token = tokens[index];
        final stringIndex = token.stringIndex;
        if (!token.enabled || stringIndex == null) continue;
        if (token.kind == VisualTabTokenKind.deadNote) {
          lastFretByString.remove(stringIndex);
          continue;
        }
        if (token.kind != VisualTabTokenKind.fret) continue;
        final parsed = _parseFret(token.text);
        if (parsed == null) continue;
        var sourceFret = parsed.$1;
        final previous = lastFretByString[stringIndex];
        if (parsed.$2 && previous != null) {
          sourceFret = previous;
          if (parsed.$1 != previous) {
            tokens[index] = token.copyWith(text: '($previous)');
            corrected += 1;
          }
        }
        lastFretByString[stringIndex] = sourceFret;
      }
      systems.add(system.copyWith(tokens: tokens));
    }
    final resolved = analysis.copyWith(systems: systems);
    resolvedByStrip[strip.id] = resolved;
    ordered.add(resolved);
  }
  return (
    byStrip: Map.unmodifiable(resolvedByStrip),
    ordered: List.unmodifiable(ordered),
    corrected: corrected,
  );
}

VisualStrip _transformedStrip({
  required VisualStrip source,
  required VisualTabSystem system,
  required VisualTabTransformConfiguration configuration,
  required String assetHash,
  required int width,
  required int height,
  required List<double> insertionSeams,
  required double insertionBandHeight,
}) {
  NormalizedRect? mapAssetRect(NormalizedRect assetRect) {
    final cropLocal = assetRectToCropLocal(assetRect, source.crop);
    if (cropLocal == null) return null;
    final clipped = _intersection(cropLocal, system.rect);
    if (clipped == null) return null;
    return _mapSystemRect(
      clipped,
      system.rect,
      insertionSeams: insertionSeams,
      insertionBandHeight: insertionBandHeight,
    );
  }

  final mappedAnnotations = <VisualAnnotationStroke>[];
  for (final stroke in source.annotations) {
    final points = <NormalizedPoint>[];
    for (final point in stroke.points) {
      if (point.y < system.rect.top || point.y > system.rect.bottom) continue;
      final localY = (point.y - system.rect.top) / system.rect.height;
      points.add(
        NormalizedPoint(
          point.x,
          _mapSystemY(
            localY,
            insertionSeams: insertionSeams,
            insertionBandHeight: insertionBandHeight,
          ),
          pressure: point.pressure,
        ),
      );
    }
    if (points.length >= 2) {
      mappedAnnotations.add(
        VisualAnnotationStroke(
          id: stroke.id,
          points: points,
          colorArgb: stroke.colorArgb,
          width: stroke.width,
        ),
      );
    }
  }
  return VisualStrip(
    id: IdFactory.next('strip'),
    assetHash: assetHash,
    assetExtension: 'png',
    pixelWidth: width,
    pixelHeight: height,
    sourceAssetHash: source.sourceAssetHash,
    sourcePage: source.sourcePage,
    treatment: source.treatment,
    lyricBand: source.lyricBand == null
        ? null
        : mapAssetRect(source.lyricBand!),
    lyricContrast: source.lyricContrast,
    highlights: [
      for (final highlight in source.highlights)
        if (mapAssetRect(highlight.rect) case final rect?)
          VisualHighlight(id: highlight.id, rect: rect),
    ],
    annotations: mappedAnnotations,
    annotationsVisible: source.annotationsVisible,
    includeAnnotationsInPdf: source.includeAnnotationsInPdf,
  );
}

List<Map<String, Object?>> _renderVisualTabSystems(
  Map<String, Object?> request,
) {
  var source = img.decodeImage(request['bytes']! as Uint8List);
  if (source == null) {
    throw const FormatException('Stored chart image is invalid.');
  }
  source = img.bakeOrientation(source);
  final strip = VisualStrip.fromJson(
    (request['strip']! as Map).cast<String, Object?>(),
  );
  source = applyDeskewRotation(source, strip.deskewDegrees);
  final analysis = VisualTabAnalysis.fromJson(
    (request['analysis']! as Map).cast<String, Object?>(),
  );
  final configuration = VisualTabTransformConfiguration.fromJson(
    (request['configuration']! as Map).cast<String, Object?>(),
  );
  final relabelFirstSystem = request['relabelFirstSystem'] as bool? ?? false;
  final crop = _pixelRect(strip.crop, source.width, source.height);
  final cropped = img.copyCrop(
    source,
    x: crop.$1,
    y: crop.$2,
    width: crop.$3,
    height: crop.$4,
  );
  return [
    for (var index = 0; index < analysis.systems.length; index += 1)
      _renderSystem(
        cropped,
        _systemWithSafeVerticalGuard(analysis.systems, index),
        configuration,
        relabelTuning: relabelFirstSystem && index == 0,
      ),
  ];
}

VisualTabSystem _systemWithSafeVerticalGuard(
  List<VisualTabSystem> systems,
  int index,
) {
  final system = systems[index];
  if (system.stringLines.length < 2) return system;
  final spacing = _medianSpacing(system.stringLines);
  final topGuard = (spacing * 2.25).clamp(0.006, 0.04);
  final bottomGuard = (spacing * 1.5).clamp(0.004, 0.03);
  final previousBottom = index == 0 ? 0.0 : systems[index - 1].rect.bottom;
  final nextTop = index + 1 == systems.length
      ? 1.0
      : systems[index + 1].rect.top;
  final top = math.max(previousBottom, system.rect.top - topGuard);
  final bottom = math.min(nextTop, system.rect.bottom + bottomGuard);
  if (bottom <= top) return system;
  return system.copyWith(
    rect: NormalizedRect(
      system.rect.left,
      top,
      system.rect.right,
      bottom,
    ).clamp(),
  );
}

Map<String, Object?> _renderSystem(
  img.Image source,
  VisualTabSystem system,
  VisualTabTransformConfiguration configuration, {
  required bool relabelTuning,
}) {
  final systemPixels = _pixelRect(system.rect, source.width, source.height);
  final base = img.copyCrop(
    source,
    x: systemPixels.$1,
    y: systemPixels.$2,
    width: systemPixels.$3,
    height: systemPixels.$4,
  );
  final sourceLines = [
    for (final normalized in system.stringLines)
      ((normalized - system.rect.top) / system.rect.height * base.height).clamp(
        0.0,
        base.height.toDouble(),
      ),
  ];
  final spacing = _medianSpacing(sourceLines);
  final unusedTopToBottom =
      configuration.unusedTargetStrings
          .map((index) => configuration.targetLabels.length - 1 - index)
          .toList(growable: false)
        ..sort();
  final usedTargets = configuration.routes
      .map(
        (route) => configuration.targetLabels.length - 1 - route.targetString,
      )
      .toSet();
  final internalInsertions = [
    for (final position in unusedTopToBottom)
      if (usedTargets.any((used) => used < position) &&
          usedTargets.any((used) => used > position))
        position,
  ];
  if (unusedTopToBottom.length > 1 && internalInsertions.isNotEmpty) {
    throw const FormatException(
      'Multiple added target strings are supported at the top and bottom of '
      'the tab. Use only one unused string between existing strings.',
    );
  }
  final singleUnusedTopToBottom = unusedTopToBottom.length == 1
      ? unusedTopToBottom.single
      : null;
  final seam = singleUnusedTopToBottom == null
      ? null
      : _insertionSeam(
          sourceLines,
          singleUnusedTopToBottom,
          base.height.toDouble(),
        );
  final insertionBandPixels = unusedTopToBottom.isEmpty
      ? 0
      : math.max(1, spacing.round());
  final relevantRisks =
      seam == null ||
          singleUnusedTopToBottom == null ||
          singleUnusedTopToBottom == 0 ||
          singleUnusedTopToBottom == sourceLines.length
      ? const <VisualConnectedNotationRisk>[]
      : system.connectedNotationRisks
            .where((risk) => risk.gapIndex == singleUnusedTopToBottom - 1)
            .map((risk) => _inferConnectedNotationSide(risk, system))
            .toList(growable: false);
  final unresolved = relevantRisks.where(
    (risk) => risk.side == VisualConnectedComponentSide.unresolved,
  );
  if (unresolved.isNotEmpty) {
    throw FormatException(
      '${unresolved.length} connected notation component(s) cross the '
      'selected string-insertion seam. Return to analysis review and assign '
      'each component to the upper or lower string region.',
    );
  }
  var output = img.Image.from(base);
  final targetLines = <double>[...sourceLines];
  final insertionSeams = <double>[];
  for (final position in unusedTopToBottom) {
    final currentSeam = _insertionSeam(
      targetLines,
      position,
      output.height.toDouble(),
    );
    final beforeInsertion = output;
    output = _insertHorizontalBand(
      beforeInsertion,
      seam: currentSeam.round().clamp(0, beforeInsertion.height),
      height: insertionBandPixels,
    );
    if (unusedTopToBottom.length == 1) {
      for (final risk in relevantRisks) {
        _moveConnectedNotationComponent(
          output,
          beforeInsertion,
          risk,
          system.rect,
          insertionBandPixels,
        );
      }
    }
    final usedBefore = usedTargets.where((used) => used < position).length;
    insertionSeams.add(
      usedBefore == 0
          ? 0
          : usedBefore == sourceLines.length
          ? 1
          : _insertionSeam(sourceLines, usedBefore, base.height.toDouble()) /
                base.height,
    );
    final newLineY = _newStringLineY(
      targetLines,
      position,
      insertionBandPixels,
    );
    for (var index = 0; index < targetLines.length; index += 1) {
      if (targetLines[index] >= currentSeam) {
        targetLines[index] += insertionBandPixels;
      }
    }
    targetLines.insert(position, newLineY);
  }
  final background = _backgroundColor(output);
  final foreground = _luminance(background) < 128
      ? img.ColorRgb8(245, 245, 245)
      : img.ColorRgb8(18, 18, 18);
  if (unusedTopToBottom.isNotEmpty) {
    final staffXs =
        system.barLines
            .where(
              (position) =>
                  position >= system.rect.left && position <= system.rect.right,
            )
            .map(
              (position) =>
                  ((position - system.rect.left) /
                          system.rect.width *
                          output.width)
                      .round()
                      .clamp(0, output.width - 1),
            )
            .toList(growable: false)
          ..sort();
    final staffLeft = staffXs.isEmpty ? 0 : staffXs.first;
    final staffRight = staffXs.isEmpty ? output.width - 1 : staffXs.last;
    for (final position in unusedTopToBottom) {
      final newLineY = targetLines[position];
      img.drawLine(
        output,
        x1: staffLeft,
        y1: newLineY.round().clamp(0, output.height - 1),
        x2: staffRight,
        y2: newLineY.round().clamp(0, output.height - 1),
        color: foreground,
        thickness: 1,
      );
    }
    for (final barLine in system.barLines) {
      final x =
          ((barLine - system.rect.left) / system.rect.width * output.width)
              .round()
              .clamp(0, output.width - 1);
      img.drawLine(
        output,
        x1: x,
        y1: targetLines.first.round().clamp(0, output.height - 1),
        x2: x,
        y2: targetLines.last.round().clamp(0, output.height - 1),
        color: foreground,
        thickness: 1,
      );
    }
  }
  if (relabelTuning) {
    _replaceTuningLabels(
      output,
      targetLines,
      configuration.targetLabels.reversed.toList(growable: false),
      system.barLines,
      systemRect: system.rect,
      background: background,
      foreground: foreground,
    );
  }

  final routes = {
    for (final route in configuration.routes) route.sourceString: route,
  };
  final transformTokens = _deduplicatedTransformTokens(system.tokens)
    ..sort((left, right) => left.rect.left.compareTo(right.rect.left));
  final lastFretBySourceString = <int, int>{};
  for (final token in transformTokens) {
    if (!token.enabled ||
        token.kind != VisualTabTokenKind.fret ||
        token.stringIndex == null) {
      continue;
    }
    final route = routes[token.stringIndex];
    if (route == null) continue;
    final parsed = _parseFret(token.text);
    if (parsed == null) continue;
    // Songsterr-style parenthesized frets denote a sustained/tied note. OCR
    // occasionally reads the enclosed zero as a three because the tie crosses
    // the glyph. Resolve it from the preceding played fret on the same string
    // before applying the route offset.
    final sourceFret = parsed.$2
        ? lastFretBySourceString[token.stringIndex] ?? parsed.$1
        : parsed.$1;
    lastFretBySourceString[token.stringIndex!] = sourceFret;
    final targetFret = sourceFret + route.effectiveOffset;
    if (targetFret < 0 || targetFret > 36) {
      throw FormatException(
        'Fret ${token.text} on source string '
        '${token.stringIndex! + 1} would become $targetFret. '
        'Visual transforms support frets 0 to 36.',
      );
    }
    final replacement = parsed.$2 ? '($targetFret)' : '$targetFret';
    if (targetFret == sourceFret) {
      // The inserted band already moves the source string to the routed
      // target line. Preserve the source glyph when its fret is unchanged.
      continue;
    }
    final targetLineIndex =
        configuration.targetLabels.length - 1 - route.targetString;
    final sourceLineIndex = system.stringLines.length - 1 - token.stringIndex!;
    _replaceToken(
      output,
      token,
      system.rect,
      replacement,
      insertionSeams: insertionSeams,
      insertionBandPixels: insertionBandPixels,
      totalInsertionPixels: insertionBandPixels * unusedTopToBottom.length,
      sourceLineY: sourceLines[sourceLineIndex],
      targetLineY: targetLines[targetLineIndex],
      targetLines: targetLines,
      staffSpacing: _medianSpacing(targetLines),
      background: background,
      foreground: foreground,
    );
  }
  return {
    'bytes': Uint8List.fromList(img.encodePng(output, level: 4)),
    'width': output.width,
    'height': output.height,
    'system': system.toJson(),
    'insertionSeams': insertionSeams,
    'insertionBandHeight': insertionBandPixels / output.height,
  };
}

List<VisualTabToken> _deduplicatedTransformTokens(List<VisualTabToken> tokens) {
  final result = <VisualTabToken>[];
  for (final token in tokens) {
    if (!token.enabled || !token.isFretLike || token.stringIndex == null) {
      result.add(token);
      continue;
    }
    final duplicateIndex = result.indexWhere((existing) {
      if (!existing.enabled ||
          !existing.isFretLike ||
          existing.stringIndex != token.stringIndex) {
        return false;
      }
      final overlap = _intersection(existing.rect, token.rect);
      if (overlap != null) {
        final smallerArea = math.min(
          existing.rect.width * existing.rect.height,
          token.rect.width * token.rect.height,
        );
        if (smallerArea > 0 &&
            (overlap.width * overlap.height) / smallerArea >= 0.35) {
          return true;
        }
      }
      // Positioned-PDF and raster passes can disagree about the text while
      // describing the same glyph, or use non-overlapping boxes (for example,
      // the PDF box around `(0)` and an OCR box around a misread central `3`).
      // Treat near-identical centres on the same string as one proposal.
      final centerDx =
          ((existing.rect.left + existing.rect.right) -
                  (token.rect.left + token.rect.right))
              .abs() /
          2;
      final centerDy =
          ((existing.rect.top + existing.rect.bottom) -
                  (token.rect.top + token.rect.bottom))
              .abs() /
          2;
      final horizontalTolerance = math.max(
        0.006,
        math.max(existing.rect.width, token.rect.width) * 1.25,
      );
      final verticalTolerance = math.max(
        0.018,
        math.max(existing.rect.height, token.rect.height) * 1.5,
      );
      return centerDx <= horizontalTolerance && centerDy <= verticalTolerance;
    });
    if (duplicateIndex < 0) {
      result.add(token);
      continue;
    }
    final existing = result[duplicateIndex];
    final tokenIsParenthesized = token.text.startsWith('(');
    final existingIsParenthesized = existing.text.startsWith('(');
    if ((tokenIsParenthesized && !existingIsParenthesized) ||
        (tokenIsParenthesized == existingIsParenthesized &&
            token.confidence > existing.confidence)) {
      result[duplicateIndex] = token;
    }
  }
  return result;
}

VisualConnectedNotationRisk _inferConnectedNotationSide(
  VisualConnectedNotationRisk risk,
  VisualTabSystem system,
) {
  if (risk.side != VisualConnectedComponentSide.unresolved) return risk;
  final nearbyUpper = <VisualTabToken>[];
  final nearbyLower = <VisualTabToken>[];
  // Ties and slides can span a sizeable part of a measure; inspect nearby
  // played strings on both sides of the component rather than only the few
  // pixels touching the seam.
  final horizontalGuard = math.max(0.25, risk.rect.width * 3);
  for (final token in system.tokens) {
    if (!token.enabled || !token.isFretLike || token.stringIndex == null) {
      continue;
    }
    final distance = token.rect.right < risk.rect.left
        ? risk.rect.left - token.rect.right
        : token.rect.left > risk.rect.right
        ? token.rect.left - risk.rect.right
        : 0.0;
    if (distance > horizontalGuard) continue;
    final topToBottomString =
        system.stringLines.length - 1 - token.stringIndex!;
    if (topToBottomString == risk.gapIndex) nearbyUpper.add(token);
    if (topToBottomString == risk.gapIndex + 1) nearbyLower.add(token);
  }
  if (nearbyUpper.isNotEmpty && nearbyLower.isEmpty) {
    return risk.copyWith(side: VisualConnectedComponentSide.upper);
  }
  if (nearbyLower.isNotEmpty && nearbyUpper.isEmpty) {
    return risk.copyWith(side: VisualConnectedComponentSide.lower);
  }
  return risk;
}

void _replaceTuningLabels(
  img.Image image,
  List<double> targetLines,
  List<String> topToBottomLabels,
  List<double> barLines, {
  required NormalizedRect systemRect,
  required img.Color background,
  required img.Color foreground,
}) {
  if (targetLines.length != topToBottomLabels.length || targetLines.isEmpty) {
    return;
  }
  final firstStaffX = barLines
      .where(
        (position) => position > systemRect.left && position < systemRect.right,
      )
      .map(
        (position) =>
            ((position - systemRect.left) / systemRect.width * image.width)
                .round(),
      )
      .fold<int>(math.max(24, (image.width * 0.12).round()), math.min)
      .clamp(16, math.max(16, image.width ~/ 3));
  final spacing = _medianSpacing(targetLines);
  final font = spacing >= 24 ? img.arial24 : img.arial14;
  final clearPadding = math.max(3, (spacing * 0.62).ceil());
  final clearRight = (firstStaffX + math.max(6, (spacing * 1.5).ceil()))
      .clamp(0, image.width - 1)
      .toInt();
  img.fillRect(
    image,
    x1: 0,
    y1: (targetLines.first.round() - clearPadding).clamp(0, image.height - 1),
    x2: clearRight,
    y2: (targetLines.last.round() + clearPadding).clamp(0, image.height - 1),
    color: background,
  );
  for (final line in targetLines) {
    img.drawLine(
      image,
      x1: math.max(0, firstStaffX - 2).toInt(),
      y1: line.round().clamp(0, image.height - 1),
      x2: clearRight,
      y2: line.round().clamp(0, image.height - 1),
      color: foreground,
      thickness: 1,
    );
  }
  for (var index = 0; index < targetLines.length; index += 1) {
    final centerY = targetLines[index].round().clamp(0, image.height - 1);
    final label = topToBottomLabels[index];
    final width = label.codeUnits.fold<int>(
      0,
      (total, char) =>
          total + font.characterXAdvance(String.fromCharCode(char)),
    );
    img.drawString(
      image,
      label,
      font: font,
      x: math.max(0, firstStaffX - width - 5).toInt(),
      y: (centerY - font.lineHeight / 2).round(),
      color: foreground,
    );
  }
}

void _moveConnectedNotationComponent(
  img.Image output,
  img.Image source,
  VisualConnectedNotationRisk risk,
  NormalizedRect systemRect,
  int insertionPixels,
) {
  final left =
      ((risk.rect.left - systemRect.left) / systemRect.width * source.width)
          .floor()
          .clamp(0, source.width - 1);
  final right =
      ((risk.rect.right - systemRect.left) / systemRect.width * source.width)
          .ceil()
          .clamp(left + 1, source.width);
  final top =
      ((risk.rect.top - systemRect.top) / systemRect.height * source.height)
          .floor()
          .clamp(0, source.height - 1);
  final bottom =
      ((risk.rect.bottom - systemRect.top) / systemRect.height * source.height)
          .ceil()
          .clamp(top + 1, source.height);
  final targetTop = risk.side == VisualConnectedComponentSide.lower
      ? top + insertionPixels
      : top;
  img.compositeImage(
    output,
    source,
    dstX: left,
    dstY: targetTop,
    dstW: right - left,
    dstH: bottom - top,
    srcX: left,
    srcY: top,
    srcW: right - left,
    srcH: bottom - top,
    blend: img.BlendMode.direct,
  );
}

void _replaceToken(
  img.Image image,
  VisualTabToken token,
  NormalizedRect systemRect,
  String replacement, {
  required List<double> insertionSeams,
  required int insertionBandPixels,
  required int totalInsertionPixels,
  required double sourceLineY,
  required double targetLineY,
  required List<double> targetLines,
  required double staffSpacing,
  required img.Color background,
  required img.Color foreground,
}) {
  final left =
      ((token.rect.left - systemRect.left) / systemRect.width * image.width);
  final right =
      ((token.rect.right - systemRect.left) / systemRect.width * image.width);
  final originalTop =
      ((token.rect.top - systemRect.top) /
      systemRect.height *
      (image.height - totalInsertionPixels));
  final originalBottom =
      ((token.rect.bottom - systemRect.top) /
      systemRect.height *
      (image.height - totalInsertionPixels));
  final baseHeight = image.height - totalInsertionPixels;
  final top = _mapInsertedPixelY(
    originalTop,
    baseHeight: baseHeight,
    insertionSeams: insertionSeams,
    insertionBandPixels: insertionBandPixels,
  );
  final bottom = _mapInsertedPixelY(
    originalBottom,
    baseHeight: baseHeight,
    insertionSeams: insertionSeams,
    insertionBandPixels: insertionBandPixels,
  );
  final x1 = (left.floor() - 3).clamp(0, image.width - 1);
  final y1 = (top.floor() - 3).clamp(0, image.height - 1);
  final x2 = (right.ceil() + 3).clamp(x1 + 1, image.width);
  final y2 = (bottom.ceil() + 3).clamp(y1 + 1, image.height);
  img.fillRect(
    image,
    x1: x1,
    y1: y1,
    x2: x2 - 1,
    y2: y2 - 1,
    color: background,
  );
  final glyph = _scaledFretGlyph(
    replacement,
    targetHeight: (staffSpacing * 1.08).round().clamp(11, 44),
    background: background,
    foreground: foreground,
  );
  final centerX = (left + right) / 2;
  final drawX = (centerX - glyph.width / 2).round();
  final drawY = (targetLineY - glyph.height / 2).round();
  // Raster review can correctly label a sustain as `(0)` while its geometry
  // encloses only the central digit. Clear a staff-relative footprint around
  // the routed string before drawing; otherwise the surviving source zero and
  // the new 3 combine visually into a 6. Keep the footprint tight enough not
  // to erase the neighbouring tie.
  final replacementIsParenthesized =
      replacement.startsWith('(') && replacement.endsWith(')');
  final clearHalfWidth = math.max(
    glyph.width / 2 + 2,
    staffSpacing * (replacementIsParenthesized ? 1.4 : 0.58),
  );
  final clearHalfHeight = math.max(
    glyph.height / 2 + 2,
    staffSpacing * (replacementIsParenthesized ? 0.68 : 0.54),
  );
  final clearLeft = (centerX - clearHalfWidth).floor().clamp(
    0,
    image.width - 1,
  );
  final clearTop = (targetLineY - clearHalfHeight).floor().clamp(
    0,
    image.height - 1,
  );
  final clearRight = (centerX + clearHalfWidth).ceil().clamp(
    0,
    image.width - 1,
  );
  final clearBottom = (targetLineY + clearHalfHeight).ceil().clamp(
    0,
    image.height - 1,
  );
  if (insertionSeams.length == 1 &&
      insertionSeams.single > 0 &&
      insertionSeams.single < 1 &&
      (originalTop + originalBottom) / 2 >=
          insertionSeams.single * baseHeight) {
    // The inserted band is copied row-by-row. A tall sustain glyph can cross
    // the seam even when its centre belongs to the lower string, leaving its
    // upper arc at the pre-insertion position. Clear that ghost footprint as
    // well as the routed footprint below.
    // Clear around the actual source string, not the OCR rectangle centre.
    // Positioned-PDF text boxes for parenthesized sustains are often anchored
    // below the string even though the upper parenthesis crosses the seam.
    final originalCenterY = sourceLineY;
    img.fillRect(
      image,
      x1: clearLeft,
      y1: (originalCenterY - clearHalfHeight).floor().clamp(
        0,
        image.height - 1,
      ),
      x2: clearRight,
      y2: (originalCenterY + clearHalfHeight).ceil().clamp(0, image.height - 1),
      color: background,
    );
  }
  img.fillRect(
    image,
    x1: clearLeft,
    y1: clearTop,
    x2: clearRight,
    y2: clearBottom,
    color: background,
  );
  for (final line in targetLines) {
    if ((line - targetLineY).abs() < 0.5) continue;
    img.drawLine(
      image,
      x1: clearLeft,
      y1: line.round().clamp(0, image.height - 1),
      x2: clearRight,
      y2: line.round().clamp(0, image.height - 1),
      color: foreground,
      thickness: 1,
    );
  }
  img.compositeImage(
    image,
    glyph,
    dstX: drawX,
    dstY: drawY,
    blend: img.BlendMode.direct,
  );
}

double _mapInsertedPixelY(
  double value, {
  required int baseHeight,
  required List<double> insertionSeams,
  required int insertionBandPixels,
}) {
  var mapped = value;
  for (final seam in insertionSeams) {
    if (value >= seam * baseHeight) mapped += insertionBandPixels;
  }
  return mapped;
}

img.Image _scaledFretGlyph(
  String value, {
  required int targetHeight,
  required img.Color background,
  required img.Color foreground,
}) {
  final textWidth = value.codeUnits.fold<int>(
    0,
    (width, char) =>
        width + img.arial48.characterXAdvance(String.fromCharCode(char)),
  );
  final canvas = img.Image(
    width: math.max(1, textWidth + 8),
    height: img.arial48.lineHeight + 8,
  );
  img.fill(canvas, color: background);
  img.drawString(
    canvas,
    value,
    font: img.arial48,
    x: 4,
    y: 4,
    color: foreground,
  );
  var left = canvas.width;
  var top = canvas.height;
  var right = 0;
  var bottom = 0;
  final backgroundLuminance = _luminance(background);
  for (var y = 0; y < canvas.height; y += 1) {
    for (var x = 0; x < canvas.width; x += 1) {
      if ((_luminance(canvas.getPixel(x, y)) - backgroundLuminance).abs() <
          18) {
        continue;
      }
      left = math.min(left, x);
      top = math.min(top, y);
      right = math.max(right, x + 1);
      bottom = math.max(bottom, y + 1);
    }
  }
  if (right <= left || bottom <= top) return canvas;
  final ink = img.copyCrop(
    canvas,
    x: left,
    y: top,
    width: right - left,
    height: bottom - top,
  );
  final height = math.max(1, targetHeight);
  final width = math.max(1, (ink.width * height / ink.height).round());
  return img.copyResize(
    ink,
    width: width,
    height: height,
    interpolation: img.Interpolation.cubic,
  );
}

img.Image _insertHorizontalBand(
  img.Image source, {
  required int seam,
  required int height,
}) {
  final output = img.Image(
    width: source.width,
    height: source.height + height,
    numChannels: source.numChannels,
  );
  final background = _backgroundColor(source);
  img.fill(output, color: background);
  if (seam > 0) {
    img.compositeImage(
      output,
      source,
      dstY: 0,
      dstW: source.width,
      dstH: seam,
      srcY: 0,
      srcW: source.width,
      srcH: seam,
      blend: img.BlendMode.direct,
    );
  }
  if (seam < source.height) {
    img.compositeImage(
      output,
      source,
      dstY: seam + height,
      dstW: source.width,
      dstH: source.height - seam,
      srcY: seam,
      srcW: source.width,
      srcH: source.height - seam,
      blend: img.BlendMode.direct,
    );
  }
  return output;
}

double _insertionSeam(
  List<double> sourceLines,
  int unusedTopToBottom,
  double sourceHeight,
) {
  if (unusedTopToBottom == 0) {
    return 0;
  }
  if (unusedTopToBottom == sourceLines.length) {
    // Append the new string below the complete source system. Splitting at a
    // midpoint would move or clip rhythm and measure context below the staff.
    return sourceHeight;
  }
  return (sourceLines[unusedTopToBottom - 1] + sourceLines[unusedTopToBottom]) /
      2;
}

double _newStringLineY(
  List<double> sourceLines,
  int unusedTopToBottom,
  int insertionPixels,
) {
  if (unusedTopToBottom == 0) return sourceLines.first;
  if (unusedTopToBottom == sourceLines.length) {
    return sourceLines.last + insertionPixels;
  }
  return sourceLines[unusedTopToBottom - 1] + insertionPixels;
}

(int, bool)? _parseFret(String text) {
  final trimmed = text.trim();
  final parenthesized = trimmed.startsWith('(') && trimmed.endsWith(')');
  final digits = parenthesized
      ? trimmed.substring(1, trimmed.length - 1)
      : trimmed;
  final value = int.tryParse(digits);
  return value == null ? null : (value, parenthesized);
}

(int, int, int, int) _pixelRect(NormalizedRect rect, int width, int height) {
  final left = (rect.left * width).floor().clamp(0, width - 1);
  final top = (rect.top * height).floor().clamp(0, height - 1);
  final right = (rect.right * width).ceil().clamp(left + 1, width);
  final bottom = (rect.bottom * height).ceil().clamp(top + 1, height);
  return (left, top, right - left, bottom - top);
}

img.Color _backgroundColor(img.Image image) {
  final samples = <img.Pixel>[];
  final stepX = math.max(1, image.width ~/ 24);
  final stepY = math.max(1, image.height ~/ 24);
  for (var x = 0; x < image.width; x += stepX) {
    samples.add(image.getPixel(x, 0));
    samples.add(image.getPixel(x, image.height - 1));
  }
  for (var y = 0; y < image.height; y += stepY) {
    samples.add(image.getPixel(0, y));
    samples.add(image.getPixel(image.width - 1, y));
  }
  samples.sort((left, right) => _luminance(left).compareTo(_luminance(right)));
  final median = samples[samples.length ~/ 2];
  return img.ColorRgba8(
    median.r.toInt(),
    median.g.toInt(),
    median.b.toInt(),
    median.a.toInt(),
  );
}

double _luminance(img.Color color) =>
    color.r.toDouble() * 0.299 +
    color.g.toDouble() * 0.587 +
    color.b.toDouble() * 0.114;

double _medianSpacing(List<double> values) {
  final spacings = <double>[
    for (var index = 1; index < values.length; index += 1)
      values[index] - values[index - 1],
  ]..sort();
  return spacings.isEmpty ? 1 : spacings[spacings.length ~/ 2];
}

NormalizedRect? _intersection(NormalizedRect a, NormalizedRect b) {
  final left = math.max(a.left, b.left);
  final top = math.max(a.top, b.top);
  final right = math.min(a.right, b.right);
  final bottom = math.min(a.bottom, b.bottom);
  if (right <= left || bottom <= top) return null;
  return NormalizedRect(left, top, right, bottom);
}

NormalizedRect _mapSystemRect(
  NormalizedRect rect,
  NormalizedRect systemRect, {
  required List<double> insertionSeams,
  required double insertionBandHeight,
}) {
  final left = (rect.left - systemRect.left) / systemRect.width;
  final right = (rect.right - systemRect.left) / systemRect.width;
  final top = (rect.top - systemRect.top) / systemRect.height;
  final bottom = (rect.bottom - systemRect.top) / systemRect.height;
  return NormalizedRect(
    left.clamp(0.0, 0.999),
    _mapSystemY(
      top,
      insertionSeams: insertionSeams,
      insertionBandHeight: insertionBandHeight,
    ).clamp(0.0, 0.999),
    right.clamp(0.001, 1.0),
    _mapSystemY(
      bottom,
      insertionSeams: insertionSeams,
      insertionBandHeight: insertionBandHeight,
    ).clamp(0.001, 1.0),
  ).clamp();
}

double _mapSystemY(
  double value, {
  required List<double> insertionSeams,
  required double insertionBandHeight,
}) {
  if (insertionSeams.isEmpty || insertionBandHeight <= 0) return value;
  final baseScale = 1 - insertionBandHeight * insertionSeams.length;
  final baseValue = value * baseScale;
  final priorInsertions = insertionSeams.where((seam) => value >= seam).length;
  return baseValue + insertionBandHeight * priorInsertions;
}
