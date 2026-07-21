import 'dart:typed_data';

import '../domain/visual_chart_models.dart';

abstract interface class ChartLibrary {
  String assetPath(String hash, String extension);
  Future<void> saveDraft(VisualChartDraft draft);
  Future<void> deleteDraft(String id);
  Future<List<VisualChartDraft>> listDrafts();
  Future<VisualChartDraft?> loadDraft(String id);
}

abstract interface class VisualImporter {
  Future<List<VisualStrip>> pickImages();
  Future<List<VisualStrip>> pickPdf();
  Future<List<VisualStrip>> pasteImages();
  Future<List<VisualStrip>> importPaths(Iterable<String> paths);
}

class RecognizedTextRegion {
  const RecognizedTextRegion({required this.text, required this.rect});

  final String text;
  final NormalizedRect rect;
}

class MetadataSuggestion {
  const MetadataSuggestion({this.title, this.artist, this.regions = const []});

  final String? title;
  final String? artist;
  final List<RecognizedTextRegion> regions;
}

abstract interface class TextRecognitionService {
  Future<MetadataSuggestion> recognize(VisualStrip strip);
}

abstract interface class ChartPdfExporter {
  Future<Uint8List> exportBytes(VisualChartDraft draft);
  Future<String?> exportWithPicker(VisualChartDraft draft);
}

class ImportCancelled implements Exception {
  const ImportCancelled();
}

class VisualImportException implements Exception {
  const VisualImportException(this.message);
  final String message;
  @override
  String toString() => message;
}
