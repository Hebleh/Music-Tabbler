import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../domain/visual_chart_models.dart';

class VisualImageProcessor {
  const VisualImageProcessor();

  Uint8List process(
    Uint8List sourceBytes,
    VisualStrip strip, {
    VisualTreatment? globalTreatment,
    int? maxWidth,
  }) {
    var image = img.decodeImage(sourceBytes);
    if (image == null) {
      throw const FormatException('Stored chart image is invalid.');
    }
    image = img.bakeOrientation(image);
    final crop = _pixelRect(strip.crop, image.width, image.height);
    image = img.copyCrop(
      image,
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
        : _relativeToCrop(strip.lyricBand!, strip.crop);
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
      final relative = _relativeToCrop(highlight.rect, strip.crop);
      if (relative == null) continue;
      final rect = _pixelRect(relative, image.width, image.height);
      img.fillRect(
        image,
        x1: rect.x,
        y1: rect.y,
        x2: rect.x + rect.width,
        y2: rect.y + rect.height,
        color: img.ColorRgba8(255, 225, 40, 82),
        alphaBlend: true,
      );
    }

    return Uint8List.fromList(img.encodePng(image, level: 3));
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
    };
  }

  _PixelRect _pixelRect(NormalizedRect rect, int width, int height) {
    final x = (rect.left * width).floor().clamp(0, width - 1);
    final y = (rect.top * height).floor().clamp(0, height - 1);
    final right = (rect.right * width).ceil().clamp(x + 1, width);
    final bottom = (rect.bottom * height).ceil().clamp(y + 1, height);
    return _PixelRect(x, y, right - x, bottom - y);
  }

  NormalizedRect? _relativeToCrop(NormalizedRect rect, NormalizedRect crop) {
    final left = rect.left > crop.left ? rect.left : crop.left;
    final top = rect.top > crop.top ? rect.top : crop.top;
    final right = rect.right < crop.right ? rect.right : crop.right;
    final bottom = rect.bottom < crop.bottom ? rect.bottom : crop.bottom;
    if (right <= left || bottom <= top) return null;
    return NormalizedRect(
      (left - crop.left) / crop.width,
      (top - crop.top) / crop.height,
      (right - crop.left) / crop.width,
      (bottom - crop.top) / crop.height,
    ).clamp();
  }
}

class _PixelRect {
  const _PixelRect(this.x, this.y, this.width, this.height);
  final int x;
  final int y;
  final int width;
  final int height;
}
