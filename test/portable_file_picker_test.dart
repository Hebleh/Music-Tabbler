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
}
