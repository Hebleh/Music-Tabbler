import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
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
  const PlannedPage(this.strips, {required this.headerHeight});
  final List<PlannedStrip> strips;
  final double headerHeight;
}

class A4StripLayout {
  const A4StripLayout({
    this.pageWidth = 595.28,
    this.pageHeight = 841.89,
    this.margin = 5,
    this.headerHeight = 24,
    this.gap = 0,
    this.minimumRowHeight = 0,
  });

  final double pageWidth;
  final double pageHeight;
  final double margin;
  final double headerHeight;
  final double gap;
  final double minimumRowHeight;

  List<PlannedPage> plan(
    List<double> aspectRatios, {
    bool includeFirstPageHeader = true,
  }) {
    final availableWidth = pageWidth - margin * 2;
    final pages = <PlannedPage>[];
    var current = <PlannedStrip>[];
    var usedHeight = 0.0;

    double availableHeightFor(int pageIndex) =>
        pageHeight -
        margin * 2 -
        (pageIndex == 0 && includeFirstPageHeader ? headerHeight : 0);

    for (var index = 0; index < aspectRatios.length; index += 1) {
      final aspect = aspectRatios[index];
      var availableHeight = availableHeightFor(pages.length);
      var width = availableWidth;
      var height = width / aspect;
      if (height > availableHeight) {
        height = availableHeight;
        width = height * aspect;
      }
      if (height < minimumRowHeight) {
        throw StateError(
          'Row ${index + 1} would render at ${height.toStringAsFixed(1)} pt, '
          'below the ${minimumRowHeight.toStringAsFixed(0)} pt minimum for '
          'this density profile. Choose Original (v0.1.0) or crop the row '
          'more tightly.',
        );
      }
      final needed = current.isEmpty ? height : gap + height;
      if (current.isNotEmpty && usedHeight + needed > availableHeight) {
        pages.add(
          PlannedPage(
            List.unmodifiable(current),
            headerHeight: pages.isEmpty && includeFirstPageHeader
                ? headerHeight
                : 0,
          ),
        );
        current = <PlannedStrip>[];
        usedHeight = 0;
        availableHeight = availableHeightFor(pages.length);
        width = availableWidth;
        height = width / aspect;
        if (height > availableHeight) {
          height = availableHeight;
          width = height * aspect;
        }
        if (height < minimumRowHeight) {
          throw StateError(
            'Row ${index + 1} would render below the minimum height for this '
            'density profile.',
          );
        }
      }
      current.add(PlannedStrip(index: index, width: width, height: height));
      usedHeight += current.length == 1 ? height : gap + height;
    }
    if (current.isNotEmpty) {
      pages.add(
        PlannedPage(
          List.unmodifiable(current),
          headerHeight: pages.isEmpty && includeFirstPageHeader
              ? headerHeight
              : 0,
        ),
      );
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
    final density = _ExportDensitySettings.forDensity(draft.exportDensity);
    final exportLayout = draft.exportDensity == VisualExportDensity.original
        ? layout
        : density.layout;
    final grouped = <String, List<(int, VisualStrip)>>{};
    for (var index = 0; index < draft.strips.length; index += 1) {
      final strip = draft.strips[index];
      final key = '${strip.assetHash}.${strip.assetExtension}';
      grouped.putIfAbsent(key, () => []).add((index, strip));
    }
    final processed = <Map<String, Object>>[];
    for (final group in grouped.values) {
      final first = group.first.$2;
      final bytes = await File(
        library.assetPath(first.assetHash, first.assetExtension),
      ).readAsBytes();
      processed.addAll(
        await compute(_processAssetForExport, {
          'bytes': bytes,
          'strips': [for (final item in group) item.$2.toJson()],
          'indices': [for (final item in group) item.$1],
          'globalTreatment': draft.globalTreatment?.name,
          'splitDetectedRowsBelowAspectRatio':
              density.splitDetectedRowsBelowAspectRatio,
        }),
      );
    }
    processed.sort((left, right) {
      final stripOrder = (left['stripIndex']! as int).compareTo(
        right['stripIndex']! as int,
      );
      return stripOrder != 0
          ? stripOrder
          : (left['rowIndex']! as int).compareTo(right['rowIndex']! as int);
    });

    return compute(_buildPdfInBackground, {
      'processed': processed,
      'title': draft.title,
      'artist': draft.artist,
      'showHeader': draft.showHeader,
      'pageWidth': exportLayout.pageWidth,
      'pageHeight': exportLayout.pageHeight,
      'margin': exportLayout.margin,
      'headerHeight': exportLayout.headerHeight,
      'gap': exportLayout.gap,
      'minimumRowHeight': exportLayout.minimumRowHeight,
    });
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

List<Map<String, Object>> _processAssetForExport(Map<String, Object?> request) {
  final strips = [
    for (final value in request['strips']! as List)
      VisualStrip.fromJson((value as Map).cast<String, Object?>()),
  ];
  final indices = (request['indices']! as List).cast<int>();
  final treatmentName = request['globalTreatment'] as String?;
  final treatment = treatmentName == null
      ? null
      : VisualTreatment.values.byName(treatmentName);
  final batches = const VisualImageProcessor().processForExportBatch(
    request['bytes']! as Uint8List,
    strips,
    globalTreatment: treatment,
    splitDetectedRowsBelowAspectRatio:
        (request['splitDetectedRowsBelowAspectRatio']! as num).toDouble(),
  );
  return [
    for (var stripIndex = 0; stripIndex < batches.length; stripIndex += 1)
      for (
        var rowIndex = 0;
        rowIndex < batches[stripIndex].length;
        rowIndex += 1
      )
        {
          'stripIndex': indices[stripIndex],
          'rowIndex': rowIndex,
          'bytes': batches[stripIndex][rowIndex].bytes,
          'aspectRatio': batches[stripIndex][rowIndex].aspectRatio,
        },
  ];
}

Future<Uint8List> _buildPdfInBackground(Map<String, Object?> request) async {
  final processed = (request['processed']! as List)
      .map((value) => (value as Map).cast<String, Object>())
      .toList(growable: false);
  final showHeader = request['showHeader']! as bool;
  final layout = A4StripLayout(
    pageWidth: request['pageWidth']! as double,
    pageHeight: request['pageHeight']! as double,
    margin: request['margin']! as double,
    headerHeight: request['headerHeight']! as double,
    gap: request['gap']! as double,
    minimumRowHeight: request['minimumRowHeight']! as double,
  );
  final pages = layout.plan([
    for (final item in processed) item['aspectRatio']! as double,
  ], includeFirstPageHeader: showHeader);
  final title = request['title']! as String;
  final artist = request['artist']! as String;
  final document = pw.Document(
    title: title,
    author: artist,
    creator: 'Music Tabbler',
  );
  for (var pageIndex = 0; pageIndex < pages.length; pageIndex += 1) {
    final page = pages[pageIndex];
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(layout.pageWidth, layout.pageHeight),
        margin: pw.EdgeInsets.all(layout.margin),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (page.headerHeight > 0)
              pw.SizedBox(
                height: page.headerHeight,
                child: pageIndex == 0 && showHeader
                    ? pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            title,
                            style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          if (artist.isNotEmpty)
                            pw.Text(
                              artist,
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
              if (itemIndex > 0) pw.SizedBox(height: layout.gap),
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.SizedBox(
                  width: page.strips[itemIndex].width,
                  height: page.strips[itemIndex].height,
                  child: pw.Image(
                    pw.MemoryImage(
                      processed[page.strips[itemIndex].index]['bytes']!
                          as Uint8List,
                    ),
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

class _ExportDensitySettings {
  const _ExportDensitySettings({
    required this.layout,
    required this.splitDetectedRowsBelowAspectRatio,
  });

  final A4StripLayout layout;
  final double splitDetectedRowsBelowAspectRatio;

  static _ExportDensitySettings forDensity(VisualExportDensity density) {
    return switch (density) {
      VisualExportDensity.original => const _ExportDensitySettings(
        layout: A4StripLayout(),
        splitDetectedRowsBelowAspectRatio: 2.2,
      ),
      VisualExportDensity.balanced => const _ExportDensitySettings(
        layout: A4StripLayout(minimumRowHeight: 34),
        splitDetectedRowsBelowAspectRatio: 2.8,
      ),
      VisualExportDensity.stageReadable => const _ExportDensitySettings(
        layout: A4StripLayout(
          pageWidth: 841.89,
          pageHeight: 595.28,
          minimumRowHeight: 48,
        ),
        splitDetectedRowsBelowAspectRatio: 3.5,
      ),
    };
  }
}
