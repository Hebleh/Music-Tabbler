import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../application/library_contracts.dart';

/// Filesystem implementation detail for immutable SHA-256-addressed assets.
class ContentAddressedAssetStore {
  const ContentAddressedAssetStore(this.directory);

  final Directory directory;

  Future<StoredAsset> store(List<int> bytes, String extension) async {
    final normalizedExtension = extension.toLowerCase().replaceFirst('.', '');
    final hash = sha256.convert(bytes).toString();
    final file = File(p.join(directory.path, '$hash.$normalizedExtension'));
    if (!await file.exists()) {
      final temporary = File('${file.path}.partial');
      try {
        await temporary.writeAsBytes(bytes, flush: true);
        await temporary.rename(file.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    }
    return StoredAsset(
      hash: hash,
      extension: normalizedExtension,
      path: file.path,
    );
  }

  String pathFor(String hash, String extension) =>
      p.join(directory.path, '$hash.$extension');

  Future<List<String>> namesWithHash(String hash) async {
    final names = <String>[];
    await for (final entity in directory.list()) {
      if (entity is File && p.basename(entity.path).startsWith('$hash.')) {
        names.add(p.basename(entity.path));
      }
    }
    names.sort();
    return List.unmodifiable(names);
  }

  Future<Uint8List> readByName(String name) async {
    if (p.basename(name) != name || name.contains('/') || name.contains('\\')) {
      throw ArgumentError.value(name, 'name', 'Asset name must be a basename.');
    }
    return File(p.join(directory.path, name)).readAsBytes();
  }
}
