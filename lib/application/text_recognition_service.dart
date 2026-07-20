import 'dart:ui';

import 'package:flutter_ocr_native/flutter_ocr_native.dart';

import '../domain/visual_chart_models.dart';
import 'service_contracts.dart';

class NativeTextRecognitionService implements TextRecognitionService {
  NativeTextRecognitionService(this.library);

  final ChartLibrary library;
  final OcrReader _reader = OcrReader();
  final Map<String, Future<MetadataSuggestion>> _cache = {};

  @override
  Future<MetadataSuggestion> recognize(VisualStrip strip) {
    return _cache.putIfAbsent(strip.assetHash, () => _recognize(strip));
  }

  Future<MetadataSuggestion> _recognize(VisualStrip strip) async {
    final result = await _reader.readFromPath(
      library.assetPath(strip.assetHash, strip.assetExtension),
    );
    final lines = [for (final block in result.blocks) ...block.lines]
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    final regions = <RecognizedTextRegion>[];
    for (final line in lines) {
      if (line.elements.isEmpty) {
        _addRegion(regions, line.text, line.boundingBox, strip);
      } else {
        for (final element in line.elements) {
          _addRegion(regions, element.text, element.boundingBox, strip);
        }
      }
    }

    final metadataLines = <String>[];
    for (final line in lines) {
      if (line.boundingBox.top / strip.pixelHeight > 0.48) continue;
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
    VisualStrip strip,
  ) {
    final text = value.trim();
    if (text.isEmpty) return;
    final rect = _normalize(bounds, strip);
    if (rect != null) {
      regions.add(RecognizedTextRegion(text: text, rect: rect));
    }
  }

  NormalizedRect? _normalize(Rect value, VisualStrip strip) {
    if (value.width <= 0 || value.height <= 0) return null;
    final left = (value.left / strip.pixelWidth).clamp(0.0, 0.99);
    final top = (value.top / strip.pixelHeight).clamp(0.0, 0.99);
    final right = (value.right / strip.pixelWidth).clamp(left + 0.001, 1.0);
    final bottom = (value.bottom / strip.pixelHeight).clamp(top + 0.001, 1.0);
    return NormalizedRect(left, top, right, bottom);
  }
}

(String?, String?) inferTabMetadata(Iterable<String> recognizedLines) {
  final candidates = recognizedLines
      .map((value) => value.trim().replaceAll(RegExp(r'\s+'), ' '))
      .where(_looksLikeMetadata)
      .toList(growable: false);
  if (candidates.isEmpty) return (null, null);

  var titleIndex = candidates.indexWhere(
    (item) => RegExp(
      r'\b(bass\s+tab|guitar\s+tab|tab|chords?)\b',
      caseSensitive: false,
    ).hasMatch(item),
  );
  if (titleIndex < 0) titleIndex = 0;
  final rawTitle = candidates[titleIndex];
  final title = rawTitle
      .replaceFirst(
        RegExp(
          r'\s*[-|:]?\s*(bass\s+tab|guitar\s+tab|tab|chords?)\s*$',
          caseSensitive: false,
        ),
        '',
      )
      .trim();

  String? artist;
  for (var index = titleIndex + 1; index < candidates.length; index += 1) {
    final value = candidates[index];
    if (value.toLowerCase() != title.toLowerCase()) {
      artist = value;
      break;
    }
  }
  return (title.isEmpty ? rawTitle : title, artist);
}

bool _looksLikeMetadata(String value) {
  if (value.length < 2 || value.length > 100) return false;
  if (!RegExp(r'[A-Za-z]').hasMatch(value)) return false;
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
