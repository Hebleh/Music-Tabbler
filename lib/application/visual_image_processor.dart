import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../domain/visual_chart_models.dart';

class VisualImageProcessor {
  const VisualImageProcessor();

  Uint8List process(
    Uint8List sourceBytes,
    VisualStrip strip, {
    VisualTreatment? globalTreatment,
  }) {
    var image = img.decodeImage(sourceBytes);
    if (image == null) {
      throw const FormatException('Stored chart image is invalid.');
    }
    image = img.bakeOrientation(image);
    image = _applyTreatment(image, globalTreatment ?? strip.treatment);

    final lyricBand = strip.lyricBand;
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
      final rect = _pixelRect(highlight.rect, image.width, image.height);
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

    final crop = _pixelRect(strip.crop, image.width, image.height);
    final cropped = img.copyCrop(
      image,
      x: crop.x,
      y: crop.y,
      width: crop.width,
      height: crop.height,
    );
    return Uint8List.fromList(img.encodePng(cropped, level: 6));
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
}

class _PixelRect {
  const _PixelRect(this.x, this.y, this.width, this.height);
  final int x;
  final int y;
  final int width;
  final int height;
}
