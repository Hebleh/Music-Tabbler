import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/application/pdf_export_service.dart';
import 'package:music_tabbler/application/visual_import_service.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';
import 'package:music_tabbler/infrastructure/local_library.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  test(
    'PDF pages round-trip through visual strips into deterministic A4',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'music_tabbler_pdf_',
      );
      final library = await LocalLibrary.forTesting(directory);
      addTearDown(() {
        library.close();
        directory.deleteSync(recursive: true);
      });

      final inputPath = Platform.environment['MUSIC_TABBLER_SMOKE_INPUT'];
      final inputBytes = inputPath == null
          ? await _syntheticInput()
          : await File(inputPath).readAsBytes();
      final importer = VisualImportService(library);
      final pages = await importer.importPdf(inputBytes);

      expect(pages, isNotEmpty);
      expect(
        pages.every((page) => page.pixelWidth > 0 && page.pixelHeight > 0),
        isTrue,
      );

      final bands =
          int.tryParse(
            Platform.environment['MUSIC_TABBLER_SMOKE_BANDS'] ?? '',
          ) ??
          2;
      final strips = <VisualStrip>[];
      for (final page in pages) {
        for (var band = 0; band < bands; band += 1) {
          final top = band / bands;
          final bottom = (band + 1) / bands;
          strips.add(
            VisualStrip(
              id: IdFactory.next('strip'),
              assetHash: page.assetHash,
              assetExtension: page.assetExtension,
              pixelWidth: page.pixelWidth,
              pixelHeight: page.pixelHeight,
              sourceAssetHash: page.sourceAssetHash,
              sourcePage: page.sourcePage,
              crop: NormalizedRect(0, top, 1, bottom),
            ),
          );
        }
      }
      final now = DateTime.now().toUtc();
      final draft = VisualChartDraft(
        id: 'round_trip',
        title: 'PDF round-trip',
        artist: 'Music Tabbler QA',
        createdAt: now,
        updatedAt: now,
        strips: strips,
      );
      final output = await PdfExportService(library).exportBytes(draft);

      expect(String.fromCharCodes(output.take(5)), '%PDF-');
      expect(output.length, greaterThan(1000));
      final outputPath = Platform.environment['MUSIC_TABBLER_VISUAL_OUTPUT'];
      if (outputPath != null) {
        await File(outputPath).writeAsBytes(output, flush: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<Uint8List> _syntheticInput() async {
  final document = pw.Document();
  document.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (_) => pw.Column(
        children: [
          pw.Text('Synthetic Bass Tab'),
          for (var row = 0; row < 8; row += 1)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 8),
              child: pw.Column(
                children: [
                  for (var string = 0; string < 5; string += 1)
                    pw.Row(
                      children: [
                        pw.SizedBox(width: 14, child: pw.Text('GDAEB'[string])),
                        pw.Expanded(child: pw.Divider()),
                        pw.Text('${(row + string) % 12}'),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
  return Uint8List.fromList(await document.save());
}
