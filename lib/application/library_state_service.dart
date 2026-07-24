import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../domain/library_models.dart';
import '../domain/visual_chart_models.dart';
import '../infrastructure/local_library.dart';
import 'portable_container.dart';
import 'service_contracts.dart';

class LibraryStateService implements LibraryStateTransfer {
  LibraryStateService(
    this.library, {
    this.codec = const PortableContainerCodec(),
  });

  static const kind = 'music-tabbler-state';
  static const schemaVersion = 1;
  static const backupRetention = 5;

  final LocalLibrary library;
  final PortableContainerCodec codec;

  Directory get _backupDirectory =>
      Directory(p.join(library.root.path, 'backups'));

  @override
  Future<Uint8List> exportStateBytes() async {
    final songs = await library.listSongs();
    final files = <PortableContainerFile>[];
    final variantsJson = <Map<String, Object?>>[];
    final assets = <String>{};
    var variantIndex = 0;
    for (final song in songs) {
      for (final identity in await library.listVariants(song.id)) {
        final draft = await library.loadDraft(identity.id);
        if (draft == null) {
          throw StateError('Chart variant ${identity.id} has no payload.');
        }
        final draftPath = 'variants/${variantIndex++}.json';
        files.add(
          PortableContainerFile(
            path: draftPath,
            bytes: Uint8List.fromList(utf8.encode(draft.encode())),
          ),
        );
        variantsJson.add({
          'id': identity.id,
          'songId': identity.songId,
          'kind': identity.kind.name,
          'draftPath': draftPath,
        });
        for (final strip in draft.strips) {
          assets.add('${strip.assetHash}.${strip.assetExtension}');
          final sourceHash = strip.sourceAssetHash;
          if (sourceHash != null) {
            await for (final entity in library.assetsDirectory.list()) {
              if (entity is File &&
                  p.basename(entity.path).startsWith('$sourceHash.')) {
                assets.add(p.basename(entity.path));
              }
            }
          }
        }
      }
    }
    final orderedAssets = assets.toList()..sort();
    for (final name in orderedAssets) {
      final file = File(p.join(library.assetsDirectory.path, name));
      if (!await file.exists()) {
        throw StateError('Library asset is missing: $name.');
      }
      files.add(
        PortableContainerFile(
          path: 'assets/$name',
          bytes: await file.readAsBytes(),
        ),
      );
    }
    final setlists = await library.listSetlists();
    return codec.encode(
      kind: kind,
      schemaVersion: schemaVersion,
      metadata: {
        'songs': [
          for (final song in songs)
            {
              'id': song.id,
              'title': song.title,
              'artist': song.artist,
              'createdAt': song.createdAt.toIso8601String(),
              'updatedAt': song.updatedAt.toIso8601String(),
            },
        ],
        'variants': variantsJson,
        'setlists': [for (final setlist in setlists) _setlistToJson(setlist)],
      },
      files: files,
    );
  }

  @override
  Future<LibraryStateImportResult> importStateBytes(
    Uint8List bytes, {
    required StateImportMode mode,
    bool Function()? isCancelled,
  }) async {
    final container = codec.decode(
      bytes,
      expectedKind: kind,
      isCancelled: isCancelled,
    );
    if (container.schemaVersion != schemaVersion) {
      throw PortableContainerException(
        'Unsupported .mtstate schema ${container.schemaVersion}.',
      );
    }
    final rawSongs = _list(container.metadata['songs'], 'songs');
    final rawVariants = _list(container.metadata['variants'], 'variants');
    final rawSetlists = _list(container.metadata['setlists'], 'setlists');
    final importedSongs = <String, ({String title, String artist})>{};
    for (final raw in rawSongs) {
      _checkCancelled(isCancelled);
      final song = _map(raw, 'song');
      final id = _required(song['id'], 'song.id');
      if (importedSongs.containsKey(id)) {
        throw PortableContainerException(
          'State declares song more than once: $id.',
        );
      }
      final artist = song['artist'];
      if (artist is! String) {
        throw const PortableContainerException('State song.artist is invalid.');
      }
      importedSongs[id] = (
        title: _required(song['title'], 'song.title'),
        artist: artist,
      );
    }
    final assetFiles = _validatedAssets(container.files);
    final consumedPaths = <String>{
      for (final file in assetFiles.values) file.path,
    };
    final importedDrafts =
        <String, ({VisualChartDraft draft, String songId})>{};
    for (final raw in rawVariants) {
      _checkCancelled(isCancelled);
      final variant = _map(raw, 'variant');
      final id = _required(variant['id'], 'variant.id');
      final songId = _required(variant['songId'], 'variant.songId');
      final draftPath = _required(variant['draftPath'], 'variant.draftPath');
      consumedPaths.add(draftPath);
      if (!importedSongs.containsKey(songId) ||
          importedDrafts.containsKey(id)) {
        throw PortableContainerException(
          'State variant identity is invalid: $id.',
        );
      }
      late final VisualChartDraft draft;
      try {
        draft = VisualChartDraft.decode(
          utf8.decode(container.file(draftPath).bytes),
        );
      } catch (_) {
        throw PortableContainerException('State variant is invalid: $id.');
      }
      if (draft.id != id) {
        throw PortableContainerException(
          'State variant payload identity does not match: $id.',
        );
      }
      for (final strip in draft.strips) {
        final name = '${strip.assetHash}.${strip.assetExtension}';
        if (!assetFiles.containsKey(name)) {
          throw PortableContainerException(
            'State is missing chart asset: $name.',
          );
        }
      }
      importedDrafts[id] = (draft: draft, songId: songId);
    }
    final importedSetlists = [
      for (final raw in rawSetlists) _setlistFromJson(_map(raw, 'setlist')),
    ];
    if (container.files.any((file) => !consumedPaths.contains(file.path))) {
      throw const PortableContainerException(
        'State contains an unexpected file.',
      );
    }
    final setlistIds = <String>{};
    final entryIds = <String>{};
    for (final setlist in importedSetlists) {
      if (!setlistIds.add(setlist.id)) {
        throw PortableContainerException(
          'State declares setlist more than once: ${setlist.id}.',
        );
      }
      for (final entry in setlist.entries) {
        if (!entryIds.add(entry.id)) {
          throw PortableContainerException(
            'State declares entry more than once: ${entry.id}.',
          );
        }
        final variantId = entry.chartVariantId;
        if (variantId != null && !importedDrafts.containsKey(variantId)) {
          throw PortableContainerException(
            'State setlist references missing chart: $variantId.',
          );
        }
      }
    }

    final variants = <({VisualChartDraft draft, String songId})>[];
    final setlists = <LibrarySetlist>[];
    var skipped = 0;
    if (mode == StateImportMode.replace) {
      variants.addAll(importedDrafts.values);
      setlists.addAll(importedSetlists);
    } else {
      final localSongs = {
        for (final song in await library.listSongs()) song.id: song,
      };
      final songIds = <String, String>{};
      for (final entry in importedSongs.entries) {
        final local = localSongs[entry.key];
        songIds[entry.key] =
            local == null ||
                (local.title == entry.value.title &&
                    local.artist == entry.value.artist)
            ? entry.key
            : IdFactory.next('song');
      }
      final variantIds = <String, String>{};
      for (final entry in importedDrafts.entries) {
        final local = await library.loadDraft(entry.key);
        if (local != null && local.encode() == entry.value.draft.encode()) {
          variantIds[entry.key] = entry.key;
          skipped += 1;
          continue;
        }
        final targetId = local == null ? entry.key : IdFactory.next('chart');
        variantIds[entry.key] = targetId;
        variants.add((
          draft: targetId == entry.key
              ? entry.value.draft
              : entry.value.draft.copyWith(id: targetId),
          songId: songIds[entry.value.songId]!,
        ));
      }
      final existingSetlistIds = {
        for (final setlist in await library.listSetlists()) setlist.id,
      };
      for (final imported in importedSetlists) {
        setlists.add(
          LibrarySetlist(
            id: existingSetlistIds.contains(imported.id)
                ? IdFactory.next('setlist')
                : imported.id,
            name: imported.name,
            scheduledAt: imported.scheduledAt,
            notes: imported.notes,
            createdAt: imported.createdAt,
            updatedAt: imported.updatedAt,
            entries: [
              for (final entry in imported.entries)
                if (entry.kind == SetlistEntryKind.placeholder)
                  LibrarySetlistEntry.placeholder(
                    id: IdFactory.next('entry'),
                    title: entry.placeholderTitle!,
                  )
                else
                  LibrarySetlistEntry(
                    id: IdFactory.next('entry'),
                    chartVariantId: variantIds[entry.chartVariantId]!,
                  ),
            ],
          ),
        );
      }
    }
    _checkCancelled(isCancelled);
    for (final entry in assetFiles.entries) {
      _checkCancelled(isCancelled);
      final extension = p.extension(entry.key).substring(1);
      final destination = File(
        library.assetPath(entry.key.substring(0, 64), extension),
      );
      if (await destination.exists() &&
          sha256.convert(await destination.readAsBytes()).toString() !=
              entry.key.substring(0, 64)) {
        throw PortableContainerException(
          'An installed asset is corrupt and was not replaced: ${entry.key}.',
        );
      }
    }
    String? backupPath;
    if (mode == StateImportMode.replace) {
      backupPath = await _createBackup();
    }
    final createdAssets = <File>[];
    try {
      for (final entry in assetFiles.entries) {
        _checkCancelled(isCancelled);
        final extension = p.extension(entry.key).substring(1);
        final destination = File(
          library.assetPath(entry.key.substring(0, 64), extension),
        );
        final existed = await destination.exists();
        final stored = await library.storeAsset(entry.value.bytes, extension);
        if ('${stored.hash}.${stored.extension}' != entry.key) {
          throw PortableContainerException(
            'State asset could not be installed safely: ${entry.key}.',
          );
        }
        if (!existed) createdAssets.add(destination);
      }
      await library.installLibraryStateAtomically(
        variants: variants,
        setlists: setlists,
        replace: mode == StateImportMode.replace,
      );
    } catch (_) {
      for (final file in createdAssets.reversed) {
        if (await file.exists()) await file.delete();
      }
      rethrow;
    }
    return LibraryStateImportResult(
      importedVariants: variants.length,
      skippedVariants: skipped,
      importedSetlists: setlists.length,
      backupPath: backupPath,
    );
  }

  @override
  Future<String?> exportStateWithPicker() async {
    final bytes = await exportStateBytes();
    return FilePicker.platform.saveFile(
      dialogTitle: 'Export Music Tabbler library state',
      fileName: 'music-tabbler-library.mtstate',
      type: FileType.custom,
      allowedExtensions: const ['mtstate'],
      bytes: bytes,
    );
  }

  @override
  Future<LibraryStateImportResult?> importStateWithPicker(
    StateImportMode mode,
  ) async {
    final selected = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mtstate'],
      withData: true,
    );
    if (selected == null) return null;
    final file = selected.files.single;
    return importStateBytes(
      file.bytes ?? await file.xFile.readAsBytes(),
      mode: mode,
    );
  }

  @override
  Future<List<String>> listBackups() async {
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
  Future<LibraryStateImportResult> restoreBackup(String path) async {
    final root = p.normalize(p.absolute(_backupDirectory.path));
    final target = p.normalize(p.absolute(path));
    if (!p.isWithin(root, target)) {
      throw const PortableContainerException('Backup path is outside storage.');
    }
    return importStateBytes(
      await File(target).readAsBytes(),
      mode: StateImportMode.replace,
    );
  }

  Future<String> _createBackup() async {
    await _backupDirectory.create(recursive: true);
    final bytes = await exportStateBytes();
    final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final destination = File(
      p.join(_backupDirectory.path, 'backup-$stamp.mtstate'),
    );
    final partial = File('${destination.path}.partial');
    await partial.writeAsBytes(bytes, flush: true);
    await partial.rename(destination.path);
    final backups = await listBackups();
    for (final old in backups.skip(backupRetention)) {
      final normalized = p.normalize(p.absolute(old));
      if (p.isWithin(
        p.normalize(p.absolute(_backupDirectory.path)),
        normalized,
      )) {
        await File(normalized).delete();
      }
    }
    return destination.path;
  }

  Map<String, PortableContainerFile> _validatedAssets(
    List<PortableContainerFile> files,
  ) {
    final result = <String, PortableContainerFile>{};
    for (final file in files.where((file) => file.path.startsWith('assets/'))) {
      final name = file.path.substring('assets/'.length);
      if (!RegExp(r'^[0-9a-f]{64}\.[a-z0-9]+$').hasMatch(name) ||
          sha256.convert(file.bytes).toString() != name.substring(0, 64)) {
        throw PortableContainerException('State asset is invalid: $name.');
      }
      result[name] = file;
    }
    return result;
  }

  Map<String, Object?> _setlistToJson(LibrarySetlist setlist) => {
    'id': setlist.id,
    'name': setlist.name,
    'scheduledAt': setlist.scheduledAt?.toIso8601String(),
    'notes': setlist.notes,
    'createdAt': setlist.createdAt.toIso8601String(),
    'updatedAt': setlist.updatedAt.toIso8601String(),
    'entries': [
      for (final entry in setlist.entries)
        {
          'id': entry.id,
          'kind': entry.kind.name,
          'chartVariantId': entry.chartVariantId,
          'placeholderTitle': entry.placeholderTitle,
        },
    ],
  };

  LibrarySetlist _setlistFromJson(Map<String, Object?> json) {
    final entries = _list(json['entries'], 'setlist.entries');
    return LibrarySetlist(
      id: _required(json['id'], 'setlist.id'),
      name: _required(json['name'], 'setlist.name'),
      scheduledAt: json['scheduledAt'] == null
          ? null
          : DateTime.parse(json['scheduledAt']! as String),
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(_required(json['createdAt'], 'createdAt')),
      updatedAt: DateTime.parse(_required(json['updatedAt'], 'updatedAt')),
      entries: [
        for (final raw in entries)
          () {
            final item = _map(raw, 'setlist.entry');
            final entryKind = SetlistEntryKind.values.byName(
              _required(item['kind'], 'entry.kind'),
            );
            return switch (entryKind) {
              SetlistEntryKind.chart => LibrarySetlistEntry(
                id: _required(item['id'], 'entry.id'),
                chartVariantId: _required(
                  item['chartVariantId'],
                  'entry.chartVariantId',
                ),
              ),
              SetlistEntryKind.placeholder => LibrarySetlistEntry.placeholder(
                id: _required(item['id'], 'entry.id'),
                title: _required(
                  item['placeholderTitle'],
                  'entry.placeholderTitle',
                ),
              ),
            };
          }(),
      ],
    );
  }

  List<Object?> _list(Object? value, String name) {
    if (value is! List) {
      throw PortableContainerException('State $name is invalid.');
    }
    return value;
  }

  Map<String, Object?> _map(Object? value, String name) {
    if (value is! Map) {
      throw PortableContainerException('State $name is invalid.');
    }
    return value.cast<String, Object?>();
  }

  String _required(Object? value, String name) {
    if (value is! String || value.trim().isEmpty) {
      throw PortableContainerException('State $name is invalid.');
    }
    return value;
  }

  void _checkCancelled(bool Function()? isCancelled) {
    if (isCancelled?.call() ?? false) throw const PortableContainerCancelled();
  }
}
