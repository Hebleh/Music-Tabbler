import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../application/portable_container.dart';

/// Creates the permanent, opaque v2 state archive required before schema 6
/// retires semantic records. This deliberately does not decode semantic JSON.
Future<String?> createLegacySemanticRetirementBackup({
  required Database database,
  required Directory root,
  required Directory assetsDirectory,
  PortableContainerCodec codec = const PortableContainerCodec(),
}) async {
  final semanticRows = database.select('''
    SELECT
      chart_variants.id,
      chart_variants.song_id,
      chart_variants.updated_at,
      semantic_charts.payload_json
    FROM chart_variants
    JOIN semantic_charts ON semantic_charts.id = chart_variants.id
    WHERE chart_variants.kind = 'semantic'
    ORDER BY chart_variants.id ASC;
  ''');
  if (semanticRows.isEmpty) return null;

  final files = <PortableContainerFile>[];
  final visualVariants = <Map<String, Object?>>[];
  final semanticVariants = <Map<String, Object?>>[];
  final visualRows = database.select('''
    SELECT chart_variants.id, chart_variants.song_id, visual_charts.payload_json
    FROM chart_variants
    JOIN visual_charts ON visual_charts.id = chart_variants.id
    WHERE chart_variants.kind = 'visual'
    ORDER BY chart_variants.id ASC;
  ''');
  for (var index = 0; index < visualRows.length; index += 1) {
    final row = visualRows[index];
    final path = 'variants/$index.json';
    files.add(
      PortableContainerFile(
        path: path,
        bytes: Uint8List.fromList(
          utf8.encode(row['payload_json']! as String),
        ),
      ),
    );
    visualVariants.add({
      'id': row['id'],
      'songId': row['song_id'],
      'kind': 'visual',
      'draftPath': path,
    });
  }
  for (var index = 0; index < semanticRows.length; index += 1) {
    final row = semanticRows[index];
    final path = 'semantic/$index.json';
    files.add(
      PortableContainerFile(
        path: path,
        bytes: Uint8List.fromList(
          utf8.encode(row['payload_json']! as String),
        ),
      ),
    );
    semanticVariants.add({
      'id': row['id'],
      'songId': row['song_id'],
      'chartPath': path,
      'updatedAt': row['updated_at'],
    });
  }

  if (await assetsDirectory.exists()) {
    final assets = await assetsDirectory
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    assets.sort((left, right) => left.path.compareTo(right.path));
    for (final asset in assets) {
      files.add(
        PortableContainerFile(
          path: 'assets/${p.basename(asset.path)}',
          bytes: await asset.readAsBytes(),
        ),
      );
    }
  }

  final songs = database.select('''
    SELECT id, title, artist, created_at, updated_at
    FROM songs
    ORDER BY id ASC;
  ''');
  final setlists = database.select('''
    SELECT id, name, scheduled_at, notes, created_at, updated_at
    FROM setlists
    ORDER BY id ASC;
  ''');
  final bytes = codec.encode(
    kind: 'music-tabbler-state',
    schemaVersion: 2,
    metadata: {
      'songs': [
        for (final row in songs)
          {
            'id': row['id'],
            'title': row['title'],
            'artist': row['artist'],
            'createdAt': row['created_at'],
            'updatedAt': row['updated_at'],
          },
      ],
      'variants': visualVariants,
      'semanticVariants': semanticVariants,
      'setlists': [
        for (final row in setlists)
          {
            'id': row['id'],
            'name': row['name'],
            'scheduledAt': row['scheduled_at'],
            'notes': row['notes'],
            'createdAt': row['created_at'],
            'updatedAt': row['updated_at'],
            'entries': [
              for (final entry in database.select(
                '''
                  SELECT id, entry_kind, chart_variant_id, placeholder_title
                  FROM setlist_entries
                  WHERE setlist_id = ?
                  ORDER BY position ASC, id ASC;
                ''',
                [row['id']],
              ))
                {
                  'id': entry['id'],
                  'kind': entry['entry_kind'],
                  'chartVariantId': entry['chart_variant_id'],
                  'placeholderTitle': entry['placeholder_title'],
                },
            ],
          },
      ],
    },
    files: files,
  );
  final validated = codec.decode(
    bytes,
    expectedKind: 'music-tabbler-state',
  );
  if (validated.schemaVersion != 2 ||
      (validated.metadata['semanticVariants'] as List?)?.length !=
          semanticRows.length) {
    throw const PortableContainerException(
      'The pre-semantic-sunset backup did not validate.',
    );
  }

  final directory = Directory(
    p.join(root.path, 'backups', 'retired-semantic'),
  );
  await directory.create(recursive: true);
  final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
  final destination = File(
    p.join(directory.path, 'pre-semantic-sunset-$stamp.mtstate'),
  );
  final partial = File('${destination.path}.partial');
  try {
    await partial.writeAsBytes(bytes, flush: true);
    await partial.rename(destination.path);
  } finally {
    if (await partial.exists()) await partial.delete();
  }
  return destination.path;
}
