import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/library_models.dart';
import '../domain/visual_chart_models.dart';
import 'performance_deck.dart';
import 'service_contracts.dart';
import 'visual_image_processor.dart';
import 'visual_annotation_renderer.dart';

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
    this.minimumRowHeightTolerance = 0.9,
  });

  final double pageWidth;
  final double pageHeight;
  final double margin;
  final double headerHeight;
  final double gap;
  final double minimumRowHeight;
  final double minimumRowHeightTolerance;

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
      if (!_meetsReadableRowFloor(
        height,
        minimumRowHeight,
        minimumRowHeightTolerance,
      )) {
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
        if (!_meetsReadableRowFloor(
          height,
          minimumRowHeight,
          minimumRowHeightTolerance,
        )) {
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

enum PlannedSetlistElementKind { header, boundary, strip, placeholder }

class SetlistLayoutEntry {
  const SetlistLayoutEntry.chart({
    required this.entryIndex,
    required this.aspectRatios,
    required this.showHeader,
  }) : isPlaceholder = false;

  const SetlistLayoutEntry.placeholder({required this.entryIndex})
    : aspectRatios = const [],
      showHeader = false,
      isPlaceholder = true;

  final int entryIndex;
  final List<double> aspectRatios;
  final bool showHeader;
  final bool isPlaceholder;
}

class PlannedSetlistElement {
  const PlannedSetlistElement({
    required this.kind,
    required this.entryIndex,
    required this.width,
    required this.height,
    this.rowIndex,
  });

  final PlannedSetlistElementKind kind;
  final int entryIndex;
  final int? rowIndex;
  final double width;
  final double height;
}

class PlannedSetlistPage {
  const PlannedSetlistPage(this.elements);

  final List<PlannedSetlistElement> elements;
}

class SetlistA4Layout {
  const SetlistA4Layout({
    required this.pageWidth,
    required this.pageHeight,
    required this.margin,
    required this.songHeaderHeight,
    required this.minimumRowHeight,
    this.minimumRowHeightTolerance = 0.9,
    this.hiddenHeaderBoundaryHeight = 2,
    this.placeholderHeight = 22,
    this.gap = 0,
  });

  factory SetlistA4Layout.fromStripLayout(A4StripLayout layout) {
    return SetlistA4Layout(
      pageWidth: layout.pageWidth,
      pageHeight: layout.pageHeight,
      margin: layout.margin,
      songHeaderHeight: layout.headerHeight,
      minimumRowHeight: layout.minimumRowHeight,
      minimumRowHeightTolerance: layout.minimumRowHeightTolerance,
      gap: layout.gap,
    );
  }

  final double pageWidth;
  final double pageHeight;
  final double margin;
  final double songHeaderHeight;
  final double hiddenHeaderBoundaryHeight;
  final double placeholderHeight;
  final double minimumRowHeight;
  final double minimumRowHeightTolerance;
  final double gap;

  List<PlannedSetlistPage> plan(List<SetlistLayoutEntry> entries) {
    final availableWidth = pageWidth - margin * 2;
    final availableHeight = pageHeight - margin * 2;
    final pages = <PlannedSetlistPage>[];
    var current = <PlannedSetlistElement>[];
    var usedHeight = 0.0;

    void finishPage() {
      if (current.isEmpty) return;
      pages.add(PlannedSetlistPage(List.unmodifiable(current)));
      current = <PlannedSetlistElement>[];
      usedHeight = 0;
    }

    void addElement(PlannedSetlistElement element) {
      current.add(element);
      usedHeight += (current.length == 1 ? 0 : gap) + element.height;
    }

    for (final entry in entries) {
      if (entry.isPlaceholder) {
        if (current.isNotEmpty &&
            usedHeight + gap + placeholderHeight > availableHeight) {
          finishPage();
        }
        addElement(
          PlannedSetlistElement(
            kind: PlannedSetlistElementKind.placeholder,
            entryIndex: entry.entryIndex,
            width: availableWidth,
            height: placeholderHeight,
          ),
        );
        continue;
      }
      if (entry.aspectRatios.isEmpty) {
        throw StateError(
          'Set item ${entry.entryIndex + 1} has no tab rows to export.',
        );
      }
      final boundaryHeight = entry.showHeader
          ? songHeaderHeight
          : hiddenHeaderBoundaryHeight;
      final firstAspect = entry.aspectRatios.first;
      var firstHeight = availableWidth / firstAspect;
      var firstWidth = availableWidth;
      final maximumFirstHeight = availableHeight - boundaryHeight;
      if (firstHeight > maximumFirstHeight) {
        firstHeight = maximumFirstHeight;
        firstWidth = firstHeight * firstAspect;
      }
      _requireReadableRow(
        firstHeight,
        entryIndex: entry.entryIndex,
        rowIndex: 0,
      );
      final firstGroupHeight = boundaryHeight + gap + firstHeight;
      if (current.isNotEmpty &&
          usedHeight + gap + firstGroupHeight > availableHeight) {
        finishPage();
      }
      addElement(
        PlannedSetlistElement(
          kind: entry.showHeader
              ? PlannedSetlistElementKind.header
              : PlannedSetlistElementKind.boundary,
          entryIndex: entry.entryIndex,
          width: availableWidth,
          height: boundaryHeight,
        ),
      );
      addElement(
        PlannedSetlistElement(
          kind: PlannedSetlistElementKind.strip,
          entryIndex: entry.entryIndex,
          rowIndex: 0,
          width: firstWidth,
          height: firstHeight,
        ),
      );

      for (
        var rowIndex = 1;
        rowIndex < entry.aspectRatios.length;
        rowIndex += 1
      ) {
        final aspect = entry.aspectRatios[rowIndex];
        var height = availableWidth / aspect;
        var width = availableWidth;
        if (height > availableHeight) {
          height = availableHeight;
          width = height * aspect;
        }
        _requireReadableRow(
          height,
          entryIndex: entry.entryIndex,
          rowIndex: rowIndex,
        );
        if (usedHeight + gap + height > availableHeight) {
          finishPage();
        }
        addElement(
          PlannedSetlistElement(
            kind: PlannedSetlistElementKind.strip,
            entryIndex: entry.entryIndex,
            rowIndex: rowIndex,
            width: width,
            height: height,
          ),
        );
      }
    }
    finishPage();
    return pages;
  }

  void _requireReadableRow(
    double height, {
    required int entryIndex,
    required int rowIndex,
  }) {
    if (!_meetsReadableRowFloor(
      height,
      minimumRowHeight,
      minimumRowHeightTolerance,
    )) {
      throw StateError(
        'Set item ${entryIndex + 1}, row ${rowIndex + 1} would render at '
        '${height.toStringAsFixed(1)} pt, below the '
        '${minimumRowHeight.toStringAsFixed(0)} pt minimum for this density '
        'profile.',
      );
    }
  }
}

bool _meetsReadableRowFloor(
  double height,
  double minimumRowHeight,
  double tolerance,
) {
  if (minimumRowHeight <= 0) return true;
  return height >= minimumRowHeight * tolerance;
}

class StagedPdfFileWriter {
  const StagedPdfFileWriter();

  Future<void> write(String path, Uint8List bytes) async {
    final destination = File(path);
    final token = DateTime.now().microsecondsSinceEpoch;
    final temporary = File('$path.music-tabbler-$token.partial');
    final previous = File('$path.music-tabbler-$token.previous');
    var movedPrevious = false;
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      if (await destination.exists()) {
        await destination.rename(previous.path);
        movedPrevious = true;
      }
      await temporary.rename(path);
      if (movedPrevious && await previous.exists()) {
        await previous.delete();
      }
    } catch (_) {
      if (!await destination.exists() &&
          movedPrevious &&
          await previous.exists()) {
        await previous.rename(path);
      }
      rethrow;
    } finally {
      if (await temporary.exists()) await temporary.delete();
      if (await previous.exists() && await destination.exists()) {
        await previous.delete();
      }
    }
  }
}

class PdfExportService
    implements ChartPdfExporter, SetlistPdfExporter, PerformanceDeckBuilder {
  PdfExportService(
    this.library, {
    this.processor = const VisualImageProcessor(),
    this.layout = const A4StripLayout(),
    this.fileWriter = const StagedPdfFileWriter(),
  });

  final ChartLibrary library;
  final VisualImageProcessor processor;
  final A4StripLayout layout;
  final StagedPdfFileWriter fileWriter;

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
      'minimumRowHeightTolerance': exportLayout.minimumRowHeightTolerance,
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

  @override
  Future<Uint8List> exportSetlistBytes(
    LibrarySetlist setlist, {
    required VisualExportDensity density,
  }) async {
    final items = await _collectSetlistItems(setlist);
    try {
      return await compute(_buildSetlistPdfInBackground, {
        'setlistId': setlist.id,
        'setlistName': setlist.name,
        'density': density.name,
        'items': items,
      });
    } on SetlistPdfExportException {
      rethrow;
    } catch (error) {
      throw SetlistPdfExportException(
        'The setlist PDF could not be created: $error',
      );
    }
  }

  @override
  Future<PerformanceDeck> buildPerformanceDeck(
    LibrarySetlist setlist, {
    required VisualExportDensity density,
  }) async {
    final items = await _collectSetlistItems(setlist);
    try {
      final message = await compute(_buildPerformanceDeckMessage, {
        'setlistId': setlist.id,
        'setlistName': setlist.name,
        'density': density.name,
        'items': items,
      });
      return PerformanceDeck.fromMessage(message);
    } on SetlistPdfExportException {
      rethrow;
    } catch (error) {
      throw SetlistPdfExportException(
        'The performance pages could not be prepared: $error',
      );
    }
  }

  Future<List<Map<String, Object?>>> _collectSetlistItems(
    LibrarySetlist setlist,
  ) async {
    if (setlist.entries.isEmpty) {
      throw const SetlistPdfExportException(
        'Add at least one song or placeholder before exporting this setlist.',
      );
    }
    final items = <Map<String, Object?>>[];
    for (var index = 0; index < setlist.entries.length; index += 1) {
      final entry = setlist.entries[index];
      if (entry.kind == SetlistEntryKind.placeholder) {
        items.add({
          'kind': SetlistEntryKind.placeholder.name,
          'entryId': entry.id,
          'title': entry.placeholderTitle,
        });
        continue;
      }
      final draft = await library.loadDraft(entry.chartVariantId!);
      if (draft == null) {
        throw SetlistPdfExportException(
          'Set item ${index + 1} references a chart that is no longer '
          'available (${entry.chartVariantId}).',
        );
      }
      if (draft.strips.isEmpty) {
        throw SetlistPdfExportException(
          'Set item ${index + 1}, "${_displayDraftTitle(draft)}", has no tab '
          'rows to export.',
        );
      }
      final assetPaths = <String, String>{};
      for (final strip in draft.strips) {
        final key = '${strip.assetHash}.${strip.assetExtension}';
        assetPaths[key] = library.assetPath(
          strip.assetHash,
          strip.assetExtension,
        );
      }
      items.add({
        'kind': SetlistEntryKind.chart.name,
        'entryId': entry.id,
        'chartVariantId': entry.chartVariantId,
        'draft': draft.toJson(),
        'assetPaths': assetPaths,
      });
    }
    return items;
  }

  @override
  Future<String?> exportSetlistWithPicker(
    LibrarySetlist setlist, {
    required VisualExportDensity density,
  }) async {
    final safeName = _safePdfName(setlist.name, fallback: 'music-tabbler-set');
    final destination = await FilePicker.platform.saveFile(
      dialogTitle: 'Export setlist as A4 PDF',
      fileName: '$safeName.pdf',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (destination == null) return null;
    final path = destination.toLowerCase().endsWith('.pdf')
        ? destination
        : '$destination.pdf';
    final bytes = await exportSetlistBytes(setlist, density: density);
    await fileWriter.write(path, bytes);
    return path;
  }
}

String _displayDraftTitle(VisualChartDraft draft) {
  final title = draft.title.trim();
  if (title.isNotEmpty && title != 'Untitled chart') return title;
  final artist = draft.artist.trim();
  return artist.isEmpty ? 'Untitled chart' : artist;
}

String _safePdfName(String value, {required String fallback}) {
  final trimmed = value.trim();
  return (trimmed.isEmpty ? fallback : trimmed).replaceAll(
    RegExp(r'[<>:"/\\|?*]'),
    '_',
  );
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
          'annotations': [
            for (final stroke in _annotationsForRow(
              strips[stripIndex].annotations,
              batches[stripIndex][rowIndex].sourceRect,
            ))
              stroke.toJson(),
          ],
          'includeAnnotationsInPdf': strips[stripIndex].includeAnnotationsInPdf,
          'annotationsVisible': strips[stripIndex].annotationsVisible,
          'sourceStripId': strips[stripIndex].id,
          'sourceRowRect': batches[stripIndex][rowIndex].sourceRect.toJson(),
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
    minimumRowHeightTolerance: request['minimumRowHeightTolerance']! as double,
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
                      _imageBytesForPdf(
                        processed[page.strips[itemIndex].index],
                      ),
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

Future<Uint8List> _buildSetlistPdfInBackground(
  Map<String, Object?> request,
) async {
  return _renderPerformanceDeckPdf(
    PerformanceDeck.fromMessage(_buildPerformanceDeckMessage(request)),
  );
}

Map<String, Object?> _buildPerformanceDeckMessage(
  Map<String, Object?> request,
) {
  final density = VisualExportDensity.values.byName(
    request['density']! as String,
  );
  final settings = _ExportDensitySettings.forDensity(density);
  final layout = SetlistA4Layout.fromStripLayout(settings.layout);
  final rawItems = (request['items']! as List)
      .map((value) => (value as Map).cast<String, Object?>())
      .toList(growable: false);
  final draftsByEntry = <int, VisualChartDraft>{};
  final placeholdersByEntry = <int, String>{};
  final processedByEntry = <int, List<Map<String, Object>>>{};
  final processedByDraft = <String, List<Map<String, Object>>>{};
  final layoutEntries = <SetlistLayoutEntry>[];

  for (var entryIndex = 0; entryIndex < rawItems.length; entryIndex += 1) {
    final item = rawItems[entryIndex];
    final kind = SetlistEntryKind.values.byName(item['kind']! as String);
    if (kind == SetlistEntryKind.placeholder) {
      placeholdersByEntry[entryIndex] = item['title']! as String;
      layoutEntries.add(SetlistLayoutEntry.placeholder(entryIndex: entryIndex));
      continue;
    }
    final draft = VisualChartDraft.fromJson(
      (item['draft']! as Map).cast<String, Object?>(),
    );
    draftsByEntry[entryIndex] = draft;
    final cached = processedByDraft[draft.id];
    late final List<Map<String, Object>> processed;
    if (cached != null) {
      processed = cached;
    } else {
      try {
        processed = _processDraftForSetlist(
          draft,
          (item['assetPaths']! as Map).cast<String, String>(),
          splitDetectedRowsBelowAspectRatio:
              settings.splitDetectedRowsBelowAspectRatio,
        );
      } catch (error) {
        throw SetlistPdfExportException(
          'Set item ${entryIndex + 1}, "${_displayDraftTitle(draft)}", could '
          'not be prepared: $error',
        );
      }
    }
    processedByDraft[draft.id] = processed;
    processedByEntry[entryIndex] = processed;
    layoutEntries.add(
      SetlistLayoutEntry.chart(
        entryIndex: entryIndex,
        aspectRatios: [
          for (final row in processed) row['aspectRatio']! as double,
        ],
        showHeader: draft.showHeader,
      ),
    );
  }

  final pages = layout.plan(layoutEntries);
  return PerformanceDeck(
    setlistId: request['setlistId']! as String,
    setlistName: request['setlistName']! as String,
    density: density,
    pageWidth: layout.pageWidth,
    pageHeight: layout.pageHeight,
    margin: layout.margin,
    gap: layout.gap,
    pages: List.unmodifiable([
      for (var pageIndex = 0; pageIndex < pages.length; pageIndex += 1)
        PerformanceDeckPage(
          id: '${request['setlistId']}:${density.name}:$pageIndex',
          index: pageIndex,
          elements: List.unmodifiable([
            for (final element in pages[pageIndex].elements)
              PerformanceDeckElement(
                kind: PerformanceElementKind.values.byName(element.kind.name),
                entryIndex: element.entryIndex,
                entryId: rawItems[element.entryIndex]['entryId']! as String,
                chartVariantId:
                    rawItems[element.entryIndex]['chartVariantId'] as String?,
                sourceStripId: element.kind == PlannedSetlistElementKind.strip
                    ? processedByEntry[element.entryIndex]![element
                              .rowIndex!]['sourceStripId']!
                          as String
                    : null,
                sourceRowRect: element.kind == PlannedSetlistElementKind.strip
                    ? NormalizedRect.fromJson(
                        (processedByEntry[element.entryIndex]![element
                                    .rowIndex!]['sourceRowRect']!
                                as Map)
                            .cast<String, Object?>(),
                      )
                    : null,
                title: element.kind == PlannedSetlistElementKind.placeholder
                    ? placeholdersByEntry[element.entryIndex]
                    : draftsByEntry[element.entryIndex] == null
                    ? null
                    : _displayDraftTitle(draftsByEntry[element.entryIndex]!),
                artist: draftsByEntry[element.entryIndex]?.artist.trim(),
                rowIndex: element.rowIndex,
                width: element.width,
                height: element.height,
                imageBytes: element.kind == PlannedSetlistElementKind.strip
                    ? processedByEntry[element.entryIndex]![element
                              .rowIndex!]['bytes']!
                          as Uint8List
                    : null,
                annotations: element.kind == PlannedSetlistElementKind.strip
                    ? List.unmodifiable(
                        (processedByEntry[element.entryIndex]![element
                                    .rowIndex!]['annotations']!
                                as List)
                            .map(
                              (value) => VisualAnnotationStroke.fromJson(
                                (value as Map).cast<String, Object?>(),
                              ),
                            ),
                      )
                    : const [],
                annotationsVisible:
                    element.kind != PlannedSetlistElementKind.strip ||
                    (processedByEntry[element.entryIndex]![element
                            .rowIndex!]['annotationsVisible']!
                        as bool),
                includeAnnotationsInPdf:
                    element.kind == PlannedSetlistElementKind.strip &&
                    (processedByEntry[element.entryIndex]![element
                            .rowIndex!]['includeAnnotationsInPdf']!
                        as bool),
              ),
          ]),
        ),
    ]),
  ).toMessage();
}

Future<Uint8List> _renderPerformanceDeckPdf(PerformanceDeck deck) async {
  final document = pw.Document(
    title: deck.setlistName,
    creator: 'Music Tabbler',
  );
  for (final page in deck.pages) {
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(deck.pageWidth, deck.pageHeight),
        margin: pw.EdgeInsets.all(deck.margin),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (
              var elementIndex = 0;
              elementIndex < page.elements.length;
              elementIndex += 1
            ) ...[
              if (elementIndex > 0) pw.SizedBox(height: deck.gap),
              _buildPerformanceDeckPdfElement(page.elements[elementIndex]),
            ],
          ],
        ),
      ),
    );
  }
  return Uint8List.fromList(await document.save());
}

pw.Widget _buildPerformanceDeckPdfElement(PerformanceDeckElement element) {
  return switch (element.kind) {
    PerformanceElementKind.header => pw.SizedBox(
      width: element.width,
      height: element.height,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.FittedBox(
              alignment: pw.Alignment.centerLeft,
              fit: pw.BoxFit.scaleDown,
              child: pw.Text(
                element.title ?? 'Untitled chart',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ),
          if ((element.artist ?? '').isNotEmpty)
            pw.SizedBox(
              height: 9,
              child: pw.FittedBox(
                alignment: pw.Alignment.centerLeft,
                fit: pw.BoxFit.scaleDown,
                child: pw.Text(
                  element.artist!,
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
            ),
        ],
      ),
    ),
    PerformanceElementKind.boundary => pw.SizedBox(
      width: element.width,
      height: element.height,
      child: pw.Container(
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            top: pw.BorderSide(width: 0.5, color: PdfColors.grey700),
          ),
        ),
      ),
    ),
    PerformanceElementKind.placeholder => pw.SizedBox(
      width: element.width,
      height: element.height,
      child: pw.Container(
        color: const PdfColor(1, 0.8, 0.82),
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        alignment: pw.Alignment.centerLeft,
        child: pw.Text(
          'Not playing - ${element.title}',
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
      ),
    ),
    PerformanceElementKind.strip => pw.Align(
      alignment: pw.Alignment.centerLeft,
      child: pw.SizedBox(
        width: element.width,
        height: element.height,
        child: pw.Image(
          pw.MemoryImage(_imageBytesForPerformancePdf(element)),
          // Source pixels remain immutable; PDF inclusion is flattened only
          // into this generated output image.
          fit: pw.BoxFit.fill,
        ),
      ),
    ),
  };
}

List<Map<String, Object>> _processDraftForSetlist(
  VisualChartDraft draft,
  Map<String, String> assetPaths, {
  required double splitDetectedRowsBelowAspectRatio,
}) {
  final grouped = <String, List<(int, VisualStrip)>>{};
  for (var index = 0; index < draft.strips.length; index += 1) {
    final strip = draft.strips[index];
    final key = '${strip.assetHash}.${strip.assetExtension}';
    grouped.putIfAbsent(key, () => []).add((index, strip));
  }
  final processed = <Map<String, Object>>[];
  for (final entry in grouped.entries) {
    final path = assetPaths[entry.key];
    if (path == null) {
      throw StateError('The source asset for ${entry.key} is unavailable.');
    }
    final batches = const VisualImageProcessor().processForExportBatch(
      File(path).readAsBytesSync(),
      [for (final item in entry.value) item.$2],
      globalTreatment: draft.globalTreatment,
      splitDetectedRowsBelowAspectRatio: splitDetectedRowsBelowAspectRatio,
    );
    for (var stripIndex = 0; stripIndex < batches.length; stripIndex += 1) {
      for (
        var rowIndex = 0;
        rowIndex < batches[stripIndex].length;
        rowIndex += 1
      ) {
        processed.add({
          'stripIndex': entry.value[stripIndex].$1,
          'rowIndex': rowIndex,
          'bytes': batches[stripIndex][rowIndex].bytes,
          'aspectRatio': batches[stripIndex][rowIndex].aspectRatio,
          'annotations': [
            for (final stroke in _annotationsForRow(
              entry.value[stripIndex].$2.annotations,
              batches[stripIndex][rowIndex].sourceRect,
            ))
              stroke.toJson(),
          ],
          'includeAnnotationsInPdf':
              entry.value[stripIndex].$2.includeAnnotationsInPdf,
          'annotationsVisible': entry.value[stripIndex].$2.annotationsVisible,
          'sourceStripId': entry.value[stripIndex].$2.id,
          'sourceRowRect': batches[stripIndex][rowIndex].sourceRect.toJson(),
        });
      }
    }
  }
  processed.sort((left, right) {
    final stripOrder = (left['stripIndex']! as int).compareTo(
      right['stripIndex']! as int,
    );
    return stripOrder != 0
        ? stripOrder
        : (left['rowIndex']! as int).compareTo(right['rowIndex']! as int);
  });
  return List.unmodifiable(processed);
}

List<VisualAnnotationStroke> _annotationsForRow(
  List<VisualAnnotationStroke> annotations,
  NormalizedRect row,
) {
  final mapped = <VisualAnnotationStroke>[];
  for (final stroke in annotations) {
    final points = <NormalizedPoint>[];
    for (final point in stroke.points) {
      if (point.y < row.top || point.y > row.bottom) continue;
      points.add(
        NormalizedPoint(point.x, (point.y - row.top) / row.height).clamp(),
      );
    }
    if (points.length < 2) continue;
    mapped.add(
      VisualAnnotationStroke(
        id: stroke.id,
        points: List.unmodifiable(points),
        colorArgb: stroke.colorArgb,
        width: stroke.width,
      ),
    );
  }
  return List.unmodifiable(mapped);
}

Uint8List _imageBytesForPdf(Map<String, Object> processed) {
  final annotations = ((processed['annotations'] as List?) ?? const [])
      .map(
        (value) => VisualAnnotationStroke.fromJson(
          (value as Map).cast<String, Object?>(),
        ),
      )
      .toList(growable: false);
  return flattenVisualAnnotations(
    processed['bytes']! as Uint8List,
    annotations,
    include: processed['includeAnnotationsInPdf'] as bool? ?? false,
  );
}

Uint8List _imageBytesForPerformancePdf(PerformanceDeckElement element) {
  return flattenVisualAnnotations(
    element.imageBytes!,
    element.annotations,
    include: element.includeAnnotationsInPdf,
  );
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
