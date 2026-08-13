import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../domain/visual_chart_models.dart';
import 'highlight_geometry.dart';
import 'horizontal_row_detector.dart';
import 'visual_deskew.dart';

class VisualImageProcessor {
  const VisualImageProcessor();

  Uint8List process(
    Uint8List sourceBytes,
    VisualStrip strip, {
    VisualTreatment? globalTreatment,
    int? maxWidth,
  }) {
    var decoded = img.decodeImage(sourceBytes);
    if (decoded == null) {
      throw const FormatException('Stored chart image is invalid.');
    }
    decoded = img.bakeOrientation(decoded);
    decoded = applyDeskewRotation(decoded, strip.deskewDegrees);
    final image = _processDecoded(
      decoded,
      strip,
      globalTreatment: globalTreatment,
      maxWidth: maxWidth,
    );
    return Uint8List.fromList(img.encodePng(image, level: 3));
  }

  List<List<ProcessedExportImage>> processForExportBatch(
    Uint8List sourceBytes,
    List<VisualStrip> strips, {
    VisualTreatment? globalTreatment,
    double splitDetectedRowsBelowAspectRatio = 2.2,
    double maximumRowAspectRatio = double.infinity,
  }) {
    var decoded = img.decodeImage(sourceBytes);
    if (decoded == null) {
      throw const FormatException('Stored chart image is invalid.');
    }
    decoded = img.bakeOrientation(decoded);
    return [
      for (final strip in strips)
        _compactImage(
          _processDecoded(
            applyDeskewRotation(decoded, strip.deskewDegrees),
            strip,
            globalTreatment: globalTreatment,
          ),
          splitDetectedRowsBelowAspectRatio: splitDetectedRowsBelowAspectRatio,
          maximumRowAspectRatio: maximumRowAspectRatio,
        ),
    ];
  }

  img.Image _processDecoded(
    img.Image source,
    VisualStrip strip, {
    VisualTreatment? globalTreatment,
    int? maxWidth,
  }) {
    final crop = _pixelRect(strip.crop, source.width, source.height);
    var image = img.copyCrop(
      source,
      x: crop.x,
      y: crop.y,
      width: crop.width,
      height: crop.height,
    );
    if (maxWidth != null && image.width > maxWidth) {
      image = img.copyResize(
        image,
        width: maxWidth,
        interpolation: img.Interpolation.linear,
      );
    }
    image = _applyTreatment(image, globalTreatment ?? strip.treatment);

    final lyricBand = strip.lyricBand == null
        ? null
        : assetRectToCropLocal(strip.lyricBand!, strip.crop);
    if (lyricBand != null && strip.lyricContrast != 1) {
      final contrasted = img.adjustColor(
        img.Image.from(image),
        contrast: strip.lyricContrast,
      );
      final band = _pixelRect(lyricBand, image.width, image.height);
      img.compositeImage(
        image,
        contrasted,
        dstX: band.x,
        dstY: band.y,
        dstW: band.width,
        dstH: band.height,
        srcX: band.x,
        srcY: band.y,
        srcW: band.width,
        srcH: band.height,
        blend: img.BlendMode.direct,
      );
    }

    for (final highlight in strip.highlights) {
      final relative = assetRectToCropLocal(highlight.rect, strip.crop);
      if (relative == null) continue;
      final rect = _pixelRect(relative, image.width, image.height);
      _paintOpaqueHighlight(image, rect);
    }

    return image;
  }

  List<Uint8List> compactForExport(
    Uint8List processedPng, {
    double splitDetectedRowsBelowAspectRatio = 2.2,
  }) {
    final decoded = img.decodePng(processedPng);
    if (decoded == null) return [processedPng];
    final detected = const HorizontalRowDetector().detect(processedPng);
    if (detected.isEmpty) return [processedPng];
    final rows =
        decoded.width / decoded.height < splitDetectedRowsBelowAspectRatio
        ? detected
        : [NormalizedRect(0, detected.first.top, 1, detected.last.bottom)];
    return [for (final row in rows) _encodeRect(decoded, row)];
  }

  List<ProcessedExportImage> _compactImage(
    img.Image image, {
    required double splitDetectedRowsBelowAspectRatio,
    required double maximumRowAspectRatio,
  }) {
    final rendered = Uint8List.fromList(img.encodePng(image, level: 3));
    final portraitLike =
        image.width / image.height < splitDetectedRowsBelowAspectRatio;
    final detector = const HorizontalRowDetector();
    final pageAware = maximumRowAspectRatio.isFinite
        ? detector.detectPageAware(rendered)
        : null;
    final detected = portraitLike
        ? (pageAware ?? detector.detectPageAware(rendered)).rows
        : detector.detect(rendered);
    if (portraitLike &&
        maximumRowAspectRatio.isFinite &&
        image.width / image.height < 1.4 &&
        detected.length <= 1) {
      throw StateError(
        'This portrait/full-page source has no reviewed tab rows. Open the '
        'chart and use Split into rows before Balanced or Stage-readable mode.',
      );
    }
    final rows = detected.isEmpty
        ? [const NormalizedRect.full()]
        : portraitLike
        ? detected
        : [
            NormalizedRect(
              pageAware?.masterLeft ?? 0,
              detected.first.top,
              pageAware?.masterRight ?? 1,
              detected.last.bottom,
            ),
          ];
    final horizontallyCompacted = maximumRowAspectRatio.isFinite
        ? [for (final row in rows) _trimHorizontalWhitespace(image, row)]
        : rows;
    final safeRows = [
      for (final row in horizontallyCompacted)
        ..._splitWideRow(image, row, maximumRowAspectRatio),
    ];
    return [
      for (final row in safeRows)
        () {
          final left = (row.left * image.width).floor().clamp(
            0,
            image.width - 1,
          );
          final right = (row.right * image.width).ceil().clamp(
            left + 1,
            image.width,
          );
          final top = (row.top * image.height).floor().clamp(
            0,
            image.height - 1,
          );
          final bottom = (row.bottom * image.height).ceil().clamp(
            top + 1,
            image.height,
          );
          final bytes = _encodeRect(image, row);
          return ProcessedExportImage(
            bytes,
            (right - left) / (bottom - top),
            sourceRect: row,
          );
        }(),
    ];
  }

  NormalizedRect _trimHorizontalWhitespace(
    img.Image image,
    NormalizedRect row,
  ) {
    final left = (row.left * image.width).floor().clamp(0, image.width - 1);
    final right = (row.right * image.width).ceil().clamp(left + 1, image.width);
    final top = (row.top * image.height).floor().clamp(0, image.height - 1);
    final bottom = (row.bottom * image.height).ceil().clamp(
      top + 1,
      image.height,
    );
    final background = _edgeBackground(image, left, right, top, bottom);
    final requiredInk = math.max(2, ((bottom - top) * 0.012).ceil());
    var inkLeft = right;
    var inkRight = left;
    for (var x = left; x < right; x += 1) {
      var ink = 0;
      for (var y = top; y < bottom; y += 1) {
        if ((_luminance(image.getPixel(x, y)) - background).abs() >= 16) {
          ink += 1;
        }
      }
      if (ink < requiredInk) continue;
      inkLeft = math.min(inkLeft, x);
      inkRight = math.max(inkRight, x + 1);
    }
    if (inkRight <= inkLeft) return row;
    final padding = math.max(4, ((right - left) * 0.012).round());
    final trimmedLeft = (inkLeft - padding).clamp(left, right - 1);
    final trimmedRight = (inkRight + padding).clamp(trimmedLeft + 1, right);
    return NormalizedRect(
      trimmedLeft / image.width,
      row.top,
      trimmedRight / image.width,
      row.bottom,
    );
  }

  List<NormalizedRect> _splitWideRow(
    img.Image image,
    NormalizedRect row,
    double maximumAspectRatio,
  ) {
    if (!maximumAspectRatio.isFinite || maximumAspectRatio <= 0) return [row];
    final width = image.width * row.width;
    final height = image.height * row.height;
    final aspect = width / height;
    if (aspect <= maximumAspectRatio) return [row];
    final count = (aspect / maximumAspectRatio).ceil();
    final left = (row.left * image.width).round();
    final right = (row.right * image.width).round();
    final top = (row.top * image.height).floor().clamp(0, image.height - 1);
    final bottom = (row.bottom * image.height).ceil().clamp(
      top + 1,
      image.height,
    );
    final boundaries = <int>[left];
    for (var index = 1; index < count; index += 1) {
      final target = left + ((right - left) * index / count).round();
      final radius = ((right - left) / count * 0.12).round().clamp(4, 80);
      boundaries.add(
        _safestVerticalCut(image, target, radius, left, right, top, bottom),
      );
    }
    boundaries.add(right);
    return [
      for (var index = 0; index < boundaries.length - 1; index += 1)
        NormalizedRect(
          boundaries[index] / image.width,
          row.top,
          boundaries[index + 1] / image.width,
          row.bottom,
        ),
    ];
  }

  int _safestVerticalCut(
    img.Image image,
    int target,
    int radius,
    int left,
    int right,
    int top,
    int bottom,
  ) {
    final start = (target - radius).clamp(left + 2, right - 3);
    final end = (target + radius).clamp(start + 1, right - 2);
    final background = _edgeBackground(image, left, right, top, bottom);
    final yStep = ((bottom - top) / 500).ceil().clamp(1, bottom - top);
    var best = target.clamp(start, end);
    var bestScore = double.infinity;
    for (var x = start; x <= end; x += 1) {
      var score = 0.0;
      for (var y = top; y < bottom; y += yStep) {
        score += (_luminance(image.getPixel(x, y)) - background).abs();
      }
      final targetPenalty = (x - target).abs() * 0.01;
      if (score + targetPenalty < bestScore) {
        bestScore = score + targetPenalty;
        best = x;
      }
    }
    return best;
  }

  double _edgeBackground(
    img.Image image,
    int left,
    int right,
    int top,
    int bottom,
  ) {
    final samples = [
      image.getPixel(left, top),
      image.getPixel(right - 1, top),
      image.getPixel(left, bottom - 1),
      image.getPixel(right - 1, bottom - 1),
    ];
    return samples.map(_luminance).reduce((a, b) => a + b) / samples.length;
  }

  double _luminance(img.Pixel pixel) =>
      pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722;

  Uint8List _encodeRect(img.Image image, NormalizedRect row) {
    final left = (row.left * image.width).floor().clamp(0, image.width - 1);
    final right = (row.right * image.width).ceil().clamp(left + 1, image.width);
    final top = (row.top * image.height).floor().clamp(0, image.height - 1);
    final bottom = (row.bottom * image.height).ceil().clamp(
      top + 1,
      image.height,
    );
    final cropped = img.copyCrop(
      image,
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
    );
    return Uint8List.fromList(img.encodePng(cropped, level: 3));
  }

  void _paintOpaqueHighlight(img.Image image, _PixelRect rect) {
    const opacity = 0.32;
    const red = 255.0;
    const green = 225.0;
    const blue = 40.0;
    final right = (rect.x + rect.width).clamp(0, image.width);
    final bottom = (rect.y + rect.height).clamp(0, image.height);
    for (var y = rect.y; y < bottom; y += 1) {
      for (var x = rect.x; x < right; x += 1) {
        final pixel = image.getPixel(x, y);
        image.setPixelRgba(
          x,
          y,
          pixel.r * (1 - opacity) + red * opacity,
          pixel.g * (1 - opacity) + green * opacity,
          pixel.b * (1 - opacity) + blue * opacity,
          255,
        );
      }
    }
  }

  img.Image _applyTreatment(img.Image image, VisualTreatment treatment) {
    return switch (treatment) {
      VisualTreatment.original => image,
      VisualTreatment.grayscale => img.grayscale(image),
      VisualTreatment.invert => img.invert(image),
      VisualTreatment.highContrast => img.adjustColor(
        img.grayscale(image),
        contrast: 1.8,
      ),
      VisualTreatment.invertedHighContrast => img.adjustColor(
        img.grayscale(img.invert(image)),
        contrast: 2.1,
      ),
    };
  }

  _PixelRect _pixelRect(NormalizedRect rect, int width, int height) {
    final x = (rect.left * width).floor().clamp(0, width - 1);
    final y = (rect.top * height).floor().clamp(0, height - 1);
    final right = (rect.right * width).ceil().clamp(x + 1, width);
    final bottom = (rect.bottom * height).ceil().clamp(y + 1, height);
    return _PixelRect(x, y, right - x, bottom - y);
  }
}

class ProcessedExportImage {
  const ProcessedExportImage(
    this.bytes,
    this.aspectRatio, {
    required this.sourceRect,
  });

  final Uint8List bytes;
  final double aspectRatio;
  final NormalizedRect sourceRect;
}

class _PixelRect {
  const _PixelRect(this.x, this.y, this.width, this.height);
  final int x;
  final int y;
  final int width;
  final int height;
}
