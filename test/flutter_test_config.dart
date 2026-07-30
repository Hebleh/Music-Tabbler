import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:pdfrx_engine/pdfrx_engine.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  if (Platform.isMacOS && Platform.environment.containsKey('FLUTTER_TEST')) {
    final hookOutput = Directory(
      '.dart_tool/hooks_runner/shared/pdfium_dart/build',
    );
    if (hookOutput.existsSync()) {
      final architectureDirectory = switch (Abi.current()) {
        Abi.macosArm64 => '/mac-arm64/',
        Abi.macosX64 => '/mac-x64/',
        _ => null,
      };
      final libraries =
          hookOutput
              .listSync(recursive: true)
              .whereType<File>()
              .where(
                (file) =>
                    file.path.endsWith('/libpdfium.dylib') &&
                    (architectureDirectory == null ||
                        file.path.contains(architectureDirectory)),
              )
              .toList()
            ..sort((left, right) => left.path.compareTo(right.path));
      if (libraries.isNotEmpty) {
        Pdfrx.pdfiumModulePath = libraries.last.path;
      }
    }
  }
  await testMain();
}
