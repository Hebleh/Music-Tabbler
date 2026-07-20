import 'dart:typed_data';

import '../domain/visual_chart_models.dart';

abstract interface class ChartLibrary {
  String assetPath(String hash, String extension);
  Future<void> saveDraft(VisualChartDraft draft);
  Future<List<VisualChartDraft>> listDrafts();
  Future<VisualChartDraft?> loadDraft(String id);
}

abstract interface class VisualImporter {
  Future<List<VisualStrip>> pickImages();
  Future<List<VisualStrip>> pickPdf();
  Future<VisualStrip> pasteImage();
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
