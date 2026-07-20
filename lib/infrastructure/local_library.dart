import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../domain/visual_chart_models.dart';
import '../application/service_contracts.dart';

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

class LocalLibrary implements ChartLibrary {
  LocalLibrary._(this.root, this.assetsDirectory, this._database);

  final Directory root;
  final Directory assetsDirectory;
  final Database _database;

  static Future<LocalLibrary> open() async {
    final support = await getApplicationSupportDirectory();
    final root = Directory(p.join(support.path, 'Music Tabbler'));
    final assets = Directory(p.join(root.path, 'assets'));
    await assets.create(recursive: true);
    final database = sqlite3.open(p.join(root.path, 'library.sqlite'));
    database.execute('''
      CREATE TABLE IF NOT EXISTS visual_charts (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        payload_json TEXT NOT NULL
      );
    ''');
    return LocalLibrary._(root, assets, database);
  }

  static Future<LocalLibrary> forTesting(Directory root) async {
    final assets = Directory(p.join(root.path, 'assets'));
    await assets.create(recursive: true);
    final database = sqlite3.openInMemory();
    database.execute('''
      CREATE TABLE visual_charts (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        payload_json TEXT NOT NULL
      );
    ''');
    return LocalLibrary._(root, assets, database);
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

  void close() => _database.close();
}
