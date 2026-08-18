import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/application/portable_file_picker.dart';

void main() {
  test('Android portable imports do not hide private extensions', () {
    final options = portableImportPickerOptions(
      isAndroid: true,
      extension: 'mtstate',
    );

    expect(options.type, FileType.any);
    expect(options.allowedExtensions, isNull);
  });

  test('desktop portable imports retain their extension filter', () {
    final state = portableImportPickerOptions(
      isAndroid: false,
      extension: 'mtstate',
    );
    final song = portableImportPickerOptions(
      isAndroid: false,
      extension: 'mtsong',
    );

    expect(state.type, FileType.custom);
    expect(state.allowedExtensions, ['mtstate']);
    expect(song.type, FileType.custom);
    expect(song.allowedExtensions, ['mtsong']);
  });

  test(
    'reads an Android content URI when no path or bytes are exposed',
    () async {
      final expected = Uint8List.fromList([1, 2, 3, 4]);
      final file = PlatformFile(
        name: 'portable.mtsong',
        size: expected.length,
        identifier: 'content://documents/portable.mtsong',
      );
      String? readIdentifier;

      final actual = await readPickedFileBytes(
        file,
        readIdentifier: (identifier) async {
          readIdentifier = identifier;
          return expected;
        },
      );

      expect(readIdentifier, file.identifier);
      expect(actual, expected);
    },
  );
}
