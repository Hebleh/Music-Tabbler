import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';
import 'package:music_tabbler/infrastructure/local_library.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('library deduplicates assets and reloads saved visual drafts', () async {
    final directory = await Directory.systemTemp.createTemp(
      'music_tabbler_library_',
    );
    final library = await LocalLibrary.forTesting(directory);
    addTearDown(() {
      library.close();
      directory.deleteSync(recursive: true);
    });

    final first = await library.storeAsset([1, 2, 3], 'png');
    final second = await library.storeAsset([1, 2, 3], '.png');
    final now = DateTime.utc(2026, 7, 20);
    final draft = VisualChartDraft(
      id: 'chart',
      title: 'Saved chart',
      artist: 'Band',
      createdAt: now,
      updatedAt: now,
      strips: [
        VisualStrip(
          id: 'strip',
          assetHash: first.hash,
          assetExtension: first.extension,
          pixelWidth: 100,
          pixelHeight: 40,
        ),
      ],
    );

    await library.saveDraft(draft);
    final loaded = await library.listDrafts();

    expect(first.path, second.path);
    expect(File(first.path).existsSync(), isTrue);
    expect(loaded.single.title, 'Saved chart');
    expect(loaded.single.strips.single.assetHash, first.hash);
    final songs = await library.listSongs();
    final identity = await library.identityForDraft(draft.id);
    expect(songs.single.id, 'song_chart');
    expect(identity?.id, draft.id);
    expect(identity?.songId, songs.single.id);

    await library.deleteDraft(draft.id);
    expect(await library.listDrafts(), isEmpty);
    expect(await library.listSongs(), isEmpty);
    expect(File(first.path).existsSync(), isTrue);
  });

  test('fresh schema supports multiple stable variants for one song', () async {
    final directory = await Directory.systemTemp.createTemp(
      'music_tabbler_variants_',
    );
    final library = await LocalLibrary.forTesting(directory);
    addTearDown(() {
      library.close();
      directory.deleteSync(recursive: true);
    });

    final first = _draft(id: 'first', title: 'Song');
    final second = _draft(id: 'second', title: 'Song');
    await library.saveDraft(first);
    final songId = (await library.identityForDraft(first.id))!.songId;
    await library.saveDraftAsVariant(second, songId: songId);

    expect(await library.listSongs(), hasLength(1));
    expect(await library.listVariants(songId), hasLength(2));
    expect((await library.identityForDraft(second.id))?.songId, songId);

    await library.deleteDraft(first.id);
    expect(await library.listSongs(), hasLength(1));
    await library.deleteDraft(second.id);
    expect(await library.listSongs(), isEmpty);
  });

  test('new song and variant identities survive persistent reopen', () async {
    final directory = await Directory.systemTemp.createTemp(
      'music_tabbler_stable_identity_',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final draft = _draft(id: 'persistent', title: 'Persistent chart');

    var library = await LocalLibrary.forTesting(directory, inMemory: false);
    await library.saveDraft(draft);
    final before = await library.identityForDraft(draft.id);
    library.close();

    library = await LocalLibrary.forTesting(directory, inMemory: false);
    final after = await library.identityForDraft(draft.id);
    expect(after?.id, before?.id);
    expect(after?.songId, before?.songId);
    expect((await library.loadDraft(draft.id))?.encode(), draft.encode());
    library.close();
  });

  test('migrates a v0.1.0 library without changing drafts or assets', () async {
    final directory = await Directory.systemTemp.createTemp(
      'music_tabbler_migration_',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final draft = _draft(
      id: 'legacy',
      title: 'Legacy chart',
      assetHash: sha256.convert([1, 2, 3, 4]).toString(),
    );
    final asset = await _createLegacyLibrary(directory, draft);
    final originalAssetBytes = await asset.readAsBytes();

    var library = await LocalLibrary.forTesting(directory, inMemory: false);
    expect((await library.loadDraft(draft.id))?.encode(), draft.encode());
    expect((await library.listSongs()).single.id, 'song_legacy');
    expect((await library.identityForDraft(draft.id))?.songId, 'song_legacy');
    expect(await asset.readAsBytes(), originalAssetBytes);
    final edited = draft.copyWith(
      title: 'Edited after migration',
      updatedAt: draft.updatedAt.add(const Duration(minutes: 1)),
    );
    await library.saveDraft(edited);
    library.close();

    library = await LocalLibrary.forTesting(directory, inMemory: false);
    expect(await library.listSongs(), hasLength(1));
    expect(await library.listVariants('song_legacy'), hasLength(1));
    expect(
      (await library.loadDraft(draft.id))?.title,
      'Edited after migration',
    );
    expect((await library.identityForDraft(draft.id))?.songId, 'song_legacy');
    expect(await asset.readAsBytes(), originalAssetBytes);
    library.close();

    final database = sqlite3.open(p.join(directory.path, 'library.sqlite'));
    addTearDown(database.close);
    expect(
      database.select('PRAGMA user_version;').single['user_version'],
      LocalLibrary.currentSchemaVersion,
    );
    expect(
      database.select('SELECT COUNT(*) AS count FROM songs;').single['count'],
      1,
    );
    expect(
      database
          .select('SELECT COUNT(*) AS count FROM chart_variants;')
          .single['count'],
      1,
    );
  });

  test(
    'failed migration rolls back its schema step and preserves legacy data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'music_tabbler_failed_migration_',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final draft = _draft(
        id: 'legacy',
        title: 'Legacy chart',
        assetHash: sha256.convert([1, 2, 3, 4]).toString(),
      );
      final asset = await _createLegacyLibrary(directory, draft);
      final path = p.join(directory.path, 'library.sqlite');
      final incompatible = sqlite3.open(path);
      incompatible.execute('CREATE TABLE songs (unexpected TEXT NOT NULL);');
      incompatible.close();

      await expectLater(
        LocalLibrary.forTesting(directory, inMemory: false),
        throwsA(isA<SqliteException>()),
      );

      final database = sqlite3.open(path);
      addTearDown(database.close);
      expect(database.select('PRAGMA user_version;').single['user_version'], 1);
      expect(
        database
            .select('SELECT COUNT(*) AS count FROM visual_charts;')
            .single['count'],
        1,
      );
      expect(
        database.select(
          "SELECT name FROM sqlite_master WHERE name = 'chart_variants';",
        ),
        isEmpty,
      );
      expect(await asset.readAsBytes(), [1, 2, 3, 4]);
    },
  );

  test('newer library schema is rejected without modification', () async {
    final directory = await Directory.systemTemp.createTemp(
      'music_tabbler_future_schema_',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = p.join(directory.path, 'library.sqlite');
    final database = sqlite3.open(path);
    database.execute(
      'PRAGMA user_version = ${LocalLibrary.currentSchemaVersion + 1};',
    );
    database.close();

    await expectLater(
      LocalLibrary.forTesting(directory, inMemory: false),
      throwsA(isA<StateError>()),
    );

    final reopened = sqlite3.open(path);
    addTearDown(reopened.close);
    expect(
      reopened.select('PRAGMA user_version;').single['user_version'],
      LocalLibrary.currentSchemaVersion + 1,
    );
  });
}

VisualChartDraft _draft({
  required String id,
  required String title,
  String? assetHash,
}) {
  final createdAt = DateTime.utc(2026, 7, 20, 10);
  return VisualChartDraft(
    id: id,
    title: title,
    artist: 'Band',
    createdAt: createdAt,
    updatedAt: createdAt.add(const Duration(hours: 1)),
    strips: assetHash == null
        ? const []
        : [
            VisualStrip(
              id: 'strip_$id',
              assetHash: assetHash,
              assetExtension: 'png',
              pixelWidth: 100,
              pixelHeight: 40,
            ),
          ],
  );
}

Future<File> _createLegacyLibrary(
  Directory root,
  VisualChartDraft draft,
) async {
  final assets = Directory(p.join(root.path, 'assets'));
  await assets.create(recursive: true);
  final strip = draft.strips.single;
  final asset = File(
    p.join(assets.path, '${strip.assetHash}.${strip.assetExtension}'),
  );
  await asset.writeAsBytes([1, 2, 3, 4], flush: true);

  final database = sqlite3.open(p.join(root.path, 'library.sqlite'));
  database.execute('''
    CREATE TABLE visual_charts (
      id TEXT PRIMARY KEY NOT NULL,
      title TEXT NOT NULL,
      artist TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      payload_json TEXT NOT NULL
    );
  ''');
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
  database.close();
  return asset;
}
