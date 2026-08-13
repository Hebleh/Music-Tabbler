import 'dart:typed_data';

import '../domain/library_models.dart';
import '../domain/visual_chart_models.dart';

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
    this.skippedVariantIds = const [],
    this.backupPath,
  });

  final int importedVariants;
  final int skippedVariants;
  final int importedSetlists;
  final List<String> skippedVariantIds;
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
  Future<StoredAsset> storeAsset(List<int> bytes, String extension);
  Future<void> saveDraft(VisualChartDraft draft);
  Future<void> deleteDraft(String id);
  Future<void> deleteDraftAndRemoveSetlistReferences(
    String id, {
    required DateTime updatedAt,
  });
  Future<List<VisualChartDraft>> listDrafts();
  Future<VisualChartDraft?> loadDraft(String id);
}

class StoredAsset {
  const StoredAsset({
    required this.hash,
    required this.extension,
    required this.path,
  });

  final String hash;
  final String extension;
  final String path;
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

/// The single persistence boundary needed by portable state and song bundles.
/// Archive services never inspect LocalLibrary directories or SQLite directly.
abstract interface class PortableLibraryStore
    implements ChartLibrary, SongVariantLibrary, SetlistLibrary {
  Future<List<String>> assetNamesWithHash(String hash);
  Future<Uint8List> readAssetByName(String name);
  Future<void> installVisualStateAtomically({
    required List<({VisualChartDraft draft, String songId})> variants,
    required List<LibrarySetlist> setlists,
    required bool replace,
  });
  Future<String> writeRotatingBackup(Uint8List bytes, {required int retention});
  Future<List<String>> listBackupPaths();
  Future<Uint8List> readBackup(String path);
}
