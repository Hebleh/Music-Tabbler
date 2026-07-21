import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/application/pdf_export_service.dart';
import 'package:music_tabbler/application/visual_import_service.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';
import 'package:music_tabbler/infrastructure/local_library.dart';

void main() {
  test('exports the supplied Songsterr screenshot for visual QA', () async {
    final inputPath = Platform.environment['MUSIC_TABBLER_SONGSTERR_INPUT'];
    final outputPath = Platform.environment['MUSIC_TABBLER_VISUAL_OUTPUT'];
    if (inputPath == null || outputPath == null) return;
    final temporary = await Directory.systemTemp.createTemp(
      'music-tabbler-qa-',
    );
    final library = await LocalLibrary.forTesting(temporary);
    try {
      final input = File(inputPath);
      final importer = VisualImportService(library);
      final strip = await importer.importImage(
        await input.readAsBytes(),
        'png',
      );
      final now = DateTime.now().toUtc();
      final draft = VisualChartDraft(
        id: 'songsterr-qa',
        title: 'Thank You for the Venom',
        artist: 'My Chemical Romance',
        createdAt: now,
        updatedAt: now,
        strips: [strip],
      );
      final bytes = await PdfExportService(library).exportBytes(draft);
      await File(outputPath).writeAsBytes(bytes, flush: true);
    } finally {
      library.close();
      await temporary.delete(recursive: true);
    }
  });
}
