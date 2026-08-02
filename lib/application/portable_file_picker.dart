import 'package:file_picker/file_picker.dart';

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
