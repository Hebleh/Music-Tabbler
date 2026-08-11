import 'dart:typed_data';

import '../domain/library_models.dart';
import '../domain/visual_chart_models.dart';
import 'performance_deck.dart';

abstract interface class ChartPdfExporter {
  Future<Uint8List> exportBytes(VisualChartDraft draft);
  Future<String?> exportWithPicker(VisualChartDraft draft);
}

abstract interface class SetlistPdfExporter {
  Future<Uint8List> exportSetlistBytes(
    LibrarySetlist setlist, {
    required VisualExportDensity density,
  });
  Future<String?> exportSetlistWithPicker(
    LibrarySetlist setlist, {
    required VisualExportDensity density,
  });
}

abstract interface class PerformanceDeckBuilder {
  Future<PerformanceDeck> buildPerformanceDeck(
    LibrarySetlist setlist, {
    required VisualExportDensity density,
  });
}

class SetlistPdfExportException implements Exception {
  const SetlistPdfExportException(this.message);

  final String message;

  @override
  String toString() => message;
}
