import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/application/portable_container.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';
import 'package:music_tabbler/infrastructure/local_library.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  test(
    'v5 semantic retirement is backed up, removed, and setlist-safe',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'music_tabbler_semantic_retirement_',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      _createVersion5Library(root);

      var library = await LocalLibrary.forTesting(root, inMemory: false);
      expect(await library.listDrafts(), hasLength(1));
      final setlist = (await library.listSetlists()).single;
      expect(setlist.entries, hasLength(2));
      expect(setlist.entries.first.chartVariantId, 'visual-chart');
      expect(setlist.entries.last.placeholderTitle, 'Semantic only');
      library.close();

      final database = sqlite3.open(p.join(root.path, 'library.sqlite'));
      expect(
        database.select('PRAGMA user_version;').single['user_version'],
        LocalLibrary.currentSchemaVersion,
      );
      expect(
        database.select(
          "SELECT name FROM sqlite_master WHERE name = 'semantic_charts';",
        ),
        isEmpty,
      );
      final variantColumns = database.select(
        "PRAGMA table_info('chart_variants');",
      );
      expect(variantColumns.map((row) => row['name']), isNot(contains('kind')));
      expect(
        database
            .select('SELECT COUNT(*) AS count FROM chart_variants;')
            .single['count'],
        1,
      );
      database.close();

      final retirementDirectory = Directory(
        p.join(root.path, 'backups', 'retired-semantic'),
      );
      final backups = retirementDirectory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.mtstate'))
          .toList();
      expect(backups, hasLength(1));
      final decoded = const PortableContainerCodec().decode(
        backups.single.readAsBytesSync(),
        expectedKind: 'music-tabbler-state',
      );
      expect(decoded.schemaVersion, 2);
      expect(decoded.metadata['semanticVariants'], hasLength(1));
      expect(decoded.file('semantic/0.json').bytes, isNotEmpty);

      library = await LocalLibrary.forTesting(root, inMemory: false);
      library.close();
      expect(
        retirementDirectory.listSync().whereType<File>().where(
          (file) => file.path.endsWith('.mtstate'),
        ),
        hasLength(1),
      );
    },
  );

  test('failed retirement backup leaves the v5 database untouched', () async {
    final root = await Directory.systemTemp.createTemp(
      'music_tabbler_semantic_retirement_failure_',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    _createVersion5Library(root);
    File(p.join(root.path, 'backups')).writeAsStringSync('not a directory');

    await expectLater(
      LocalLibrary.forTesting(root, inMemory: false),
      throwsA(isA<FileSystemException>()),
    );

    final database = sqlite3.open(p.join(root.path, 'library.sqlite'));
    addTearDown(database.close);
    expect(database.select('PRAGMA user_version;').single['user_version'], 5);
    expect(
      database
          .select('SELECT COUNT(*) AS count FROM semantic_charts;')
          .single['count'],
      1,
    );
    expect(
      database
          .select(
            "SELECT COUNT(*) AS count FROM chart_variants WHERE kind = 'semantic';",
          )
          .single['count'],
      1,
    );
  });
}

void _createVersion5Library(Directory root) {
  Directory(p.join(root.path, 'assets')).createSync(recursive: true);
  final database = sqlite3.open(p.join(root.path, 'library.sqlite'));
  final now = DateTime.utc(2026, 8, 11);
  final visual = VisualChartDraft(
    id: 'visual-chart',
    title: 'Visual chart',
    artist: 'Band',
    createdAt: now,
    updatedAt: now,
  );
  database.execute('''
    CREATE TABLE visual_charts (
      id TEXT PRIMARY KEY NOT NULL,
      title TEXT NOT NULL,
      artist TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      payload_json TEXT NOT NULL
    );
    CREATE TABLE songs (
      id TEXT PRIMARY KEY NOT NULL,
      title TEXT NOT NULL,
      artist TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    CREATE TABLE chart_variants (
      id TEXT PRIMARY KEY NOT NULL,
      song_id TEXT NOT NULL REFERENCES songs(id) ON DELETE CASCADE,
      kind TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    CREATE INDEX chart_variants_song_id_index ON chart_variants(song_id);
    CREATE TABLE semantic_charts (
      id TEXT PRIMARY KEY NOT NULL REFERENCES chart_variants(id) ON DELETE CASCADE,
      payload_json TEXT NOT NULL
    );
    CREATE TABLE setlists (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL,
      scheduled_at TEXT,
      notes TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    CREATE TABLE setlist_entries (
      id TEXT PRIMARY KEY NOT NULL,
      setlist_id TEXT NOT NULL REFERENCES setlists(id) ON DELETE CASCADE,
      entry_kind TEXT NOT NULL CHECK(entry_kind IN ('chart', 'placeholder')),
      chart_variant_id TEXT REFERENCES chart_variants(id) ON DELETE RESTRICT,
      placeholder_title TEXT,
      position INTEGER NOT NULL CHECK(position >= 0),
      UNIQUE(setlist_id, position),
      CHECK(
        (entry_kind = 'chart' AND chart_variant_id IS NOT NULL AND placeholder_title IS NULL)
        OR
        (entry_kind = 'placeholder' AND chart_variant_id IS NULL
          AND placeholder_title IS NOT NULL AND length(trim(placeholder_title)) > 0)
      )
    );
  ''');
  for (final song in [
    ('visual-song', 'Visual chart'),
    ('semantic-song', 'Semantic only'),
  ]) {
    database.execute('INSERT INTO songs VALUES (?, ?, ?, ?, ?);', [
      song.$1,
      song.$2,
      'Band',
      now.toIso8601String(),
      now.toIso8601String(),
    ]);
  }
  database.execute('INSERT INTO chart_variants VALUES (?, ?, ?, ?, ?);', [
    'visual-chart',
    'visual-song',
    'visual',
    now.toIso8601String(),
    now.toIso8601String(),
  ]);
  database.execute('INSERT INTO chart_variants VALUES (?, ?, ?, ?, ?);', [
    'semantic-chart',
    'semantic-song',
    'semantic',
    now.toIso8601String(),
    now.toIso8601String(),
  ]);
  database.execute('INSERT INTO visual_charts VALUES (?, ?, ?, ?, ?);', [
    visual.id,
    visual.title,
    visual.artist,
    now.toIso8601String(),
    visual.encode(),
  ]);
  database.execute('INSERT INTO semantic_charts VALUES (?, ?);', [
    'semantic-chart',
    jsonEncode({'id': 'semantic-chart', 'legacy': true}),
  ]);
  database.execute('INSERT INTO setlists VALUES (?, ?, ?, ?, ?, ?);', [
    'set',
    'Gig',
    null,
    null,
    now.toIso8601String(),
    now.toIso8601String(),
  ]);
  database.execute('INSERT INTO setlist_entries VALUES (?, ?, ?, ?, ?, ?);', [
    'visual-entry',
    'set',
    'chart',
    'visual-chart',
    null,
    0,
  ]);
  database.execute('INSERT INTO setlist_entries VALUES (?, ?, ?, ?, ?, ?);', [
    'semantic-entry',
    'set',
    'chart',
    'semantic-chart',
    null,
    1,
  ]);
  database.execute('PRAGMA user_version = 5;');
  database.close();
}
