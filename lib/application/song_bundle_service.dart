import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../domain/visual_chart_models.dart';
import '../infrastructure/local_library.dart';
import 'portable_container.dart';
import 'service_contracts.dart';

class SongBundleService implements SongBundleTransfer {
  SongBundleService(
    this.library, {
    this.codec = const PortableContainerCodec(),
  });

  static const kind = 'music-tabbler-song';
  static const schemaVersion = 1;

  final LocalLibrary library;
  final PortableContainerCodec codec;

  @override
  Future<Uint8List> exportSongBytes(String chartVariantId) async {
    final identity = await library.identityForDraft(chartVariantId);
    if (identity == null) {
      throw StateError('Chart variant $chartVariantId does not exist.');
    }
    final songs = await library.listSongs();
    final song = songs.singleWhere((song) => song.id == identity.songId);
    final variants = await library.listVariants(identity.songId);
    final files = <PortableContainerFile>[];
    final metadataVariants = <Map<String, Object?>>[];
    final assets = <String>{};
    for (var index = 0; index < variants.length; index++) {
      final variant = variants[index];
      final draft = await library.loadDraft(variant.id);
      if (draft == null) {
        throw StateError('Chart variant ${variant.id} has no visual payload.');
      }
      final draftPath = 'variants/$index.json';
      files.add(
        PortableContainerFile(
          path: draftPath,
          bytes: Uint8List.fromList(utf8.encode(draft.encode())),
        ),
      );
      metadataVariants.add({
        'id': variant.id,
        'kind': variant.kind.name,
        'createdAt': variant.createdAt.toIso8601String(),
        'updatedAt': variant.updatedAt.toIso8601String(),
        'draftPath': draftPath,
      });
      for (final strip in draft.allReferencedStrips) {
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
    final orderedAssets = assets.toList()..sort();
    for (final assetName in orderedAssets) {
      final file = File(p.join(library.assetsDirectory.path, assetName));
      if (!await file.exists()) {
        throw StateError('Chart asset is missing: $assetName.');
      }
      files.add(
        PortableContainerFile(
          path: 'assets/$assetName',
          bytes: await file.readAsBytes(),
        ),
      );
    }
    return codec.encode(
      kind: kind,
      schemaVersion: schemaVersion,
      metadata: {
        'song': {
          'id': song.id,
          'title': song.title,
          'artist': song.artist,
          'createdAt': song.createdAt.toIso8601String(),
          'updatedAt': song.updatedAt.toIso8601String(),
        },
        'variants': metadataVariants,
      },
      files: files,
    );
  }

  @override
  Future<SongBundleImportResult> importSongBytes(Uint8List bytes) async {
    final container = codec.decode(bytes, expectedKind: kind);
    if (container.schemaVersion != schemaVersion) {
      throw PortableContainerException(
        'Unsupported .mtsong schema ${container.schemaVersion}.',
      );
    }
    final songJson = _map(container.metadata['song'], 'song');
    final variantsJson = container.metadata['variants'];
    if (variantsJson is! List || variantsJson.isEmpty) {
      throw const PortableContainerException(
        'Song bundle contains no chart variants.',
      );
    }
    final importedSongId = _string(songJson['id'], 'song.id');
    final importedTitle = _string(songJson['title'], 'song.title');
    final importedArtistValue = songJson['artist'];
    if (importedArtistValue is! String) {
      throw const PortableContainerException(
        'Song bundle song.artist is invalid.',
      );
    }
    final importedArtist = importedArtistValue;
    var targetSongId = importedSongId;
    final localSongs = await library.listSongs();
    final localSong = localSongs
        .where((song) => song.id == importedSongId)
        .firstOrNull;
    if (localSong != null &&
        (localSong.title != importedTitle ||
            localSong.artist != importedArtist)) {
      targetSongId = IdFactory.next('song');
    }

    final staged = <({VisualChartDraft draft, String songId})>[];
    final seenVariantIds = <String>{};
    final assetFiles = <String, PortableContainerFile>{};
    for (final file in container.files) {
      if (file.path.startsWith('assets/')) {
        final name = file.path.substring('assets/'.length);
        if (!RegExp(r'^[0-9a-f]{64}\.[a-z0-9]+$').hasMatch(name)) {
          throw PortableContainerException(
            'Song bundle asset name is invalid: $name.',
          );
        }
        final expectedHash = name.substring(0, 64);
        if (sha256.convert(file.bytes).toString() != expectedHash) {
          throw PortableContainerException(
            'Song bundle asset hash is invalid: $name.',
          );
        }
        assetFiles[name] = file;
      }
    }
    final consumedPaths = <String>{
      for (final file in assetFiles.values) file.path,
    };
    for (final rawVariant in variantsJson) {
      final variant = _map(rawVariant, 'variant');
      final originalId = _string(variant['id'], 'variant.id');
      if (!seenVariantIds.add(originalId)) {
        throw PortableContainerException(
          'Song bundle declares variant more than once: $originalId.',
        );
      }
      final draftPath = _string(variant['draftPath'], 'variant.draftPath');
      consumedPaths.add(draftPath);
      late final VisualChartDraft imported;
      try {
        imported = VisualChartDraft.decode(
          utf8.decode(container.file(draftPath).bytes),
        );
      } catch (_) {
        throw PortableContainerException(
          'Song bundle variant is invalid: $originalId.',
        );
      }
      if (imported.id != originalId) {
        throw PortableContainerException(
          'Song bundle variant identity does not match: $originalId.',
        );
      }
      for (final strip in imported.allReferencedStrips) {
        final assetName = '${strip.assetHash}.${strip.assetExtension}';
        if (!assetFiles.containsKey(assetName)) {
          throw PortableContainerException(
            'Song bundle is missing chart asset: $assetName.',
          );
        }
      }
      final existing = await library.loadDraft(originalId);
      final targetId = existing == null ? originalId : IdFactory.next('chart');
      staged.add((
        draft: targetId == originalId
            ? imported
            : imported.copyWith(id: targetId),
        songId: targetSongId,
      ));
    }
    if (container.files.any((file) => !consumedPaths.contains(file.path))) {
      throw const PortableContainerException(
        'Song bundle contains an unexpected file.',
      );
    }
    for (final entry in assetFiles.entries) {
      final extension = p.extension(entry.key).substring(1);
      final stored = await library.storeAsset(entry.value.bytes, extension);
      if ('${stored.hash}.${stored.extension}' != entry.key) {
        throw PortableContainerException(
          'Song bundle asset could not be installed safely: ${entry.key}.',
        );
      }
    }
    await library.saveDraftVariantsAtomically(staged);
    return SongBundleImportResult(
      importedVariantIds: List.unmodifiable(
        staged.map((variant) => variant.draft.id),
      ),
      skippedVariantIds: const [],
    );
  }

  @override
  Future<String?> exportSongWithPicker(String chartVariantId) async {
    final draft = await library.loadDraft(chartVariantId);
    if (draft == null) return null;
    final safeName = draft.title.trim().isEmpty
        ? 'music-tabbler-song'
        : draft.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final bytes = await exportSongBytes(chartVariantId);
    return FilePicker.platform.saveFile(
      dialogTitle: 'Export portable song',
      fileName: '$safeName.mtsong',
      type: FileType.custom,
      allowedExtensions: const ['mtsong'],
      bytes: bytes,
    );
  }

  @override
  Future<SongBundleImportResult?> importSongWithPicker() async {
    final selected = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mtsong'],
      withData: true,
    );
    if (selected == null) return null;
    final file = selected.files.single;
    final bytes = file.bytes ?? await file.xFile.readAsBytes();
    return importSongBytes(bytes);
  }

  Map<String, Object?> _map(Object? value, String name) {
    if (value is! Map) {
      throw PortableContainerException('Song bundle $name is invalid.');
    }
    return value.cast<String, Object?>();
  }

  String _string(Object? value, String name) {
    if (value is! String || value.trim().isEmpty) {
      throw PortableContainerException('Song bundle $name is invalid.');
    }
    return value;
  }
}
