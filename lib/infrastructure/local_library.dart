import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../application/service_contracts.dart';
import '../domain/library_models.dart';
import '../domain/visual_chart_models.dart';
import 'content_addressed_asset_store.dart';
import 'library_schema_migrator.dart';

class LocalLibrary implements PortableLibraryStore {
  LocalLibrary._(this.root, this._assets, this._database);

  static const currentSchemaVersion = LibrarySchemaMigrator.currentVersion;

  final Directory root;
  final ContentAddressedAssetStore _assets;
  final Database _database;

  Directory get assetsDirectory => _assets.directory;

  static Future<LocalLibrary> open() async {
    const configuredRoot = String.fromEnvironment('MUSIC_TABBLER_LIBRARY_ROOT');
    if (configuredRoot.trim().isNotEmpty) {
      return _openAtRoot(Directory(configuredRoot), inMemory: false);
    }
    final support = await getApplicationSupportDirectory();
    final root = Directory(p.join(support.path, 'Music Tabbler'));
    return _openAtRoot(root, inMemory: false);
  }

  static Future<LocalLibrary> forTesting(
    Directory root, {
    bool inMemory = true,
  }) async {
    return _openAtRoot(root, inMemory: inMemory);
  }

  static Future<LocalLibrary> _openAtRoot(
    Directory root, {
    required bool inMemory,
  }) async {
    final assets = Directory(p.join(root.path, 'assets'));
    await assets.create(recursive: true);
    final database = inMemory
        ? sqlite3.openInMemory()
        : sqlite3.open(p.join(root.path, 'library.sqlite'));
    try {
      await LibrarySchemaMigrator.migrate(
        database,
        root: root,
        assetsDirectory: assets,
      );
      database.execute('PRAGMA foreign_keys = ON;');
      return LocalLibrary._(root, ContentAddressedAssetStore(assets), database);
    } catch (_) {
      database.close();
      rethrow;
    }
  }

  @override
  Future<StoredAsset> storeAsset(List<int> bytes, String extension) =>
      _assets.store(bytes, extension);

  @override
  String assetPath(String hash, String extension) =>
      _assets.pathFor(hash, extension);

  @override
  Future<List<String>> assetNamesWithHash(String hash) =>
      _assets.namesWithHash(hash);

  @override
  Future<Uint8List> readAssetByName(String name) => _assets.readByName(name);

  Directory get _backupDirectory => Directory(p.join(root.path, 'backups'));

  @override
  Future<String> writeRotatingBackup(
    Uint8List bytes, {
    required int retention,
  }) async {
    if (retention < 1) throw ArgumentError.value(retention, 'retention');
    await _backupDirectory.create(recursive: true);
    final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final destination = File(
      p.join(_backupDirectory.path, 'backup-$stamp.mtstate'),
    );
    final partial = File('${destination.path}.partial');
    try {
      await partial.writeAsBytes(bytes, flush: true);
      await partial.rename(destination.path);
    } finally {
      if (await partial.exists()) await partial.delete();
    }
    final backups = await listBackupPaths();
    for (final old in backups.skip(retention)) {
      await File(old).delete();
    }
    return destination.path;
  }

  @override
  Future<List<String>> listBackupPaths() async {
    if (!await _backupDirectory.exists()) return const [];
    final files = await _backupDirectory
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.mtstate'))
        .cast<File>()
        .toList();
    files.sort(
      (left, right) =>
          right.lastModifiedSync().compareTo(left.lastModifiedSync()),
    );
    return List.unmodifiable(files.map((file) => file.path));
  }

  @override
  Future<Uint8List> readBackup(String path) async {
    final backupRoot = p.normalize(p.absolute(_backupDirectory.path));
    final target = p.normalize(p.absolute(path));
    if (!p.isWithin(backupRoot, target)) {
      throw ArgumentError.value(
        path,
        'path',
        'Backup path is outside storage.',
      );
    }
    return File(target).readAsBytes();
  }

  @override
  Future<void> saveDraft(VisualChartDraft draft) async {
    final existing = _database.select(
      'SELECT song_id FROM chart_variants WHERE id = ? LIMIT 1;',
      [draft.id],
    );
    final songId = existing.isEmpty
        ? legacySongId(draft.id)
        : existing.single['song_id'] as String;
    await saveDraftAsVariant(draft, songId: songId);
  }

  @override
  Future<void> saveDraftAsVariant(
    VisualChartDraft draft, {
    required String songId,
  }) async {
    _inTransaction(() => _saveDraftAsVariant(draft, songId));
  }

  Future<void> saveDraftVariantsAtomically(
    List<({VisualChartDraft draft, String songId})> variants,
  ) async {
    _inTransaction(() {
      for (final variant in variants) {
        _saveDraftAsVariant(variant.draft, variant.songId);
      }
    });
  }

  void _saveDraftAsVariant(VisualChartDraft draft, String songId) {
    final existing = _database.select(
      'SELECT song_id FROM chart_variants WHERE id = ? LIMIT 1;',
      [draft.id],
    );
    if (existing.isNotEmpty && existing.single['song_id'] != songId) {
      throw StateError(
        'Chart variant ${draft.id} already belongs to another song.',
      );
    }

    _database.execute(
      '''
        INSERT INTO songs (id, title, artist, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          title = excluded.title,
          artist = excluded.artist,
          updated_at = excluded.updated_at;
      ''',
      [
        songId,
        draft.title,
        draft.artist,
        draft.createdAt.toIso8601String(),
        draft.updatedAt.toIso8601String(),
      ],
    );
    _database.execute(
      '''
        INSERT INTO chart_variants (
          id, song_id, created_at, updated_at
        ) VALUES (?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          updated_at = excluded.updated_at;
      ''',
      [
        draft.id,
        songId,
        draft.createdAt.toIso8601String(),
        draft.updatedAt.toIso8601String(),
      ],
    );

    final statement = _database.prepare('''
      INSERT INTO visual_charts (id, title, artist, updated_at, payload_json)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        title = excluded.title,
        artist = excluded.artist,
        updated_at = excluded.updated_at,
        payload_json = excluded.payload_json;
    ''');
    try {
      statement.execute([
        draft.id,
        draft.title,
        draft.artist,
        draft.updatedAt.toIso8601String(),
        draft.encode(),
      ]);
    } finally {
      statement.close();
    }
  }

  @override
  Future<void> deleteDraft(String id) async {
    _deleteDraft(id, removeSetlistReferences: false);
  }

  @override
  Future<void> deleteDraftAndRemoveSetlistReferences(
    String id, {
    required DateTime updatedAt,
  }) async {
    _deleteDraft(id, removeSetlistReferences: true, updatedAt: updatedAt);
  }

  void _deleteDraft(
    String id, {
    required bool removeSetlistReferences,
    DateTime? updatedAt,
  }) {
    _inTransaction(() {
      final rows = _database.select(
        'SELECT song_id FROM chart_variants WHERE id = ? LIMIT 1;',
        [id],
      );
      final references = _database.select(
        '''
        SELECT DISTINCT setlist_id
        FROM setlist_entries
        WHERE chart_variant_id = ?
        ORDER BY setlist_id ASC;
      ''',
        [id],
      );
      if (references.isNotEmpty) {
        if (!removeSetlistReferences) {
          throw ChartVariantReferencedBySetlistsException(
            chartVariantId: id,
            setlistIds: references
                .map((row) => row['setlist_id'] as String)
                .toList(growable: false),
          );
        }
        final resolvedUpdatedAt = updatedAt;
        if (resolvedUpdatedAt == null) {
          throw ArgumentError.notNull('updatedAt');
        }
        _database.execute(
          '''
          UPDATE setlists
          SET updated_at = ?
          WHERE id IN (
            SELECT DISTINCT setlist_id
            FROM setlist_entries
            WHERE chart_variant_id = ?
          );
        ''',
          [resolvedUpdatedAt.toIso8601String(), id],
        );
        _database.execute(
          'DELETE FROM setlist_entries WHERE chart_variant_id = ?;',
          [id],
        );
      }
      _database.execute('DELETE FROM visual_charts WHERE id = ?;', [id]);
      _database.execute('DELETE FROM chart_variants WHERE id = ?;', [id]);
      if (rows.isNotEmpty) {
        _database.execute(
          '''
          DELETE FROM songs
          WHERE id = ?
            AND NOT EXISTS (
              SELECT 1 FROM chart_variants WHERE song_id = ?
            );
        ''',
          [rows.single['song_id'], rows.single['song_id']],
        );
      }
    });
  }

  @override
  Future<List<VisualChartDraft>> listDrafts() async {
    final rows = _database.select(
      'SELECT payload_json FROM visual_charts ORDER BY updated_at DESC;',
    );
    return rows
        .map((row) => VisualChartDraft.decode(row['payload_json'] as String))
        .toList(growable: false);
  }

  @override
  Future<VisualChartDraft?> loadDraft(String id) async {
    final rows = _database.select(
      'SELECT payload_json FROM visual_charts WHERE id = ? LIMIT 1;',
      [id],
    );
    if (rows.isEmpty) return null;
    return VisualChartDraft.decode(rows.single['payload_json'] as String);
  }

  @override
  Future<List<LibrarySong>> listSongs() async {
    final rows = _database.select('''
      SELECT id, title, artist, created_at, updated_at
      FROM songs
      ORDER BY updated_at DESC, id ASC;
    ''');
    return rows
        .map(
          (row) => LibrarySong(
            id: row['id'] as String,
            title: row['title'] as String,
            artist: row['artist'] as String,
            createdAt: DateTime.parse(row['created_at'] as String),
            updatedAt: DateTime.parse(row['updated_at'] as String),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<ChartVariantIdentity>> listVariants(String songId) async {
    final rows = _database.select(
      '''
      SELECT id, song_id, created_at, updated_at
      FROM chart_variants
      WHERE song_id = ?
      ORDER BY updated_at DESC, id ASC;
    ''',
      [songId],
    );
    return rows.map(_variantFromRow).toList(growable: false);
  }

  @override
  Future<ChartVariantIdentity?> identityForDraft(String draftId) async {
    final rows = _database.select(
      '''
      SELECT id, song_id, created_at, updated_at
      FROM chart_variants
      WHERE id = ?
      LIMIT 1;
    ''',
      [draftId],
    );
    return rows.isEmpty ? null : _variantFromRow(rows.single);
  }

  static ChartVariantIdentity _variantFromRow(Row row) {
    return ChartVariantIdentity(
      id: row['id'] as String,
      songId: row['song_id'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  @override
  Future<void> saveSetlist(LibrarySetlist setlist) async {
    _validateSetlistEntries(setlist.entries);
    _inTransaction(() => _saveSetlist(setlist));
  }

  @override
  Future<void> installVisualStateAtomically({
    required List<({VisualChartDraft draft, String songId})> variants,
    required List<LibrarySetlist> setlists,
    required bool replace,
  }) async {
    for (final setlist in setlists) {
      _validateSetlistEntries(setlist.entries);
    }
    _inTransaction(() {
      if (replace) {
        _database.execute('DELETE FROM setlist_entries;');
        _database.execute('DELETE FROM setlists;');
        _database.execute('DELETE FROM visual_charts;');
        _database.execute('DELETE FROM chart_variants;');
        _database.execute('DELETE FROM songs;');
      }
      for (final variant in variants) {
        _saveDraftAsVariant(variant.draft, variant.songId);
      }
      for (final setlist in setlists) {
        _saveSetlist(setlist);
      }
    });
  }

  void _saveSetlist(LibrarySetlist setlist) {
    _requireChartVariants(
      setlist.entries
          .where((entry) => entry.kind == SetlistEntryKind.chart)
          .map((entry) => entry.chartVariantId!),
    );
    _requireEntryIdsAvailableForSetlist(setlist.id, setlist.entries);
    _database.execute(
      '''
        INSERT INTO setlists (
          id, name, scheduled_at, notes, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          name = excluded.name,
          scheduled_at = excluded.scheduled_at,
          notes = excluded.notes,
          updated_at = excluded.updated_at;
      ''',
      [
        setlist.id,
        setlist.name,
        setlist.scheduledAt?.toIso8601String(),
        setlist.notes,
        setlist.createdAt.toIso8601String(),
        setlist.updatedAt.toIso8601String(),
      ],
    );
    _database.execute('DELETE FROM setlist_entries WHERE setlist_id = ?;', [
      setlist.id,
    ]);
    final statement = _database.prepare('''
        INSERT INTO setlist_entries (
          id,
          setlist_id,
          entry_kind,
          chart_variant_id,
          placeholder_title,
          position
        ) VALUES (?, ?, ?, ?, ?, ?);
      ''');
    try {
      for (var index = 0; index < setlist.entries.length; index++) {
        final entry = setlist.entries[index];
        statement.execute([
          entry.id,
          setlist.id,
          entry.kind.name,
          entry.chartVariantId,
          entry.placeholderTitle,
          index,
        ]);
      }
    } finally {
      statement.close();
    }
  }

  @override
  Future<List<LibrarySetlist>> listSetlists() async {
    final rows = _database.select('''
      SELECT id, name, scheduled_at, notes, created_at, updated_at
      FROM setlists
      ORDER BY updated_at DESC, id ASC;
    ''');
    return rows.map(_setlistFromRow).toList(growable: false);
  }

  @override
  Future<LibrarySetlist?> loadSetlist(String id) async {
    final rows = _database.select(
      '''
      SELECT id, name, scheduled_at, notes, created_at, updated_at
      FROM setlists
      WHERE id = ?
      LIMIT 1;
    ''',
      [id],
    );
    return rows.isEmpty ? null : _setlistFromRow(rows.single);
  }

  @override
  Future<void> reorderSetlistEntries(
    String setlistId,
    List<String> orderedEntryIds, {
    required DateTime updatedAt,
  }) async {
    if (orderedEntryIds.toSet().length != orderedEntryIds.length) {
      throw ArgumentError.value(
        orderedEntryIds,
        'orderedEntryIds',
        'Entry IDs must be unique.',
      );
    }
    _inTransaction(() {
      final currentRows = _database.select(
        '''
        SELECT id
        FROM setlist_entries
        WHERE setlist_id = ?
        ORDER BY position ASC, id ASC;
      ''',
        [setlistId],
      );
      final currentIds = currentRows
          .map((row) => row['id'] as String)
          .toList(growable: false);
      if (currentIds.toSet().difference(orderedEntryIds.toSet()).isNotEmpty ||
          orderedEntryIds.toSet().difference(currentIds.toSet()).isNotEmpty) {
        throw ArgumentError.value(
          orderedEntryIds,
          'orderedEntryIds',
          'Reorder must contain every current entry exactly once.',
        );
      }
      if (currentRows.isEmpty &&
          _database.select('SELECT 1 FROM setlists WHERE id = ? LIMIT 1;', [
            setlistId,
          ]).isEmpty) {
        throw StateError('Setlist $setlistId does not exist.');
      }

      // Offset first so the unique (setlist_id, position) constraint cannot
      // collide while positions are being reassigned.
      _database.execute(
        '''
        UPDATE setlist_entries
        SET position = position + 1000000
        WHERE setlist_id = ?;
      ''',
        [setlistId],
      );
      final statement = _database.prepare('''
        UPDATE setlist_entries
        SET position = ?
        WHERE id = ? AND setlist_id = ?;
      ''');
      try {
        for (var index = 0; index < orderedEntryIds.length; index++) {
          statement.execute([index, orderedEntryIds[index], setlistId]);
        }
      } finally {
        statement.close();
      }
      _database.execute('UPDATE setlists SET updated_at = ? WHERE id = ?;', [
        updatedAt.toIso8601String(),
        setlistId,
      ]);
    });
  }

  @override
  Future<void> deleteSetlist(String id) async {
    _database.execute('DELETE FROM setlists WHERE id = ?;', [id]);
  }

  LibrarySetlist _setlistFromRow(Row row) {
    final id = row['id'] as String;
    final entryRows = _database.select(
      '''
      SELECT id, entry_kind, chart_variant_id, placeholder_title
      FROM setlist_entries
      WHERE setlist_id = ?
      ORDER BY position ASC, id ASC;
    ''',
      [id],
    );
    return LibrarySetlist(
      id: id,
      name: row['name'] as String,
      scheduledAt: _optionalDateTime(row['scheduled_at']),
      notes: row['notes'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      entries: entryRows
          .map((entry) {
            final kind = SetlistEntryKind.values.byName(
              entry['entry_kind'] as String,
            );
            return switch (kind) {
              SetlistEntryKind.chart => LibrarySetlistEntry(
                id: entry['id'] as String,
                chartVariantId: entry['chart_variant_id'] as String,
              ),
              SetlistEntryKind.placeholder => LibrarySetlistEntry.placeholder(
                id: entry['id'] as String,
                title: entry['placeholder_title'] as String,
              ),
            };
          })
          .toList(growable: false),
    );
  }

  void _requireChartVariants(Iterable<String> chartVariantIds) {
    final missing = <String>[];
    for (final id in chartVariantIds.toSet()) {
      if (_database.select(
        'SELECT 1 FROM chart_variants WHERE id = ? LIMIT 1;',
        [id],
      ).isEmpty) {
        missing.add(id);
      }
    }
    if (missing.isNotEmpty) {
      missing.sort();
      throw MissingChartVariantReferencesException(List.unmodifiable(missing));
    }
  }

  void _requireEntryIdsAvailableForSetlist(
    String setlistId,
    List<LibrarySetlistEntry> entries,
  ) {
    final conflicts = <String>[];
    for (final entry in entries) {
      final rows = _database.select(
        'SELECT setlist_id FROM setlist_entries WHERE id = ? LIMIT 1;',
        [entry.id],
      );
      if (rows.isNotEmpty && rows.single['setlist_id'] != setlistId) {
        conflicts.add(entry.id);
      }
    }
    if (conflicts.isNotEmpty) {
      conflicts.sort();
      throw SetlistEntryIdentityConflictException(conflicts);
    }
  }

  static void _validateSetlistEntries(List<LibrarySetlistEntry> entries) {
    final ids = entries.map((entry) => entry.id).toList(growable: false);
    if (ids.toSet().length != ids.length) {
      throw ArgumentError.value(
        ids,
        'setlist.entries',
        'Entry IDs must be unique.',
      );
    }
    for (final entry in entries) {
      switch (entry.kind) {
        case SetlistEntryKind.chart:
          if (entry.chartVariantId == null ||
              entry.chartVariantId!.trim().isEmpty ||
              entry.placeholderTitle != null) {
            throw ArgumentError.value(
              entry.id,
              'setlist.entries',
              'Chart entries require a non-empty chart variant ID.',
            );
          }
        case SetlistEntryKind.placeholder:
          if (entry.chartVariantId != null ||
              entry.placeholderTitle == null ||
              entry.placeholderTitle!.trim().isEmpty) {
            throw ArgumentError.value(
              entry.id,
              'setlist.entries',
              'Placeholder entries require a non-empty title.',
            );
          }
      }
    }
  }

  static DateTime? _optionalDateTime(Object? value) =>
      value == null ? null : DateTime.parse(value as String);

  void _inTransaction(void Function() operation) {
    _database.execute('BEGIN IMMEDIATE;');
    try {
      operation();
      _database.execute('COMMIT;');
    } catch (_) {
      _database.execute('ROLLBACK;');
      rethrow;
    }
  }

  void close() => _database.close();
}
