import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/domain/library_models.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';
import 'package:music_tabbler/infrastructure/local_library.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  test(
    'setlist CRUD preserves ordered duplicate variant references across reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'music_tabbler_setlists_',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final first = _draft('variant-a');
      final second = _draft('variant-b');
      final createdAt = DateTime.utc(2026, 7, 23, 9);
      final scheduledAt = DateTime.utc(2026, 8, 16, 11);

      var library = await LocalLibrary.forTesting(directory, inMemory: false);
      await library.saveDraft(first);
      await library.saveDraft(second);
      await library.saveSetlist(
        LibrarySetlist(
          id: 'setlist-gig',
          name: 'August gig',
          scheduledAt: scheduledAt,
          notes: 'Bring the five-string.',
          createdAt: createdAt,
          updatedAt: createdAt,
          entries: const [
            LibrarySetlistEntry(id: 'entry-1', chartVariantId: 'variant-a'),
            LibrarySetlistEntry(id: 'entry-2', chartVariantId: 'variant-b'),
            LibrarySetlistEntry(id: 'entry-3', chartVariantId: 'variant-a'),
          ],
        ),
      );
      library.close();

      library = await LocalLibrary.forTesting(directory, inMemory: false);
      final loaded = (await library.listSetlists()).single;
      expect(loaded.id, 'setlist-gig');
      expect(loaded.name, 'August gig');
      expect(loaded.scheduledAt, scheduledAt);
      expect(loaded.notes, 'Bring the five-string.');
      expect(loaded.createdAt, createdAt);
      expect(loaded.entries.map((entry) => entry.id), [
        'entry-1',
        'entry-2',
        'entry-3',
      ]);
      expect(loaded.entries.map((entry) => entry.chartVariantId), [
        'variant-a',
        'variant-b',
        'variant-a',
      ]);

      final editedAt = createdAt.add(const Duration(hours: 1));
      await library.saveSetlist(
        LibrarySetlist(
          id: loaded.id,
          name: 'August gig - revised',
          scheduledAt: loaded.scheduledAt,
          createdAt: createdAt.add(const Duration(days: 1)),
          updatedAt: editedAt,
          entries: loaded.entries,
        ),
      );
      final edited = await library.loadSetlist(loaded.id);
      expect(edited?.name, 'August gig - revised');
      expect(edited?.notes, isNull);
      expect(edited?.createdAt, createdAt);
      expect(edited?.updatedAt, editedAt);

      await library.deleteSetlist(loaded.id);
      expect(await library.loadSetlist(loaded.id), isNull);
      expect(await library.listDrafts(), hasLength(2));
      library.close();
    },
  );

  test('reorder persists stable entry identities and exact order', () async {
    final directory = await Directory.systemTemp.createTemp(
      'music_tabbler_setlist_reorder_',
    );
    final library = await LocalLibrary.forTesting(directory);
    addTearDown(() {
      library.close();
      directory.deleteSync(recursive: true);
    });
    await library.saveDraft(_draft('variant-a'));
    await library.saveDraft(_draft('variant-b'));
    final originalTime = DateTime.utc(2026, 7, 23, 9);
    final reorderedAt = originalTime.add(const Duration(minutes: 5));
    await library.saveSetlist(
      _setlist(
        entries: const [
          LibrarySetlistEntry(id: 'entry-a', chartVariantId: 'variant-a'),
          LibrarySetlistEntry(id: 'entry-b', chartVariantId: 'variant-b'),
          LibrarySetlistEntry(id: 'entry-c', chartVariantId: 'variant-a'),
        ],
        updatedAt: originalTime,
      ),
    );

    await library.reorderSetlistEntries('setlist', [
      'entry-c',
      'entry-a',
      'entry-b',
    ], updatedAt: reorderedAt);

    final reordered = await library.loadSetlist('setlist');
    expect(reordered?.entries.map((entry) => entry.id), [
      'entry-c',
      'entry-a',
      'entry-b',
    ]);
    expect(reordered?.entries.map((entry) => entry.chartVariantId), [
      'variant-a',
      'variant-a',
      'variant-b',
    ]);
    expect(reordered?.updatedAt, reorderedAt);
  });

  test(
    'invalid reorder rolls back without changing order or timestamp',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'music_tabbler_setlist_bad_reorder_',
      );
      final library = await LocalLibrary.forTesting(directory);
      addTearDown(() {
        library.close();
        directory.deleteSync(recursive: true);
      });
      await library.saveDraft(_draft('variant-a'));
      final original = _setlist(
        entries: const [
          LibrarySetlistEntry(id: 'entry-a', chartVariantId: 'variant-a'),
          LibrarySetlistEntry(id: 'entry-b', chartVariantId: 'variant-a'),
        ],
      );
      await library.saveSetlist(original);

      await expectLater(
        library.reorderSetlistEntries(original.id, [
          'entry-b',
        ], updatedAt: original.updatedAt.add(const Duration(hours: 1))),
        throwsArgumentError,
      );

      final unchanged = await library.loadSetlist(original.id);
      expect(unchanged?.entries.map((entry) => entry.id), [
        'entry-a',
        'entry-b',
      ]);
      expect(unchanged?.updatedAt, original.updatedAt);
    },
  );

  test('missing chart variants reject the whole setlist save', () async {
    final directory = await Directory.systemTemp.createTemp(
      'music_tabbler_setlist_missing_variant_',
    );
    final library = await LocalLibrary.forTesting(directory);
    addTearDown(() {
      library.close();
      directory.deleteSync(recursive: true);
    });
    await library.saveDraft(_draft('variant-a'));
    final original = _setlist(
      entries: const [
        LibrarySetlistEntry(id: 'entry-a', chartVariantId: 'variant-a'),
      ],
    );
    await library.saveSetlist(original);

    await expectLater(
      library.saveSetlist(
        LibrarySetlist(
          id: original.id,
          name: 'Should roll back',
          createdAt: original.createdAt,
          updatedAt: original.updatedAt.add(const Duration(hours: 1)),
          entries: const [
            LibrarySetlistEntry(
              id: 'entry-missing',
              chartVariantId: 'variant-missing',
            ),
          ],
        ),
      ),
      throwsA(
        isA<MissingChartVariantReferencesException>().having(
          (error) => error.chartVariantIds,
          'missing variant IDs',
          ['variant-missing'],
        ),
      ),
    );

    final unchanged = await library.loadSetlist(original.id);
    expect(unchanged?.name, original.name);
    expect(unchanged?.entries.single.id, 'entry-a');
  });

  test('entry identity conflicts across setlists roll back the save', () async {
    final directory = await Directory.systemTemp.createTemp(
      'music_tabbler_setlist_entry_conflict_',
    );
    final library = await LocalLibrary.forTesting(directory);
    addTearDown(() {
      library.close();
      directory.deleteSync(recursive: true);
    });
    await library.saveDraft(_draft('variant-a'));
    final createdAt = DateTime.utc(2026, 7, 23, 9);
    await library.saveSetlist(
      LibrarySetlist(
        id: 'first-setlist',
        name: 'First',
        createdAt: createdAt,
        updatedAt: createdAt,
        entries: const [
          LibrarySetlistEntry(
            id: 'shared-entry-id',
            chartVariantId: 'variant-a',
          ),
        ],
      ),
    );

    await expectLater(
      library.saveSetlist(
        LibrarySetlist(
          id: 'second-setlist',
          name: 'Second',
          createdAt: createdAt,
          updatedAt: createdAt,
          entries: const [
            LibrarySetlistEntry(
              id: 'shared-entry-id',
              chartVariantId: 'variant-a',
            ),
          ],
        ),
      ),
      throwsA(
        isA<SetlistEntryIdentityConflictException>().having(
          (error) => error.entryIds,
          'conflicting entry IDs',
          ['shared-entry-id'],
        ),
      ),
    );

    expect((await library.listSetlists()).single.id, 'first-setlist');
    expect(
      (await library.loadSetlist('first-setlist'))?.entries.single.id,
      'shared-entry-id',
    );
    expect(await library.loadSetlist('second-setlist'), isNull);
  });

  test('variant deletion is blocked by every referencing setlist', () async {
    final directory = await Directory.systemTemp.createTemp(
      'music_tabbler_setlist_delete_guard_',
    );
    final library = await LocalLibrary.forTesting(directory);
    addTearDown(() {
      library.close();
      directory.deleteSync(recursive: true);
    });
    await library.saveDraft(_draft('variant-a'));
    for (final id in ['setlist-b', 'setlist-a']) {
      await library.saveSetlist(
        LibrarySetlist(
          id: id,
          name: id,
          createdAt: DateTime.utc(2026, 7, 23),
          updatedAt: DateTime.utc(2026, 7, 23),
          entries: [
            LibrarySetlistEntry(id: 'entry-$id', chartVariantId: 'variant-a'),
          ],
        ),
      );
    }

    await expectLater(
      library.deleteDraft('variant-a'),
      throwsA(
        isA<ChartVariantReferencedBySetlistsException>()
            .having((error) => error.chartVariantId, 'variant ID', 'variant-a')
            .having((error) => error.setlistIds, 'referencing setlists', [
              'setlist-a',
              'setlist-b',
            ]),
      ),
    );
    expect(await library.loadDraft('variant-a'), isNotNull);
    expect(await library.listSongs(), hasLength(1));
    expect(await library.listSetlists(), hasLength(2));

    await library.deleteSetlist('setlist-a');
    await expectLater(
      library.deleteDraft('variant-a'),
      throwsA(
        isA<ChartVariantReferencedBySetlistsException>().having(
          (error) => error.setlistIds,
          'remaining referencing setlist',
          ['setlist-b'],
        ),
      ),
    );
    await library.deleteSetlist('setlist-b');
    await library.deleteDraft('variant-a');
    expect(await library.loadDraft('variant-a'), isNull);
    expect(await library.listSongs(), isEmpty);
    expect(await library.listSetlists(), isEmpty);
  });

  test(
    'schema v2 migrates to empty setlist storage without changing charts',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'music_tabbler_setlist_migration_',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final draft = _draft('variant-a');
      _createVersion2Library(directory, draft);

      final library = await LocalLibrary.forTesting(directory, inMemory: false);
      expect(await library.listSetlists(), isEmpty);
      expect((await library.loadDraft(draft.id))?.encode(), draft.encode());
      library.close();

      final reopened = await LocalLibrary.forTesting(
        directory,
        inMemory: false,
      );
      expect(await reopened.listSetlists(), isEmpty);
      expect((await reopened.loadDraft(draft.id))?.encode(), draft.encode());
      reopened.close();

      final database = sqlite3.open(p.join(directory.path, 'library.sqlite'));
      addTearDown(database.close);
      expect(
        database.select('PRAGMA user_version;').single['user_version'],
        LocalLibrary.currentSchemaVersion,
      );
      expect(
        database
            .select("SELECT name FROM sqlite_master WHERE name = 'setlists';")
            .single['name'],
        'setlists',
      );
    },
  );

  test(
    'failed schema v3 migration rolls back and preserves schema v2 data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'music_tabbler_setlist_failed_migration_',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final draft = _draft('variant-a');
      _createVersion2Library(directory, draft);
      final path = p.join(directory.path, 'library.sqlite');
      final incompatible = sqlite3.open(path);
      incompatible.execute('CREATE TABLE setlists (unexpected TEXT NOT NULL);');
      incompatible.close();

      await expectLater(
        LocalLibrary.forTesting(directory, inMemory: false),
        throwsA(isA<SqliteException>()),
      );

      final database = sqlite3.open(path);
      addTearDown(database.close);
      expect(database.select('PRAGMA user_version;').single['user_version'], 2);
      expect(
        database
            .select('SELECT COUNT(*) AS count FROM visual_charts;')
            .single['count'],
        1,
      );
      expect(
        database.select(
          "SELECT name FROM sqlite_master WHERE name = 'setlist_entries';",
        ),
        isEmpty,
      );
    },
  );
}

VisualChartDraft _draft(String id) {
  final time = DateTime.utc(2026, 7, 23, 8);
  return VisualChartDraft(
    id: id,
    title: 'Song $id',
    artist: 'Band',
    createdAt: time,
    updatedAt: time,
    strips: const [],
  );
}

LibrarySetlist _setlist({
  List<LibrarySetlistEntry> entries = const [],
  DateTime? updatedAt,
}) {
  final createdAt = DateTime.utc(2026, 7, 23, 9);
  return LibrarySetlist(
    id: 'setlist',
    name: 'Setlist',
    createdAt: createdAt,
    updatedAt: updatedAt ?? createdAt,
    entries: entries,
  );
}

void _createVersion2Library(Directory root, VisualChartDraft draft) {
  root.createSync(recursive: true);
  Directory(p.join(root.path, 'assets')).createSync(recursive: true);
  final database = sqlite3.open(p.join(root.path, 'library.sqlite'));
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
    CREATE INDEX chart_variants_song_id_index
      ON chart_variants(song_id);
  ''');
  final songId = 'song_${draft.id}';
  database.execute(
    '''
    INSERT INTO visual_charts (id, title, artist, updated_at, payload_json)
    VALUES (?, ?, ?, ?, ?);
  ''',
    [
      draft.id,
      draft.title,
      draft.artist,
      draft.updatedAt.toIso8601String(),
      draft.encode(),
    ],
  );
  database.execute(
    '''
    INSERT INTO songs (id, title, artist, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?);
  ''',
    [
      songId,
      draft.title,
      draft.artist,
      draft.createdAt.toIso8601String(),
      draft.updatedAt.toIso8601String(),
    ],
  );
  database.execute(
    '''
    INSERT INTO chart_variants (id, song_id, kind, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?);
  ''',
    [
      draft.id,
      songId,
      ChartVariantKind.visual.name,
      draft.createdAt.toIso8601String(),
      draft.updatedAt.toIso8601String(),
    ],
  );
  database.execute('PRAGMA user_version = 2;');
  database.close();
}
