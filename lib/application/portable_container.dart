import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';

class PortableContainerLimits {
  const PortableContainerLimits({
    this.maxArchiveBytes = 128 * 1024 * 1024,
    this.maxManifestBytes = 1024 * 1024,
    this.maxFiles = 512,
    this.maxFileBytes = 64 * 1024 * 1024,
    this.maxExpandedBytes = 512 * 1024 * 1024,
    this.maxExpansionRatio = 200,
  });

  final int maxArchiveBytes;
  final int maxManifestBytes;
  final int maxFiles;
  final int maxFileBytes;
  final int maxExpandedBytes;
  final int maxExpansionRatio;
}

class PortableContainerFile {
  PortableContainerFile({required this.path, required Uint8List bytes})
    : bytes = Uint8List.fromList(bytes);

  final String path;
  final Uint8List bytes;
}

class ValidatedPortableContainer {
  ValidatedPortableContainer({
    required this.kind,
    required this.schemaVersion,
    required Map<String, Object?> metadata,
    required List<PortableContainerFile> files,
  }) : metadata = Map.unmodifiable(metadata),
       files = List.unmodifiable(files);

  final String kind;
  final int schemaVersion;
  final Map<String, Object?> metadata;
  final List<PortableContainerFile> files;

  PortableContainerFile file(String path) =>
      files.singleWhere((file) => file.path == path);
}

class PortableContainerException implements Exception {
  const PortableContainerException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PortableContainerCancelled extends PortableContainerException {
  const PortableContainerCancelled() : super('Portable container cancelled.');
}

class PortableContainerCodec {
  const PortableContainerCodec({this.limits = const PortableContainerLimits()});

  static const format = 'music-tabbler-portable';
  static const manifestPath = 'manifest.json';

  final PortableContainerLimits limits;

  Uint8List encode({
    required String kind,
    required int schemaVersion,
    Map<String, Object?> metadata = const {},
    required List<PortableContainerFile> files,
    bool Function()? isCancelled,
  }) {
    _checkCancelled(isCancelled);
    if (kind.trim().isEmpty || schemaVersion < 1) {
      throw const PortableContainerException(
        'Container kind and schema version are required.',
      );
    }
    if (files.length > limits.maxFiles) {
      throw PortableContainerException(
        'Container has more than ${limits.maxFiles} files.',
      );
    }
    final normalized = <String, PortableContainerFile>{};
    var totalBytes = 0;
    for (final file in files) {
      _checkCancelled(isCancelled);
      final path = _validatedPath(file.path);
      if (path == manifestPath) {
        throw const PortableContainerException(
          'manifest.json is reserved by the container format.',
        );
      }
      final key = path.toLowerCase();
      if (normalized.containsKey(key)) {
        throw PortableContainerException(
          'Container paths collide: ${file.path}.',
        );
      }
      if (file.bytes.length > limits.maxFileBytes) {
        throw PortableContainerException('Container file is too large: $path.');
      }
      totalBytes += file.bytes.length;
      if (totalBytes > limits.maxExpandedBytes) {
        throw const PortableContainerException(
          'Container expanded size exceeds the safety limit.',
        );
      }
      normalized[key] = PortableContainerFile(path: path, bytes: file.bytes);
    }
    final ordered = normalized.values.toList()
      ..sort((left, right) => left.path.compareTo(right.path));
    final manifest = <String, Object?>{
      'format': format,
      'kind': kind,
      'schemaVersion': schemaVersion,
      'metadata': metadata,
      'files': [
        for (final file in ordered)
          {
            'path': file.path,
            'size': file.bytes.length,
            'sha256': sha256.convert(file.bytes).toString(),
          },
      ],
    };
    final manifestBytes = Uint8List.fromList(utf8.encode(jsonEncode(manifest)));
    if (manifestBytes.length > limits.maxManifestBytes) {
      throw const PortableContainerException(
        'Container manifest exceeds the safety limit.',
      );
    }
    final archive = Archive();
    final manifestEntry = ArchiveFile.bytes(manifestPath, manifestBytes)
      ..lastModTime = 0;
    archive.add(manifestEntry);
    for (final file in ordered) {
      _checkCancelled(isCancelled);
      archive.add(ArchiveFile.bytes(file.path, file.bytes)..lastModTime = 0);
    }
    final encoded = ZipEncoder().encode(archive);
    if (encoded.length > limits.maxArchiveBytes) {
      throw const PortableContainerException(
        'Encoded container exceeds the safety limit.',
      );
    }
    return Uint8List.fromList(encoded);
  }

  ValidatedPortableContainer decode(
    Uint8List bytes, {
    String? expectedKind,
    bool Function()? isCancelled,
  }) {
    _checkCancelled(isCancelled);
    if (bytes.isEmpty || bytes.length > limits.maxArchiveBytes) {
      throw const PortableContainerException(
        'Container file size is outside the safety limit.',
      );
    }
    final preflight = _preflightZip(bytes);
    if (preflight.length > limits.maxFiles + 1) {
      throw PortableContainerException(
        'Container has more than ${limits.maxFiles} files.',
      );
    }
    var totalBytes = 0;
    final names = <String>{};
    for (final entry in preflight) {
      _checkCancelled(isCancelled);
      final path = _validatedPath(entry.name);
      final key = path.toLowerCase();
      if (!names.add(key)) {
        throw PortableContainerException('Duplicate container path: $path.');
      }
      if (entry.isDirectory || entry.isSymbolicLink) {
        throw PortableContainerException(
          'Directories and links are not allowed: $path.',
        );
      }
      final limit = path == manifestPath
          ? limits.maxManifestBytes
          : limits.maxFileBytes;
      if (entry.expandedSize > limit) {
        throw PortableContainerException('Container file is too large: $path.');
      }
      if (entry.compressedSize == 0 && entry.expandedSize > 0 ||
          entry.compressedSize > 0 &&
              entry.expandedSize / entry.compressedSize >
                  limits.maxExpansionRatio) {
        throw PortableContainerException(
          'Container file expands beyond the safety ratio: $path.',
        );
      }
      totalBytes += entry.expandedSize;
      if (totalBytes > limits.maxExpandedBytes) {
        throw const PortableContainerException(
          'Container expanded size exceeds the safety limit.',
        );
      }
    }

    late final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const PortableContainerException(
        'Container is not a readable ZIP archive.',
      );
    }
    final manifestEntries = archive.files
        .where((entry) => entry.name == manifestPath)
        .toList(growable: false);
    if (manifestEntries.length != 1) {
      throw const PortableContainerException(
        'Container must contain exactly one manifest.json.',
      );
    }
    late final Map<String, Object?> manifest;
    try {
      manifest =
          (jsonDecode(utf8.decode(manifestEntries.single.readBytes()!)) as Map)
              .cast<String, Object?>();
    } catch (_) {
      throw const PortableContainerException(
        'Container manifest is not valid JSON.',
      );
    }
    if (manifest['format'] != format) {
      throw const PortableContainerException('Unsupported container format.');
    }
    final kind = manifest['kind'];
    final schemaVersion = manifest['schemaVersion'];
    if (kind is! String || schemaVersion is! int || schemaVersion < 1) {
      throw const PortableContainerException(
        'Container manifest identity is invalid.',
      );
    }
    if (expectedKind != null && kind != expectedKind) {
      throw PortableContainerException(
        'Expected a $expectedKind container, but found $kind.',
      );
    }
    final manifestFiles = manifest['files'];
    if (manifestFiles is! List || manifestFiles.length > limits.maxFiles) {
      throw const PortableContainerException(
        'Container manifest file list is invalid.',
      );
    }
    final archiveByPath = <String, ArchiveFile>{
      for (final entry in archive.files)
        if (entry.name != manifestPath) entry.name: entry,
    };
    final output = <PortableContainerFile>[];
    final declared = <String>{};
    for (final raw in manifestFiles) {
      _checkCancelled(isCancelled);
      if (raw is! Map) {
        throw const PortableContainerException(
          'Container manifest file entry is invalid.',
        );
      }
      final item = raw.cast<String, Object?>();
      final rawPath = item['path'];
      final size = item['size'];
      final expectedHash = item['sha256'];
      if (rawPath is! String || size is! int || expectedHash is! String) {
        throw const PortableContainerException(
          'Container manifest file entry is incomplete.',
        );
      }
      final path = _validatedPath(rawPath);
      if (!declared.add(path.toLowerCase())) {
        throw PortableContainerException(
          'Manifest declares a path more than once: $path.',
        );
      }
      final entry = archiveByPath[path];
      if (entry == null) {
        throw PortableContainerException(
          'Container is missing declared file: $path.',
        );
      }
      final content = entry.readBytes();
      if (content == null ||
          content.length != size ||
          sha256.convert(content).toString() != expectedHash) {
        throw PortableContainerException(
          'Container checksum or size does not match: $path.',
        );
      }
      output.add(PortableContainerFile(path: path, bytes: content));
    }
    if (archiveByPath.length != declared.length ||
        archiveByPath.keys.any(
          (path) => !declared.contains(path.toLowerCase()),
        )) {
      throw const PortableContainerException(
        'Container contains files not declared by its manifest.',
      );
    }
    final rawMetadata = manifest['metadata'];
    if (rawMetadata != null && rawMetadata is! Map) {
      throw const PortableContainerException('Container metadata is invalid.');
    }
    return ValidatedPortableContainer(
      kind: kind,
      schemaVersion: schemaVersion,
      metadata: rawMetadata == null
          ? const {}
          : (rawMetadata as Map).cast<String, Object?>(),
      files: output,
    );
  }

  String _validatedPath(String input) {
    if (input.isEmpty ||
        input.length > 240 ||
        input.contains('\\') ||
        input.contains('\u0000') ||
        input.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(input)) {
      throw PortableContainerException('Unsafe container path: $input.');
    }
    final segments = input.split('/');
    if (segments.any(
      (segment) =>
          segment.isEmpty ||
          segment == '.' ||
          segment == '..' ||
          segment.codeUnits.any((unit) => unit < 32),
    )) {
      throw PortableContainerException('Unsafe container path: $input.');
    }
    return segments.join('/');
  }

  void _checkCancelled(bool Function()? isCancelled) {
    if (isCancelled?.call() ?? false) throw const PortableContainerCancelled();
  }

  List<_ZipEntryMetadata> _preflightZip(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    const eocdSignature = 0x06054b50;
    var eocd = -1;
    final lowerBound = (bytes.length - 65557).clamp(0, bytes.length);
    for (var offset = bytes.length - 22; offset >= lowerBound; offset--) {
      if (data.getUint32(offset, Endian.little) == eocdSignature) {
        eocd = offset;
        break;
      }
    }
    if (eocd < 0 ||
        data.getUint16(eocd + 4, Endian.little) != 0 ||
        data.getUint16(eocd + 6, Endian.little) != 0) {
      throw const PortableContainerException(
        'Container ZIP directory is missing or unsupported.',
      );
    }
    final entryCount = data.getUint16(eocd + 10, Endian.little);
    final directorySize = data.getUint32(eocd + 12, Endian.little);
    final directoryOffset = data.getUint32(eocd + 16, Endian.little);
    if (directoryOffset + directorySize > eocd) {
      throw const PortableContainerException(
        'Container ZIP directory is corrupt.',
      );
    }
    final entries = <_ZipEntryMetadata>[];
    var offset = directoryOffset;
    for (var index = 0; index < entryCount; index++) {
      if (offset + 46 > bytes.length ||
          data.getUint32(offset, Endian.little) != 0x02014b50) {
        throw const PortableContainerException(
          'Container ZIP entry is corrupt.',
        );
      }
      final versionMadeBy = data.getUint16(offset + 4, Endian.little);
      final flags = data.getUint16(offset + 8, Endian.little);
      final compression = data.getUint16(offset + 10, Endian.little);
      final compressedSize = data.getUint32(offset + 20, Endian.little);
      final expandedSize = data.getUint32(offset + 24, Endian.little);
      final nameLength = data.getUint16(offset + 28, Endian.little);
      final extraLength = data.getUint16(offset + 30, Endian.little);
      final commentLength = data.getUint16(offset + 32, Endian.little);
      final externalAttributes = data.getUint32(offset + 38, Endian.little);
      final end = offset + 46 + nameLength + extraLength + commentLength;
      if (end > bytes.length ||
          compressedSize == 0xffffffff ||
          expandedSize == 0xffffffff ||
          flags & 1 != 0 ||
          (compression != 0 && compression != 8)) {
        throw const PortableContainerException(
          'Container ZIP entry uses an unsupported feature.',
        );
      }
      final name = utf8.decode(
        bytes.sublist(offset + 46, offset + 46 + nameLength),
        allowMalformed: false,
      );
      final unixMode = versionMadeBy >> 8 == 3
          ? (externalAttributes >> 16) & 0xffff
          : 0;
      entries.add(
        _ZipEntryMetadata(
          name: name,
          compressedSize: compressedSize,
          expandedSize: expandedSize,
          isDirectory: name.endsWith('/') || name.endsWith('\\'),
          isSymbolicLink: unixMode & 0xf000 == 0xa000,
        ),
      );
      offset = end;
    }
    if (offset != directoryOffset + directorySize) {
      throw const PortableContainerException(
        'Container ZIP directory length does not match.',
      );
    }
    return entries;
  }
}

class _ZipEntryMetadata {
  const _ZipEntryMetadata({
    required this.name,
    required this.compressedSize,
    required this.expandedSize,
    required this.isDirectory,
    required this.isSymbolicLink,
  });

  final String name;
  final int compressedSize;
  final int expandedSize;
  final bool isDirectory;
  final bool isSymbolicLink;
}
