import 'dart:typed_data';

import '../domain/library_models.dart';
import '../domain/device_preferences.dart';
import '../domain/music_models.dart';
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

class SongBundleImportResult {
  const SongBundleImportResult({
    required this.importedVariantIds,
    required this.skippedVariantIds,
  });

  final List<String> importedVariantIds;
  final List<String> skippedVariantIds;
}

abstract interface class SongBundleTransfer {
  Future<Uint8List> exportSongBytes(String chartVariantId);
  Future<SongBundleImportResult> importSongBytes(Uint8List bytes);
  Future<String?> exportSongWithPicker(String chartVariantId);
  Future<SongBundleImportResult?> importSongWithPicker();
}

enum StateImportMode { merge, replace }

class LibraryStateImportResult {
  const LibraryStateImportResult({
    required this.importedVariants,
    required this.skippedVariants,
    required this.importedSetlists,
    this.backupPath,
  });

  final int importedVariants;
  final int skippedVariants;
  final int importedSetlists;
  final String? backupPath;
}

abstract interface class LibraryStateTransfer {
  Future<Uint8List> exportStateBytes();
  Future<LibraryStateImportResult> importStateBytes(
    Uint8List bytes, {
    required StateImportMode mode,
    bool Function()? isCancelled,
  });
  Future<String?> exportStateWithPicker();
  Future<LibraryStateImportResult?> importStateWithPicker(StateImportMode mode);
  Future<List<String>> listBackups();
  Future<LibraryStateImportResult> restoreBackup(String path);
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

abstract interface class SemanticChartLibrary {
  Future<void> saveSemanticChart(
    SongChart chart, {
    required String songId,
    required DateTime updatedAt,
  });
  Future<List<SongChart>> listSemanticCharts();
  Future<SongChart?> loadSemanticChart(String id);
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

abstract interface class SemanticChartPdfExporter {
  Future<Uint8List> exportSemanticBytes(
    SongChart chart, {
    required bool showTitle,
    required bool showTab,
    required bool showNotation,
  });
  Future<String?> exportSemanticWithPicker(
    SongChart chart, {
    required bool showTitle,
    required bool showTab,
    required bool showNotation,
  });
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
