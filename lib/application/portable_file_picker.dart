import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

typedef PlatformFileIdentifierReader =
    Future<Uint8List> Function(String identifier);

class PlatformFileReadException implements Exception {
  const PlatformFileReadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PortableImportPickerOptions {
  const PortableImportPickerOptions({
    required this.type,
    required this.allowedExtensions,
  });

  final FileType type;
  final List<String>? allowedExtensions;
}

/// Android document providers filter by MIME type rather than filename.
/// Music Tabbler's private extensions are not registered MIME types, so a
/// custom extension filter can hide valid portable files. The container codec
/// remains the authority after selection and validates kind, schema, paths,
/// sizes, and checksums before importing anything.
PortableImportPickerOptions portableImportPickerOptions({
  required bool isAndroid,
  required String extension,
}) => isAndroid
    ? const PortableImportPickerOptions(
        type: FileType.any,
        allowedExtensions: null,
      )
    : PortableImportPickerOptions(
        type: FileType.custom,
        allowedExtensions: [extension],
      );

/// Reads the selected file using the data exposed by `file_picker`.
///
/// Keeping this in one place prevents image, PDF, song, and library imports
/// from making different assumptions about a platform picker's result shape.
Future<Uint8List> readPickedFileBytes(
  PlatformFile file, {
  PlatformFileIdentifierReader? readIdentifier,
}) async {
  final embeddedBytes = file.bytes;
  if (embeddedBytes != null) return embeddedBytes;
  final path = file.path;
  if (path != null && path.isNotEmpty) {
    try {
      return await File(path).readAsBytes();
    } on FileSystemException {
      // Some Android document providers expose a cache path that is no longer
      // readable but retain the original content URI as the identifier.
    }
  }
  final stream = file.readStream;
  if (stream != null) {
    final output = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      output.add(chunk);
    }
    return output.takeBytes();
  }
  final identifier = file.identifier;
  if (readIdentifier != null && identifier != null && identifier.isNotEmpty) {
    return readIdentifier(identifier);
  }
  throw PlatformFileReadException(
    'The selected file "${file.name}" could not be read from this device.',
  );
}
