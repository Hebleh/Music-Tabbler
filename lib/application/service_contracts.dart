import 'dart:typed_data';

import '../domain/library_models.dart';
import '../domain/device_preferences.dart';
import '../domain/visual_chart_models.dart';
import 'performance_deck.dart';

abstract interface class DevicePreferencesStore {
  Future<DevicePreferences> load();
  Future<void> save(DevicePreferences preferences);
}

abstract interface class PerformanceModeController {
  Future<void> setActive(bool active);
}

abstract interface class ExternalUrlOpener {
  Future<void> open(String url);
}

abstract interface class ChartLibrary {
  String assetPath(String hash, String extension);
  Future<void> saveDraft(VisualChartDraft draft);
  Future<void> deleteDraft(String id);
  Future<void> deleteDraftAndRemoveSetlistReferences(
    String id, {
    required DateTime updatedAt,
  });
  Future<List<VisualChartDraft>> listDrafts();
  Future<VisualChartDraft?> loadDraft(String id);
}

abstract interface class SongVariantLibrary {
  Future<List<LibrarySong>> listSongs();
  Future<List<ChartVariantIdentity>> listVariants(String songId);
  Future<ChartVariantIdentity?> identityForDraft(String draftId);
  Future<void> saveDraftAsVariant(
    VisualChartDraft draft, {
    required String songId,
  });
}

abstract interface class SetlistLibrary {
  Future<void> saveSetlist(LibrarySetlist setlist);
  Future<List<LibrarySetlist>> listSetlists();
  Future<LibrarySetlist?> loadSetlist(String id);
  Future<void> reorderSetlistEntries(
    String setlistId,
    List<String> orderedEntryIds, {
    required DateTime updatedAt,
  });
  Future<void> deleteSetlist(String id);
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

class ImportCancelled implements Exception {
  const ImportCancelled();
}

class VisualImportException implements Exception {
  const VisualImportException(this.message);
  final String message;
  @override
  String toString() => message;
}
