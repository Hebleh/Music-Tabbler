import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/visual_chart_models.dart';
import 'service_contracts.dart';
import 'visual_image_processor.dart';

class PlannedStrip {
  const PlannedStrip({
    required this.index,
    required this.width,
    required this.height,
  });
  final int index;
  final double width;
  final double height;
}

class PlannedPage {
  const PlannedPage(this.strips);
  final List<PlannedStrip> strips;
}

class A4StripLayout {
  const A4StripLayout({
    this.pageWidth = 595.28,
    this.pageHeight = 841.89,
    this.margin = 22,
    this.headerHeight = 28,
    this.gap = 8,
  });

  final double pageWidth;
  final double pageHeight;
  final double margin;
  final double headerHeight;
  final double gap;

  List<PlannedPage> plan(List<double> aspectRatios) {
    final availableWidth = pageWidth - margin * 2;
    final availableHeight = pageHeight - margin * 2 - headerHeight;
    final pages = <PlannedPage>[];
    var current = <PlannedStrip>[];
    var usedHeight = 0.0;

    for (var index = 0; index < aspectRatios.length; index += 1) {
      final aspect = aspectRatios[index];
      var width = availableWidth;
      var height = width / aspect;
      if (height > availableHeight) {
        height = availableHeight;
        width = height * aspect;
      }
      final needed = current.isEmpty ? height : gap + height;
      if (current.isNotEmpty && usedHeight + needed > availableHeight) {
        pages.add(PlannedPage(List.unmodifiable(current)));
        current = <PlannedStrip>[];
        usedHeight = 0;
      }
      current.add(PlannedStrip(index: index, width: width, height: height));
      usedHeight += current.length == 1 ? height : gap + height;
    }
    if (current.isNotEmpty) {
      pages.add(PlannedPage(List.unmodifiable(current)));
    }
    return pages;
  }
}

class PdfExportService implements ChartPdfExporter {
  PdfExportService(
    this.library, {
    this.processor = const VisualImageProcessor(),
    this.layout = const A4StripLayout(),
  });

  final ChartLibrary library;
  final VisualImageProcessor processor;
  final A4StripLayout layout;

  @override
  Future<Uint8List> exportBytes(VisualChartDraft draft) async {
    if (draft.strips.isEmpty) {
      throw StateError('Add at least one tab strip before exporting.');
    }
    final processed = <Uint8List>[];
    for (final strip in draft.strips) {
      final file = File(
        library.assetPath(strip.assetHash, strip.assetExtension),
      );
      final bytes = await file.readAsBytes();
      processed.add(
        processor.process(bytes, strip, globalTreatment: draft.globalTreatment),
      );
    }

    final pages = layout.plan(
      draft.strips.map((strip) => strip.croppedAspectRatio).toList(),
    );
    final document = pw.Document(
      title: draft.title,
      author: draft.artist,
      creator: 'Music Tabbler',
    );
    for (final page in pages) {
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(22),
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                height: 28,
                child: draft.showHeader
                    ? pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            draft.title,
                            style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          if (draft.artist.isNotEmpty)
                            pw.Text(
                              draft.artist,
                              style: const pw.TextStyle(fontSize: 8),
                            ),
                        ],
                      )
                    : pw.SizedBox(),
              ),
              for (
                var itemIndex = 0;
                itemIndex < page.strips.length;
                itemIndex += 1
              ) ...[
                if (itemIndex > 0) pw.SizedBox(height: 8),
                pw.Align(
                  alignment: pw.Alignment.centerLeft,
                  child: pw.SizedBox(
                    width: page.strips[itemIndex].width,
                    height: page.strips[itemIndex].height,
                    child: pw.Image(
                      pw.MemoryImage(processed[page.strips[itemIndex].index]),
                      fit: pw.BoxFit.fill,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Uint8List.fromList(await document.save());
  }

  @override
  Future<String?> exportWithPicker(VisualChartDraft draft) async {
    final safeTitle = draft.title.trim().isEmpty
        ? 'music-tabbler-chart'
        : draft.title.trim().replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final destination = await FilePicker.platform.saveFile(
      dialogTitle: 'Export A4 chart',
      fileName: '$safeTitle.pdf',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (destination == null) return null;
    final path = destination.toLowerCase().endsWith('.pdf')
        ? destination
        : '$destination.pdf';
    await File(path).writeAsBytes(await exportBytes(draft), flush: true);
    return path;
  }
}
