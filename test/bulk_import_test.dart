import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:music_tabbler/application/visual_import_service.dart';
import 'package:music_tabbler/infrastructure/local_library.dart';

void main() {
  test('folder intake imports supported screenshots in path order', () async {
    final root = await Directory.systemTemp.createTemp('music-tabbler-drop-');
    addTearDown(() => root.delete(recursive: true));
    final source = Directory('${root.path}${Platform.pathSeparator}screens')
      ..createSync();
    final image = img.Image(width: 20, height: 10);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    final bytes = img.encodePng(image);
    await File(
      '${source.path}${Platform.pathSeparator}02.png',
    ).writeAsBytes(bytes);
    await File(
      '${source.path}${Platform.pathSeparator}01.png',
    ).writeAsBytes(bytes);
    await File(
      '${source.path}${Platform.pathSeparator}ignore.txt',
    ).writeAsString('not a chart');

    final library = await LocalLibrary.forTesting(root);
    final importer = VisualImportService(library);
    final strips = await importer.importPaths([source.path]);

    expect(strips, hasLength(2));
    expect(strips.every((strip) => strip.pixelWidth == 20), isTrue);
  });
}
