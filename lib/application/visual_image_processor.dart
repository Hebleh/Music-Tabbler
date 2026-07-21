import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../domain/visual_chart_models.dart';
import 'highlight_geometry.dart';
import 'horizontal_row_detector.dart';

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
  }) {
    var decoded = img.decodeImage(sourceBytes);
    if (decoded == null) {
      throw const FormatException('Stored chart image is invalid.');
    }
    decoded = img.bakeOrientation(decoded);
    return [
      for (final strip in strips)
        _compactImage(
          _processDecoded(decoded, strip, globalTreatment: globalTreatment),
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

  List<Uint8List> compactForExport(Uint8List processedPng) {
    final decoded = img.decodePng(processedPng);
    if (decoded == null) return [processedPng];
    final detected = const HorizontalRowDetector().detect(processedPng);
    if (detected.isEmpty) return [processedPng];
    final rows = decoded.width / decoded.height < 2.2
        ? detected
        : [NormalizedRect(0, detected.first.top, 1, detected.last.bottom)];
    return [for (final row in rows) _encodeRect(decoded, row)];
  }

  List<ProcessedExportImage> _compactImage(img.Image image) {
    final rendered = Uint8List.fromList(img.encodePng(image, level: 3));
    final detected = const HorizontalRowDetector().detect(rendered);
    if (detected.isEmpty) {
      return [ProcessedExportImage(rendered, image.width / image.height)];
    }
    final rows = image.width / image.height < 2.2
        ? detected
        : [NormalizedRect(0, detected.first.top, 1, detected.last.bottom)];
    return [
      for (final row in rows)
        () {
          final top = (row.top * image.height).floor().clamp(
            0,
            image.height - 1,
          );
          final bottom = (row.bottom * image.height).ceil().clamp(
            top + 1,
            image.height,
          );
          final bytes = _encodeRect(image, row);
          return ProcessedExportImage(bytes, image.width / (bottom - top));
        }(),
    ];
  }

  Uint8List _encodeRect(img.Image image, NormalizedRect row) {
    final top = (row.top * image.height).floor().clamp(0, image.height - 1);
    final bottom = (row.bottom * image.height).ceil().clamp(
      top + 1,
      image.height,
    );
    final cropped = img.copyCrop(
      image,
      x: 0,
      y: top,
      width: image.width,
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
  const ProcessedExportImage(this.bytes, this.aspectRatio);

  final Uint8List bytes;
  final double aspectRatio;
}

class _PixelRect {
  const _PixelRect(this.x, this.y, this.width, this.height);
  final int x;
  final int y;
  final int width;
  final int height;
}
