import 'dart:async';
import 'dart:io';

import 'package:pdfrx_engine/pdfrx_engine.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  if (Platform.isMacOS && Platform.environment.containsKey('FLUTTER_TEST')) {
    final hookOutput = Directory(
      '.dart_tool/hooks_runner/shared/pdfium_dart/build',
    );
    if (hookOutput.existsSync()) {
      final libraries =
          hookOutput
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('/libpdfium.dylib'))
              .toList()
            ..sort((left, right) => left.path.compareTo(right.path));
      if (libraries.isNotEmpty) {
        Pdfrx.pdfiumModulePath = libraries.last.path;
      }
    }
  }
  await testMain();
}
