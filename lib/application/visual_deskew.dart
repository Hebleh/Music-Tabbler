import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../domain/visual_chart_models.dart';

const maximumDeskewDegrees = 7.0;

VisualStrip reprojectVisualStripDeskew(
  VisualStrip strip,
  double targetDegrees,
) {
  final target = targetDegrees.clamp(
    -maximumDeskewDegrees,
    maximumDeskewDegrees,
  );
  if ((target - strip.deskewDegrees).abs() < 0.0001) return strip;
  final base =
      strip.deskewBaseGeometry ??
      VisualDeskewBaseGeometry(
        crop: strip.crop,
        lyricBand: strip.lyricBand,
        highlights: strip.highlights,
        annotations: strip.annotations,
      );
  if (target.abs() < 0.0001) {
    return strip.copyWith(
      crop: base.crop,
      lyricBand: base.lyricBand,
      clearLyricBand: base.lyricBand == null,
      highlights: base.highlights,
      annotations: base.annotations,
      deskewDegrees: 0,
      clearDeskewBaseGeometry: true,
    );
  }

  NormalizedPoint mapAssetPoint(NormalizedPoint point) => _mapDeskewPoint(
    point,
    width: strip.pixelWidth.toDouble(),
    height: strip.pixelHeight.toDouble(),
    fromDegrees: 0,
    toDegrees: target,
  );

  NormalizedRect mapAssetRect(NormalizedRect rect) => _boundingRect([
    mapAssetPoint(NormalizedPoint(rect.left, rect.top)),
    mapAssetPoint(NormalizedPoint(rect.right, rect.top)),
    mapAssetPoint(NormalizedPoint(rect.right, rect.bottom)),
    mapAssetPoint(NormalizedPoint(rect.left, rect.bottom)),
  ]);

  final targetCrop = mapAssetRect(base.crop);
  final annotations = <VisualAnnotationStroke>[];
  for (final stroke in base.annotations) {
    final points = <NormalizedPoint>[];
    for (final point in stroke.points) {
      final currentAsset = NormalizedPoint(
        base.crop.left + point.x * base.crop.width,
        base.crop.top + point.y * base.crop.height,
        pressure: point.pressure,
      );
      final targetAsset = mapAssetPoint(currentAsset);
      points.add(
        NormalizedPoint(
          ((targetAsset.x - targetCrop.left) / targetCrop.width).clamp(
            0.0,
            1.0,
          ),
          ((targetAsset.y - targetCrop.top) / targetCrop.height).clamp(
            0.0,
            1.0,
          ),
          pressure: point.pressure,
        ),
      );
    }
    annotations.add(
      VisualAnnotationStroke(
        id: stroke.id,
        points: points,
        colorArgb: stroke.colorArgb,
        width: stroke.width,
      ),
    );
  }

  return strip.copyWith(
    crop: targetCrop,
    lyricBand: base.lyricBand == null ? null : mapAssetRect(base.lyricBand!),
    clearLyricBand: base.lyricBand == null,
    highlights: [
      for (final highlight in base.highlights)
        VisualHighlight(id: highlight.id, rect: mapAssetRect(highlight.rect)),
    ],
    annotations: annotations,
    deskewDegrees: target,
    deskewBaseGeometry: base,
  );
}

img.Image applyDeskewRotation(img.Image source, double degrees) {
  if (degrees.abs() < 0.0001) return source;
  final background = _edgeBackground(source);
  final rotated = img.copyRotate(
    source,
    angle: degrees,
    interpolation: img.Interpolation.cubic,
  );
  for (final pixel in rotated) {
    if (pixel.a.toInt() == 0) {
      rotated.setPixel(pixel.x, pixel.y, background);
    }
  }
  return rotated;
}

NormalizedPoint _mapDeskewPoint(
  NormalizedPoint point, {
  required double width,
  required double height,
  required double fromDegrees,
  required double toDegrees,
}) {
  final fromSize = _rotatedSize(width, height, fromDegrees);
  final toSize = _rotatedSize(width, height, toDegrees);
  final fromRadians = fromDegrees * math.pi / 180;
  final fromCos = math.cos(fromRadians);
  final fromSin = math.sin(fromRadians);
  final fromX = point.x * fromSize.$1 - fromSize.$1 / 2;
  final fromY = point.y * fromSize.$2 - fromSize.$2 / 2;
  final originalX = fromX * fromCos + fromY * fromSin;
  final originalY = -fromX * fromSin + fromY * fromCos;

  final toRadians = toDegrees * math.pi / 180;
  final toCos = math.cos(toRadians);
  final toSin = math.sin(toRadians);
  final targetX = originalX * toCos - originalY * toSin + toSize.$1 / 2;
  final targetY = originalX * toSin + originalY * toCos + toSize.$2 / 2;
  return NormalizedPoint(
    (targetX / toSize.$1).clamp(0.0, 1.0),
    (targetY / toSize.$2).clamp(0.0, 1.0),
    pressure: point.pressure,
  );
}

(double, double) _rotatedSize(double width, double height, double degrees) {
  final radians = degrees * math.pi / 180;
  return (
    (width * math.cos(radians)).abs() + (height * math.sin(radians)).abs(),
    (width * math.sin(radians)).abs() + (height * math.cos(radians)).abs(),
  );
}

NormalizedRect _boundingRect(List<NormalizedPoint> points) {
  final left = points.map((point) => point.x).reduce(math.min);
  final top = points.map((point) => point.y).reduce(math.min);
  final right = points.map((point) => point.x).reduce(math.max);
  final bottom = points.map((point) => point.y).reduce(math.max);
  final safeLeft = left.clamp(0.0, 0.999);
  final safeTop = top.clamp(0.0, 0.999);
  final safeRight = right.clamp(safeLeft + 0.001, 1.0);
  final safeBottom = bottom.clamp(safeTop + 0.001, 1.0);
  return NormalizedRect(safeLeft, safeTop, safeRight, safeBottom);
}

img.Color _edgeBackground(img.Image image) {
  final samples = <img.Pixel>[
    image.getPixel(0, 0),
    image.getPixel(image.width - 1, 0),
    image.getPixel(0, image.height - 1),
    image.getPixel(image.width - 1, image.height - 1),
  ]..sort((left, right) => _luminance(left).compareTo(_luminance(right)));
  final sample = samples[samples.length ~/ 2];
  return img.ColorRgba8(
    sample.r.toInt(),
    sample.g.toInt(),
    sample.b.toInt(),
    sample.a.toInt(),
  );
}

double _luminance(img.Color color) =>
    color.r.toDouble() * 0.299 +
    color.g.toDouble() * 0.587 +
    color.b.toDouble() * 0.114;
