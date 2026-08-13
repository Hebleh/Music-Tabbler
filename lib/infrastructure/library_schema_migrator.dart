import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../domain/visual_chart_models.dart';
import 'legacy_semantic_retirement.dart';

String legacySongId(String draftId) => 'song_$draftId';

/// Owns ordered SQLite schema changes and their transaction boundary.
class LibrarySchemaMigrator {
  const LibrarySchemaMigrator._();

  static const currentVersion = 6;

  static Future<void> migrate(
    Database database, {
    required Directory root,
    required Directory assetsDirectory,
  }) async {
    var version = _schemaVersion(database);
    if (version > currentVersion) {
      throw StateError(
        'Library schema $version is newer than supported schema '
        '$currentVersion.',
      );
    }
    while (version < currentVersion) {
      final nextVersion = version + 1;
      if (nextVersion == 6) {
        await createLegacySemanticRetirementBackup(
          database: database,
          root: root,
          assetsDirectory: assetsDirectory,
        );
      }
      database.execute('BEGIN IMMEDIATE;');
      try {
        switch (nextVersion) {
          case 1:
            _toVersion1(database);
          case 2:
            _toVersion2(database);
          case 3:
            _toVersion3(database);
          case 4:
            _toVersion4(database);
          case 5:
            _toVersion5(database);
          case 6:
            _toVersion6(database);
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

  static int _schemaVersion(Database database) =>
      database.select('PRAGMA user_version;').single['user_version'] as int;

  static void _toVersion1(Database database) {
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

  static void _toVersion2(Database database) {
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
    final songs = database.prepare('''
      INSERT INTO songs (id, title, artist, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?);
    ''');
    final variants = database.prepare('''
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
        final songId = legacySongId(draft.id);
        songs.execute([
          songId,
          draft.title,
          draft.artist,
          draft.createdAt.toIso8601String(),
          draft.updatedAt.toIso8601String(),
        ]);
        variants.execute([
          draft.id,
          songId,
          'visual',
          draft.createdAt.toIso8601String(),
          draft.updatedAt.toIso8601String(),
        ]);
      }
    } finally {
      songs.close();
      variants.close();
    }
  }

  static void _toVersion3(Database database) {
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

  static void _toVersion4(Database database) {
    database.execute('''
      CREATE TABLE setlist_entries_v4 (
        id TEXT PRIMARY KEY NOT NULL,
        setlist_id TEXT NOT NULL
          REFERENCES setlists(id) ON DELETE CASCADE,
        entry_kind TEXT NOT NULL
          CHECK(entry_kind IN ('chart', 'placeholder')),
        chart_variant_id TEXT
          REFERENCES chart_variants(id) ON DELETE RESTRICT,
        placeholder_title TEXT,
        position INTEGER NOT NULL CHECK(position >= 0),
        UNIQUE(setlist_id, position),
        CHECK(
          (entry_kind = 'chart' AND chart_variant_id IS NOT NULL
            AND placeholder_title IS NULL)
          OR
          (entry_kind = 'placeholder' AND chart_variant_id IS NULL
            AND placeholder_title IS NOT NULL
            AND length(trim(placeholder_title)) > 0)
        )
      );
    ''');
    database.execute('''
      INSERT INTO setlist_entries_v4 (
        id, setlist_id, entry_kind, chart_variant_id,
        placeholder_title, position
      )
      SELECT id, setlist_id, 'chart', chart_variant_id, NULL, position
      FROM setlist_entries;
    ''');
    database.execute('DROP TABLE setlist_entries;');
    database.execute(
      'ALTER TABLE setlist_entries_v4 RENAME TO setlist_entries;',
    );
    database.execute('''
      CREATE INDEX setlist_entries_setlist_id_index
      ON setlist_entries(setlist_id, position);
    ''');
    database.execute('''
      CREATE INDEX setlist_entries_chart_variant_id_index
      ON setlist_entries(chart_variant_id);
    ''');
  }

  static void _toVersion5(Database database) {
    database.execute('''
      CREATE TABLE semantic_charts (
        id TEXT PRIMARY KEY NOT NULL
          REFERENCES chart_variants(id) ON DELETE CASCADE,
        payload_json TEXT NOT NULL
      );
    ''');
  }

  static void _toVersion6(Database database) {
    database.execute('''
      UPDATE setlist_entries
      SET
        entry_kind = 'placeholder',
        placeholder_title = COALESCE(
          (
            SELECT NULLIF(trim(songs.title), '')
            FROM chart_variants
            JOIN songs ON songs.id = chart_variants.song_id
            WHERE chart_variants.id = setlist_entries.chart_variant_id
          ),
          'Retired semantic chart'
        ),
        chart_variant_id = NULL
      WHERE chart_variant_id IN (
        SELECT id FROM chart_variants WHERE kind = 'semantic'
      );
    ''');
    database.execute("DELETE FROM chart_variants WHERE kind = 'semantic';");
    database.execute('''
      DELETE FROM songs
      WHERE NOT EXISTS (
        SELECT 1 FROM chart_variants
        WHERE chart_variants.song_id = songs.id
      );
    ''');
    database.execute('DROP TABLE semantic_charts;');
    database.execute('''
      CREATE TABLE chart_variants_v6 (
        id TEXT PRIMARY KEY NOT NULL,
        song_id TEXT NOT NULL REFERENCES songs(id) ON DELETE CASCADE,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    database.execute('''
      INSERT INTO chart_variants_v6 (id, song_id, created_at, updated_at)
      SELECT id, song_id, created_at, updated_at
      FROM chart_variants
      WHERE kind = 'visual';
    ''');
    database.execute('DROP TABLE chart_variants;');
    database.execute('ALTER TABLE chart_variants_v6 RENAME TO chart_variants;');
    database.execute('''
      CREATE INDEX chart_variants_song_id_index
      ON chart_variants(song_id);
    ''');
  }
}
