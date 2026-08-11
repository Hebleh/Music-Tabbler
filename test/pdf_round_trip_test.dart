import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:music_tabbler/application/pdf_export_service.dart';
import 'package:music_tabbler/application/visual_import_service.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';
import 'package:music_tabbler/infrastructure/local_library.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  test('PDF export applies the density saved on the draft', () async {
    final directory = await Directory.systemTemp.createTemp(
      'music_tabbler_density_',
    );
    final library = await LocalLibrary.forTesting(directory);
    addTearDown(() {
      library.close();
      directory.deleteSync(recursive: true);
    });
    final source = img.Image(width: 600, height: 240);
    img.fill(source, color: img.ColorRgb8(255, 255, 255));
    img.fillRect(
      source,
      x1: 20,
      y1: 35,
      x2: 580,
      y2: 90,
      color: img.ColorRgb8(0, 0, 0),
    );
    img.fillRect(
      source,
      x1: 20,
      y1: 155,
      x2: 580,
      y2: 210,
      color: img.ColorRgb8(0, 0, 0),
    );
    final stored = await library.storeAsset(img.encodePng(source), 'png');
    final now = DateTime.utc(2026, 7, 22);
    final base = VisualChartDraft(
      id: 'density',
      title: 'Density',
      artist: '',
      createdAt: now,
      updatedAt: now,
      showHeader: false,
      strips: [
        VisualStrip(
          id: 'strip',
          assetHash: stored.hash,
          assetExtension: stored.extension,
          pixelWidth: 600,
          pixelHeight: 240,
        ),
      ],
    );

    final original = latin1.decode(
      await VisualChartPdfExporter(library).exportBytes(base),
      allowInvalid: true,
    );
    final stage = latin1.decode(
      await VisualChartPdfExporter(library).exportBytes(
        base.copyWith(exportDensity: VisualExportDensity.stageReadable),
      ),
      allowInvalid: true,
    );

    expect(original, contains('/MediaBox[0 0 595.28 841.89]'));
    expect(stage, contains('/MediaBox[0 0 841.89 595.28]'));
  });

  test('source provenance never enters individual PDF output', () async {
    final directory = await Directory.systemTemp.createTemp(
      'music_tabbler_provenance_pdf_',
    );
    final library = await LocalLibrary.forTesting(directory);
    addTearDown(() {
      library.close();
      directory.deleteSync(recursive: true);
    });
    final source = img.Image(width: 300, height: 80);
    img.fill(source, color: img.ColorRgb8(255, 255, 255));
    final stored = await library.storeAsset(img.encodePng(source), 'png');
    final now = DateTime.utc(2026, 7, 24);
    final output = await VisualChartPdfExporter(library).exportBytes(
      VisualChartDraft(
        id: 'private-source',
        title: 'Song',
        artist: '',
        createdAt: now,
        updatedAt: now,
        provenance: const SourceProvenance(
          url: 'https://example.invalid/private-version-token',
          provider: 'Private source label',
          notes: 'Never print this note',
        ),
        strips: [
          VisualStrip(
            id: 'strip',
            assetHash: stored.hash,
            assetExtension: stored.extension,
            pixelWidth: 300,
            pixelHeight: 80,
          ),
        ],
      ),
    );
    final pdfText = latin1.decode(output, allowInvalid: true);

    expect(pdfText, isNot(contains('private-version-token')));
    expect(pdfText, isNot(contains('Private source label')));
    expect(pdfText, isNot(contains('Never print this note')));
  });

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
      final output = await VisualChartPdfExporter(library).exportBytes(draft);

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
