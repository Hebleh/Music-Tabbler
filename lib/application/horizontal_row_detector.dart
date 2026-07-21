import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../domain/visual_chart_models.dart';

class HorizontalRowDetector {
  const HorizontalRowDetector({
    this.minimumGapFraction = 0.012,
    this.minimumGapPixels = 18,
    this.maximumRows = 64,
  });

  final double minimumGapFraction;
  final int minimumGapPixels;
  final int maximumRows;

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
      final requiredInk = (samples * 0.0015).ceil().clamp(2, 8);
      active[localY] = ink >= requiredInk || strongInk >= 2;
      wideLine[localY] =
          samples > 0 && ink / samples >= 0.28 && strongInk / samples >= 0.08;
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
}

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
