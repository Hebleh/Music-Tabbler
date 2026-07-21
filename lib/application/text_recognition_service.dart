import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_ocr_native/flutter_ocr_native.dart';
import 'package:image/image.dart' as img;

import '../domain/visual_chart_models.dart';
import 'service_contracts.dart';

class NativeTextRecognitionService implements TextRecognitionService {
  NativeTextRecognitionService(this.library);

  final ChartLibrary library;
  final OcrReader _reader = OcrReader();
  final Map<String, Future<MetadataSuggestion>> _cache = {};

  @override
  Future<MetadataSuggestion> recognize(VisualStrip strip) {
    return _cache.putIfAbsent(
      textRecognitionCacheKey(strip),
      () => _recognize(strip),
    );
  }

  Future<MetadataSuggestion> _recognize(VisualStrip strip) async {
    final prepared = await _prepareForRecognition(
      library.assetPath(strip.assetHash, strip.assetExtension),
      strip.crop,
    );
    final result = await _reader.readFromBytes(prepared.bytes);
    final lines = [for (final block in result.blocks) ...block.lines]
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    final regions = <RecognizedTextRegion>[];
    for (final line in lines) {
      if (line.elements.isEmpty) {
        _addRegion(regions, line.text, line.boundingBox, prepared);
      } else {
        for (final element in line.elements) {
          _addRegion(regions, element.text, element.boundingBox, prepared);
        }
      }
    }

    final metadataLines = <String>[];
    for (final line in lines) {
      if (line.boundingBox.top / prepared.height > 0.48) continue;
      metadataLines.add(line.text);
    }
    final metadata = inferTabMetadata(metadataLines);
    return MetadataSuggestion(
      title: metadata.$1,
      artist: metadata.$2,
      regions: regions,
    );
  }

  void _addRegion(
    List<RecognizedTextRegion> regions,
    String value,
    Rect bounds,
    _PreparedOcrImage prepared,
  ) {
    final text = value.trim();
    if (text.isEmpty) return;
    final rect = _normalize(bounds, prepared.width, prepared.height);
    if (rect != null) {
      regions.add(RecognizedTextRegion(text: text, rect: rect));
    }
  }

  NormalizedRect? _normalize(Rect value, int width, int height) {
    if (value.width <= 0 || value.height <= 0) return null;
    final left = (value.left / width).clamp(0.0, 0.99);
    final top = (value.top / height).clamp(0.0, 0.99);
    final right = (value.right / width).clamp(left + 0.001, 1.0);
    final bottom = (value.bottom / height).clamp(top + 0.001, 1.0);
    return NormalizedRect(left, top, right, bottom);
  }

  Future<_PreparedOcrImage> _prepareForRecognition(
    String path,
    NormalizedRect crop,
  ) async {
    return compute(_prepareOcrImage, {'path': path, 'crop': crop.toJson()});
  }
}

String textRecognitionCacheKey(VisualStrip strip) {
  final crop = strip.crop;
  return '${strip.assetHash}:'
      '${crop.left.toStringAsFixed(6)}:'
      '${crop.top.toStringAsFixed(6)}:'
      '${crop.right.toStringAsFixed(6)}:'
      '${crop.bottom.toStringAsFixed(6)}';
}

_PreparedOcrImage _prepareOcrImage(Map<String, Object> request) {
  final path = request['path']! as String;
  final crop = NormalizedRect.fromJson(
    (request['crop']! as Map).cast<String, Object?>(),
  );
  var image = img.decodeImage(File(path).readAsBytesSync());
  if (image == null) {
    throw const FormatException('Stored chart image is invalid.');
  }
  image = img.bakeOrientation(image);
  final x = (crop.left * image.width).floor().clamp(0, image.width - 1);
  final y = (crop.top * image.height).floor().clamp(0, image.height - 1);
  final right = (crop.right * image.width).ceil().clamp(x + 1, image.width);
  final bottom = (crop.bottom * image.height).ceil().clamp(y + 1, image.height);
  image = img.copyCrop(image, x: x, y: y, width: right - x, height: bottom - y);

  var scale = 1.0;
  if (image.width < 3200) scale = 3200 / image.width;
  if (image.height * scale < 240) scale = 240 / image.height;
  if (image.width * scale > 4800) scale = 4800 / image.width;
  if (scale > 1.01) {
    image = img.copyResize(
      image,
      width: (image.width * scale).round(),
      interpolation: img.Interpolation.cubic,
    );
  }
  var luminance = 0.0;
  var samples = 0;
  final stepX = (image.width ~/ 80).clamp(1, image.width);
  final stepY = (image.height ~/ 80).clamp(1, image.height);
  for (var y = 0; y < image.height; y += stepY) {
    for (var x = 0; x < image.width; x += stepX) {
      final pixel = image.getPixel(x, y);
      luminance +=
          pixel.r.toDouble() * 0.299 +
          pixel.g.toDouble() * 0.587 +
          pixel.b.toDouble() * 0.114;
      samples += 1;
    }
  }
  image = img.grayscale(image);
  if (samples > 0 && luminance / samples < 118) image = img.invert(image);
  image = img.adjustColor(image, contrast: 1.35);
  return _PreparedOcrImage(
    Uint8List.fromList(img.encodePng(image, level: 2)),
    image.width,
    image.height,
  );
}

class _PreparedOcrImage {
  const _PreparedOcrImage(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width;
  final int height;
}

(String?, String?) inferTabMetadata(Iterable<String> recognizedLines) {
  final candidates = recognizedLines
      .map((value) => value.trim().replaceAll(RegExp(r'\s+'), ' '))
      .where(_looksLikeMetadata)
      .toList(growable: false);
  if (candidates.isEmpty) return (null, null);

  var titleIndex = candidates.indexWhere(
    (item) => RegExp(
      r'\b(bass\s+transcription|bass\s+tab|guitar\s+tab|tab|chords?)\b',
      caseSensitive: false,
    ).hasMatch(item),
  );
  if (titleIndex < 0) titleIndex = 0;
  final rawTitle = candidates[titleIndex];
  var title = rawTitle
      .replaceFirst(
        RegExp(
          r'\s*[-|:]?\s*(bass\s+transcription|bass\s+tab|guitar\s+tab|tab|chords?)\s*$',
          caseSensitive: false,
        ),
        '',
      )
      .trim();

  String? artist;
  if (RegExp(
        r'\bbass\s+transcription\s*$',
        caseSensitive: false,
      ).hasMatch(rawTitle) &&
      title.contains(' - ')) {
    final separator = title.indexOf(' - ');
    artist = title.substring(0, separator).trim();
    title = title.substring(separator + 3).trim();
  }
  for (var index = titleIndex + 1; index < candidates.length; index += 1) {
    final value = candidates[index];
    final lower = value.toLowerCase();
    if (lower != title.toLowerCase() &&
        !_metadataUiWords.contains(lower) &&
        artist == null &&
        !RegExp(
          r'\b(bass\s+transcription|bass\s+tab|guitar\s+tab|tab|chords?)\b',
          caseSensitive: false,
        ).hasMatch(value)) {
      artist = value;
      break;
    }
  }
  return (title.isEmpty ? rawTitle : title, artist);
}

bool _looksLikeMetadata(String value) {
  if (value.length < 2 || value.length > 100) return false;
  if (!RegExp(r'[A-Za-z\u3040-\u30ff\u3400-\u9fff]').hasMatch(value)) {
    return false;
  }
  final lower = value.toLowerCase();
  return !lower.contains('revision from') &&
      lower != 'search' &&
      lower != 'my tabs' &&
      lower != 'new tab' &&
      lower != 'sign in' &&
      lower != 'help' &&
      !lower.contains('songsterr') &&
      !RegExp(r'^\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4}$').hasMatch(value);
}

const _metadataUiWords = {
  'tab',
  'bass tab',
  'guitar tab',
  'original',
  'synth',
  'editor',
  'download',
  'more',
};
