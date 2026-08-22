import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/application/import_contracts.dart';
import 'package:music_tabbler/application/visual_import_service.dart';

void main() {
  test('reads Android-style picker bytes when no local path exists', () async {
    final selected = PlatformFile(
      name: 'songsterr-tab.pdf',
      size: 4,
      bytes: Uint8List.fromList([37, 80, 68, 70]),
    );

    expect(await readPlatformFileBytes(selected), [37, 80, 68, 70]);
  });

  test('reads a local picker path when byte data was not requested', () async {
    final directory = await Directory.systemTemp.createTemp(
      'music-tabbler-picker-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}${Platform.pathSeparator}tab.pdf');
    await source.writeAsBytes([1, 2, 3]);
    final selected = PlatformFile(name: 'tab.pdf', size: 3, path: source.path);

    expect(await readPlatformFileBytes(selected), [1, 2, 3]);
  });

  test('reads a stream when neither bytes nor a path is available', () async {
    final selected = PlatformFile(
      name: 'provider.pdf',
      size: 3,
      readStream: Stream<List<int>>.fromIterable([
        [1],
        [2, 3],
      ]),
    );

    expect(await readPlatformFileBytes(selected), [1, 2, 3]);
  });

  test('reports an actionable error when a picker result is unreadable', () {
    final selected = PlatformFile(name: 'missing.pdf', size: 1);

    expect(
      () => readPlatformFileBytes(selected),
      throwsA(
        isA<VisualImportException>().having(
          (error) => error.message,
          'message',
          contains('no readable data'),
        ),
      ),
    );
  });
}
