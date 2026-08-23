import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../domain/visual_chart_models.dart';

class PageRowProposal {
  const PageRowProposal({
    required this.rows,
    required this.masterLeft,
    required this.masterRight,
  });

  final List<NormalizedRect> rows;
  final double masterLeft;
  final double masterRight;
}

class HorizontalRowDetector {
  const HorizontalRowDetector({
    this.minimumGapFraction = 0.012,
    this.minimumGapPixels = 18,
    this.maximumRows = 64,
  });

  final double minimumGapFraction;
  final int minimumGapPixels;
  final int maximumRows;

  /// Produces editable page-level row proposals. Compared with [detect], this
  /// trims header/footer content around the repeated staff systems and derives
  /// conservative common side crops. The original pixels remain untouched.
  PageRowProposal detectPageAware(
    Uint8List sourceBytes, {
    NormalizedRect sourceRect = const NormalizedRect.full(),
  }) {
    var image = img.decodeImage(sourceBytes);
    if (image == null) {
      return PageRowProposal(
        rows: [sourceRect],
        masterLeft: sourceRect.left,
        masterRight: sourceRect.right,
      );
    }
    image = img.bakeOrientation(image);
    final detected = detect(sourceBytes, sourceRect: sourceRect);
    final background = _backgroundLuminance(
      image,
      (sourceRect.left * image.width).floor().clamp(0, image.width - 1),
      (sourceRect.top * image.height).floor().clamp(0, image.height - 1),
      (sourceRect.right * image.width).ceil().clamp(1, image.width),
      (sourceRect.bottom * image.height).ceil().clamp(1, image.height),
    );
    final results = <(NormalizedRect, (double, double)?)>[];
    for (final row in detected) {
      results.add(_tightenPageRow(image, row, background));
    }
    final staffedResults = results
        .where((result) => result.$2 != null)
        .toList(growable: false);
    // A page with several confirmed staff rows may also contain title and page
    // number bands. Exclude those non-staff bands from automatic proposals;
    // retain the conservative detector result when staff evidence is sparse.
    final retained = staffedResults.length >= 2 ? staffedResults : results;
    final tightened = retained.map((result) => result.$1).toList();
    final sideBounds = staffedResults.map((result) => result.$2!).toList();
    if (sideBounds.isEmpty) {
      return PageRowProposal(
        rows: tightened,
        masterLeft: sourceRect.left,
        masterRight: sourceRect.right,
      );
    }
    final lefts = sideBounds.map((value) => value.$1).toList()..sort();
    final rights = sideBounds.map((value) => value.$2).toList()..sort();
    final medianLeft = lefts[lefts.length ~/ 2];
    final medianRight = rights[rights.length ~/ 2];
    // A tie or parenthesized sustain can cross just beyond the first/last bar
    // line without touching the staff-line scan. Retain nearby real row ink,
    // but cap a single row's influence so a distant speck cannot restore the
    // old page-width gutters.
    final maximumInkExpansion = (24 / image.width).clamp(6 / image.width, 0.02);
    final outerLeft = lefts.first
        .clamp(medianLeft - maximumInkExpansion, medianLeft)
        .toDouble();
    final outerRight = rights.last
        .clamp(medianRight, medianRight + maximumInkExpansion)
        .toDouble();
    // The staff-band bounds already include the complete outer ink. Cross-row
    // sustain hooks can meet either outermost detected pixel, so retain a
    // small safety edge on both sides without restoring page-width gutters.
    final leftPadding = 8 / image.width;
    final rightPadding = 8 / image.width;
    final masterLeft = (outerLeft - leftPadding)
        .clamp(sourceRect.left, sourceRect.right - 0.02)
        .toDouble();
    final masterRight = (outerRight + rightPadding)
        .clamp(masterLeft + 0.02, sourceRect.right)
        .toDouble();
    return PageRowProposal(
      rows: [
        for (final row in tightened)
          NormalizedRect(masterLeft, row.top, masterRight, row.bottom),
      ],
      masterLeft: masterLeft,
      masterRight: masterRight,
    );
  }

  List<NormalizedRect> detect(
    Uint8List sourceBytes, {
    NormalizedRect sourceRect = const NormalizedRect.full(),
  }) {
    var image = img.decodeImage(sourceBytes);
    if (image == null) return [sourceRect];
    image = img.bakeOrientation(image);
    final left = (sourceRect.left * image.width).floor().clamp(
      0,
      image.width - 1,
    );
    final top = (sourceRect.top * image.height).floor().clamp(
      0,
      image.height - 1,
    );
    final right = (sourceRect.right * image.width).ceil().clamp(
      left + 1,
      image.width,
    );
    final bottom = (sourceRect.bottom * image.height).ceil().clamp(
      top + 1,
      image.height,
    );
    final width = right - left;
    final height = bottom - top;
    if (width < 2 || height < 2) return [sourceRect];

    final background = _backgroundLuminance(image, left, top, right, bottom);
    final sampleStep = (width / 800).ceil().clamp(1, width);
    final active = List<bool>.filled(height, false);
    final wideLine = List<bool>.filled(height, false);
    for (var localY = 0; localY < height; localY += 1) {
      var ink = 0;
      var strongInk = 0;
      var samples = 0;
      for (var x = left; x < right; x += sampleStep) {
        final distance =
            (_luminance(image.getPixel(x, top + localY)) - background).abs();
        if (distance >= 7) ink += 1;
        if (distance >= 16) strongInk += 1;
        samples += 1;
      }
      final requiredInk = (samples * 0.003).ceil().clamp(3, 10);
      active[localY] = ink >= requiredInk || strongInk >= 2;
      wideLine[localY] =
          samples > 0 && ink / samples >= 0.18 && strongInk / samples >= 0.04;
    }

    final guard = (height * 0.004).round().clamp(4, 14);
    final edgePadding = (height * 0.0015).round().clamp(2, 6);
    final protected = List<bool>.filled(height, false);
    for (var y = 0; y < height; y += 1) {
      if (!active[y]) continue;
      final start = (y - guard).clamp(0, height - 1);
      final end = (y + guard).clamp(0, height - 1);
      for (var protectedY = start; protectedY <= end; protectedY += 1) {
        protected[protectedY] = true;
      }
    }

    final firstContent = protected.indexWhere((value) => value);
    final lastContent = protected.lastIndexWhere((value) => value);
    if (firstContent < 0 || lastContent < firstContent) return [sourceRect];

    final minimumGap = (height * minimumGapFraction).round().clamp(
      minimumGapPixels,
      80,
    );
    final cuts = <int>[];
    var blankStart = -1;
    for (var y = firstContent; y <= lastContent + 1; y += 1) {
      final blank = y <= lastContent && !protected[y];
      if (blank && blankStart < 0) blankStart = y;
      if (!blank && blankStart >= 0) {
        if (y - blankStart >= minimumGap) cuts.add((blankStart + y) ~/ 2);
        blankStart = -1;
      }
    }
    final staffCuts = _staffSystemCuts(wideLine, height);
    final effectiveCuts = staffCuts.isNotEmpty ? staffCuts : cuts;
    if (effectiveCuts.isEmpty) {
      return [
        _normalizedContentRect(
          sourceRect,
          firstContent,
          lastContent + 1,
          height,
          edgePadding,
        ),
      ];
    }

    final boundaries = <int>[0, ...effectiveCuts.take(maximumRows - 1), height];
    final rows = <NormalizedRect>[];
    for (var index = 0; index < boundaries.length - 1; index += 1) {
      final segmentTop = boundaries[index];
      final segmentBottom = boundaries[index + 1];
      var contentTop = -1;
      var contentBottom = -1;
      for (var y = segmentTop; y < segmentBottom; y += 1) {
        if (!protected[y]) continue;
        if (contentTop < 0) contentTop = y;
        contentBottom = y + 1;
      }
      if (contentTop < 0) continue;
      rows.add(
        _normalizedContentRect(
          sourceRect,
          contentTop,
          contentBottom,
          height,
          edgePadding,
        ),
      );
    }
    return rows.isEmpty ? [sourceRect] : rows;
  }

  List<int> _staffSystemCuts(List<bool> wideLine, int height) {
    final mergeGap = (height * 0.018).round().clamp(10, 32);
    final clusters = <_WideLineCluster>[];
    _WideLineCluster? current;
    var previousWide = false;
    for (var y = 0; y < wideLine.length; y += 1) {
      if (!wideLine[y]) {
        previousWide = false;
        continue;
      }
      if (current == null || y - current.last > mergeGap) {
        current = _WideLineCluster(y);
        clusters.add(current);
      } else {
        current.add(y, startsRun: !previousWide);
      }
      previousWide = true;
    }
    final systems = clusters
        .where(
          (cluster) => cluster.runs >= 3 && cluster.last - cluster.first >= 5,
        )
        .toList(growable: false);
    if (systems.length < 2) return const [];
    return [
      for (var index = 0; index < systems.length - 1; index += 1)
        (systems[index].last + systems[index + 1].first) ~/ 2,
    ];
  }

  NormalizedRect _normalizedContentRect(
    NormalizedRect sourceRect,
    int top,
    int bottom,
    int sourceHeight,
    int padding,
  ) {
    final paddedTop = (top - padding).clamp(0, sourceHeight - 1);
    final paddedBottom = (bottom + padding).clamp(paddedTop + 1, sourceHeight);
    return NormalizedRect(
      sourceRect.left,
      sourceRect.top + sourceRect.height * paddedTop / sourceHeight,
      sourceRect.right,
      sourceRect.top + sourceRect.height * paddedBottom / sourceHeight,
    ).clamp();
  }

  double _backgroundLuminance(
    img.Image image,
    int left,
    int top,
    int right,
    int bottom,
  ) {
    final histogram = List<int>.filled(256, 0);
    final stepX = ((right - left) / 180).ceil().clamp(1, right - left);
    final stepY = ((bottom - top) / 180).ceil().clamp(1, bottom - top);
    for (var y = top; y < bottom; y += stepY) {
      for (var x = left; x < right; x += stepX) {
        histogram[_luminance(image.getPixel(x, y)).round().clamp(0, 255)] += 1;
      }
    }
    var mode = 0;
    for (var value = 1; value < histogram.length; value += 1) {
      if (histogram[value] > histogram[mode]) mode = value;
    }
    return mode.toDouble();
  }

  double _luminance(img.Pixel pixel) =>
      pixel.r.toDouble() * 0.299 +
      pixel.g.toDouble() * 0.587 +
      pixel.b.toDouble() * 0.114;

  (NormalizedRect, (double, double)?) _tightenPageRow(
    img.Image image,
    NormalizedRect row,
    double background,
  ) {
    final left = (row.left * image.width).floor().clamp(0, image.width - 1);
    final right = (row.right * image.width).ceil().clamp(left + 1, image.width);
    final top = (row.top * image.height).floor().clamp(0, image.height - 1);
    final bottom = (row.bottom * image.height).ceil().clamp(
      top + 1,
      image.height,
    );
    final stepX = ((right - left) / 900).ceil().clamp(1, right - left);
    final wideYs = <int>[];
    for (var y = top; y < bottom; y += 1) {
      var ink = 0;
      var samples = 0;
      for (var x = left; x < right; x += stepX) {
        final distance = (_luminance(image.getPixel(x, y)) - background).abs();
        if (distance >= 16) {
          ink += 1;
        }
        samples += 1;
      }
      // Staff lines span most of the usable row width. A lower threshold lets
      // large title glyphs masquerade as a four-line tab system.
      if (samples > 0 && ink / samples >= 0.42) {
        wideYs.add(y);
      }
    }
    if (wideYs.isEmpty) return (row, null);
    final runs = <(int, int)>[];
    var runStart = wideYs.first;
    var runEnd = wideYs.first;
    for (final y in wideYs.skip(1)) {
      if (y <= runEnd + 1) {
        runEnd = y;
      } else {
        runs.add((runStart, runEnd));
        runStart = y;
        runEnd = y;
      }
    }
    runs.add((runStart, runEnd));
    (int, int)? staffBand;
    final maximumStaffSpan = (image.height * 0.08).round().clamp(20, 140);
    for (var index = 0; index + 2 < runs.length; index += 1) {
      for (var end = index + 2; end < runs.length; end += 1) {
        if (runs[end].$2 - runs[index].$1 > maximumStaffSpan) break;
        if (end - index + 1 >= 3) {
          staffBand = (runs[index].$1, runs[end].$2);
        }
      }
      if (staffBand != null) break;
    }
    if (staffBand == null) return (row, null);
    var inkLeft = right;
    var inkRight = left;
    for (var y = staffBand.$1; y <= staffBand.$2; y += 1) {
      for (var x = left; x < right; x += stepX) {
        final distance = (_luminance(image.getPixel(x, y)) - background).abs();
        if (distance < 16) continue;
        inkLeft = mathMin(inkLeft, x);
        inkRight = mathMax(inkRight, x);
      }
    }
    final staffInkLeft = inkLeft;
    final staffInkRight = inkRight;
    final topGuard = (image.height * 0.035).round().clamp(4, 90);
    final bottomGuard = (image.height * 0.045).round().clamp(6, 110);
    final bottomNotationPadding = (image.height * 0.003).round().clamp(4, 8);
    final tightenedTop = (staffBand.$1 - topGuard)
        .clamp(top, bottom - 1)
        .toInt();
    final tightenedBottom = (staffBand.$2 + bottomGuard)
        .clamp(
          tightenedTop + 1,
          (bottom + bottomNotationPadding).clamp(
            tightenedTop + 1,
            image.height,
          ),
        )
        .toInt();
    // Include strong notation outside the staff band itself, notably the
    // leading edge of cross-row ties and parenthesized sustain glyphs.
    final notationSideAllowance = (24 / image.width).clamp(
      6 / image.width,
      0.02,
    );
    final notationLeft = (staffInkLeft - notationSideAllowance * image.width)
        .floor()
        .clamp(left, right - 1);
    final notationRight = (staffInkRight + notationSideAllowance * image.width)
        .ceil()
        .clamp(notationLeft + 1, right);
    for (var y = tightenedTop; y < tightenedBottom; y += 1) {
      for (var x = notationLeft; x < notationRight; x += stepX) {
        final distance = (_luminance(image.getPixel(x, y)) - background).abs();
        if (distance < 16) continue;
        inkLeft = mathMin(inkLeft, x);
        inkRight = mathMax(inkRight, x);
      }
    }
    return (
      NormalizedRect(
        row.left,
        tightenedTop / image.height,
        row.right,
        tightenedBottom / image.height,
      ).clamp(),
      inkRight > inkLeft
          ? (inkLeft / image.width, (inkRight + stepX) / image.width)
          : null,
    );
  }
}

int mathMin(int left, int right) => left < right ? left : right;
int mathMax(int left, int right) => left > right ? left : right;

class _WideLineCluster {
  _WideLineCluster(this.first) : last = first, count = 1, runs = 1;

  final int first;
  int last;
  int count;
  int runs;

  void add(int y, {required bool startsRun}) {
    last = y;
    count += 1;
    if (startsRun) runs += 1;
  }
}
