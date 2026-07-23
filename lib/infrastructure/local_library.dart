import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../application/service_contracts.dart';
import '../domain/library_models.dart';
import '../domain/visual_chart_models.dart';

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

class LocalLibrary implements ChartLibrary, SongVariantLibrary, SetlistLibrary {
  LocalLibrary._(this.root, this.assetsDirectory, this._database);

  static const currentSchemaVersion = 3;

  final Directory root;
  final Directory assetsDirectory;
  final Database _database;

  static Future<LocalLibrary> open() async {
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
      _migrate(database);
      database.execute('PRAGMA foreign_keys = ON;');
      return LocalLibrary._(root, assets, database);
    } catch (_) {
      database.close();
      rethrow;
    }
  }

  static void _migrate(Database database) {
    var version = _schemaVersion(database);
    if (version > currentSchemaVersion) {
      throw StateError(
        'Library schema $version is newer than supported schema '
        '$currentSchemaVersion.',
      );
    }

    while (version < currentSchemaVersion) {
      final nextVersion = version + 1;
      database.execute('BEGIN IMMEDIATE;');
      try {
        switch (nextVersion) {
          case 1:
            _migrateToVersion1(database);
            break;
          case 2:
            _migrateToVersion2(database);
            break;
          case 3:
            _migrateToVersion3(database);
            break;
          default:
            throw StateError('Missing library migration $nextVersion.');
        }
        database.execute('PRAGMA user_version = $nextVersion;');
        database.execute('COMMIT;');
      } catch (_) {
        database.execute('ROLLBACK;');
        rethrow;
      }
      version = nextVersion;
    }
  }

  static int _schemaVersion(Database database) {
    return database.select('PRAGMA user_version;').single['user_version']
        as int;
  }

  static void _migrateToVersion1(Database database) {
    database.execute('''
      CREATE TABLE IF NOT EXISTS visual_charts (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        payload_json TEXT NOT NULL
      );
    ''');
  }

  static void _migrateToVersion2(Database database) {
    database.execute('''
      CREATE TABLE songs (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    database.execute('''
      CREATE TABLE chart_variants (
        id TEXT PRIMARY KEY NOT NULL,
        song_id TEXT NOT NULL REFERENCES songs(id) ON DELETE CASCADE,
        kind TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    database.execute('''
      CREATE INDEX chart_variants_song_id_index
      ON chart_variants(song_id);
    ''');
    final songStatement = database.prepare('''
      INSERT INTO songs (id, title, artist, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?);
    ''');
    final variantStatement = database.prepare('''
      INSERT INTO chart_variants (
        id, song_id, kind, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?);
    ''');
    try {
      for (final row in database.select(
        'SELECT id, payload_json FROM visual_charts;',
      )) {
        final draft = VisualChartDraft.decode(row['payload_json'] as String);
        if (row['id'] != draft.id) {
          throw const FormatException(
            'Visual chart row and payload identities do not match.',
          );
        }
        final songId = _legacySongId(draft.id);
        songStatement.execute([
          songId,
          draft.title,
          draft.artist,
          draft.createdAt.toIso8601String(),
          draft.updatedAt.toIso8601String(),
        ]);
        variantStatement.execute([
          draft.id,
          songId,
          ChartVariantKind.visual.name,
          draft.createdAt.toIso8601String(),
          draft.updatedAt.toIso8601String(),
        ]);
      }
    } finally {
      songStatement.close();
      variantStatement.close();
    }
  }

  static void _migrateToVersion3(Database database) {
    database.execute('''
      CREATE TABLE setlists (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        scheduled_at TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    database.execute('''
      CREATE TABLE setlist_entries (
        id TEXT PRIMARY KEY NOT NULL,
        setlist_id TEXT NOT NULL
          REFERENCES setlists(id) ON DELETE CASCADE,
        chart_variant_id TEXT NOT NULL
          REFERENCES chart_variants(id) ON DELETE RESTRICT,
        position INTEGER NOT NULL CHECK(position >= 0),
        UNIQUE(setlist_id, position)
      );
    ''');
    database.execute('''
      CREATE INDEX setlist_entries_setlist_id_index
      ON setlist_entries(setlist_id, position);
    ''');
    database.execute('''
      CREATE INDEX setlist_entries_chart_variant_id_index
      ON setlist_entries(chart_variant_id);
    ''');
  }

  Future<StoredAsset> storeAsset(List<int> bytes, String extension) async {
    final normalizedExtension = extension.toLowerCase().replaceFirst('.', '');
    final hash = sha256.convert(bytes).toString();
    final file = File(
      p.join(assetsDirectory.path, '$hash.$normalizedExtension'),
    );
    if (!await file.exists()) {
      final temporary = File('${file.path}.partial');
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
    }
    return StoredAsset(
      hash: hash,
      extension: normalizedExtension,
      path: file.path,
    );
  }

  @override
  String assetPath(String hash, String extension) {
    return p.join(assetsDirectory.path, '$hash.$extension');
  }

  @override
  Future<void> saveDraft(VisualChartDraft draft) async {
    final existing = _database.select(
      'SELECT song_id FROM chart_variants WHERE id = ? LIMIT 1;',
      [draft.id],
    );
    final songId = existing.isEmpty
        ? _legacySongId(draft.id)
        : existing.single['song_id'] as String;
    await saveDraftAsVariant(draft, songId: songId);
  }

  @override
  Future<void> saveDraftAsVariant(
    VisualChartDraft draft, {
    required String songId,
  }) async {
    _inTransaction(() {
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
          id, song_id, kind, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          updated_at = excluded.updated_at;
      ''',
        [
          draft.id,
          songId,
          ChartVariantKind.visual.name,
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
    });
  }

  @override
  Future<void> deleteDraft(String id) async {
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
        throw ChartVariantReferencedBySetlistsException(
          chartVariantId: id,
          setlistIds: references
              .map((row) => row['setlist_id'] as String)
              .toList(growable: false),
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
      SELECT id, song_id, kind, created_at, updated_at
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
      SELECT id, song_id, kind, created_at, updated_at
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
      kind: ChartVariantKind.values.byName(row['kind'] as String),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  @override
  Future<void> saveSetlist(LibrarySetlist setlist) async {
    _validateSetlistEntryIds(setlist.entries);
    _inTransaction(() {
      _requireChartVariants(
        setlist.entries.map((entry) => entry.chartVariantId),
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
          id, setlist_id, chart_variant_id, position
        ) VALUES (?, ?, ?, ?);
      ''');
      try {
        for (var index = 0; index < setlist.entries.length; index++) {
          final entry = setlist.entries[index];
          statement.execute([
            entry.id,
            setlist.id,
            entry.chartVariantId,
            index,
          ]);
        }
      } finally {
        statement.close();
      }
    });
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
      SELECT id, chart_variant_id
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
          .map(
            (entry) => LibrarySetlistEntry(
              id: entry['id'] as String,
              chartVariantId: entry['chart_variant_id'] as String,
            ),
          )
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

  static void _validateSetlistEntryIds(List<LibrarySetlistEntry> entries) {
    final ids = entries.map((entry) => entry.id).toList(growable: false);
    if (ids.toSet().length != ids.length) {
      throw ArgumentError.value(
        ids,
        'setlist.entries',
        'Entry IDs must be unique.',
      );
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

  static String _legacySongId(String draftId) => 'song_$draftId';

  void close() => _database.close();
}
