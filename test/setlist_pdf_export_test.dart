import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:music_tabbler/application/pdf_export_service.dart';
import 'package:music_tabbler/application/performance_deck.dart';
import 'package:music_tabbler/application/service_contracts.dart';
import 'package:music_tabbler/application/visual_import_service.dart';
import 'package:music_tabbler/domain/library_models.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';
import 'package:music_tabbler/infrastructure/local_library.dart';

void main() {
  test(
    'combined setlist PDF preserves duplicates and renders placeholders',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'music_tabbler_setlist_pdf_',
      );
      final library = await LocalLibrary.forTesting(directory);
      addTearDown(() {
        library.close();
        directory.deleteSync(recursive: true);
      });
      final first = await _saveChart(
        library,
        id: 'first',
        title: 'First Song',
        artist: 'First Artist',
        showHeader: true,
      );
      final second = await _saveChart(
        library,
        id: 'second',
        title: 'Second Song',
        artist: 'Second Artist',
        showHeader: false,
      );
      final now = DateTime.utc(2026, 7, 23);
      final setlist = LibrarySetlist(
        id: 'gig',
        name: 'August gig',
        createdAt: now,
        updatedAt: now,
        entries: [
          LibrarySetlistEntry(id: 'one', chartVariantId: first.id),
          const LibrarySetlistEntry.placeholder(
            id: 'placeholder',
            title: 'Singer feature',
          ),
          LibrarySetlistEntry(id: 'two', chartVariantId: second.id),
          LibrarySetlistEntry(id: 'repeat', chartVariantId: first.id),
        ],
      );

      final deckBuilder = CachedPerformanceDeckBuilder(library);
      final exporter = SetlistPdfExportService(deckBuilder);
      final deck = await deckBuilder.buildPerformanceDeck(
        setlist,
        density: VisualExportDensity.stageReadable,
      );
      final bytes = await exporter.exportSetlistBytes(
        setlist,
        density: VisualExportDensity.stageReadable,
      );

      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(1000));
      expect(
        latin1.decode(bytes, allowInvalid: true),
        contains('/MediaBox[0 0 841.89 595.28]'),
      );
      final pages = await VisualImportService(library).importPdf(bytes);
      expect(pages, isNotEmpty);
      var redPixels = 0;
      for (final page in pages) {
        final rendered = img.decodePng(
          await File(
            library.assetPath(page.assetHash, page.assetExtension),
          ).readAsBytes(),
        )!;
        for (final pixel in rendered) {
          if (pixel.r > 225 &&
              pixel.g > 150 &&
              pixel.g < 235 &&
              pixel.b > 160 &&
              pixel.r > pixel.g + 15) {
            redPixels += 1;
          }
        }
      }
      expect(redPixels, greaterThan(100));
      expect(deck.pages, isNotEmpty);
      expect(
        deck.pages
            .expand((page) => page.elements)
            .map((element) => element.entryId)
            .toSet(),
        {'one', 'placeholder', 'two', 'repeat'},
      );
      expect(
        deck.pages
            .expand((page) => page.elements)
            .where((element) => element.kind == PerformanceElementKind.header)
            .map((element) => element.entryId),
        orderedEquals(['one', 'repeat']),
      );

      final outputPath =
          Platform.environment['MUSIC_TABBLER_SETLIST_VISUAL_OUTPUT'];
      if (outputPath != null) {
        await File(outputPath).writeAsBytes(bytes, flush: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('setlist export names missing and empty chart failures', () async {
    final directory = await Directory.systemTemp.createTemp(
      'music_tabbler_setlist_pdf_errors_',
    );
    final library = await LocalLibrary.forTesting(directory);
    addTearDown(() {
      library.close();
      directory.deleteSync(recursive: true);
    });
    final now = DateTime.utc(2026, 7, 23);
    final exporter = SetlistPdfExportService(
      CachedPerformanceDeckBuilder(library),
    );

    await expectLater(
      exporter.exportSetlistBytes(
        LibrarySetlist(
          id: 'empty-set',
          name: 'Empty',
          createdAt: now,
          updatedAt: now,
        ),
        density: VisualExportDensity.original,
      ),
      throwsA(
        isA<SetlistPdfExportException>().having(
          (error) => error.message,
          'message',
          contains('Add at least one song or placeholder'),
        ),
      ),
    );

    await expectLater(
      exporter.exportSetlistBytes(
        LibrarySetlist(
          id: 'missing-set',
          name: 'Missing',
          createdAt: now,
          updatedAt: now,
          entries: const [
            LibrarySetlistEntry(id: 'missing', chartVariantId: 'gone'),
          ],
        ),
        density: VisualExportDensity.original,
      ),
      throwsA(
        isA<SetlistPdfExportException>().having(
          (error) => error.message,
          'message',
          allOf(contains('Set item 1'), contains('no longer available')),
        ),
      ),
    );

    final emptyChart = VisualChartDraft(
      id: 'empty-chart',
      title: 'No rows',
      artist: '',
      createdAt: now,
      updatedAt: now,
    );
    await library.saveDraft(emptyChart);
    await expectLater(
      exporter.exportSetlistBytes(
        LibrarySetlist(
          id: 'empty-chart-set',
          name: 'Empty chart',
          createdAt: now,
          updatedAt: now,
          entries: const [
            LibrarySetlistEntry(
              id: 'empty-chart-entry',
              chartVariantId: 'empty-chart',
            ),
          ],
        ),
        density: VisualExportDensity.original,
      ),
      throwsA(
        isA<SetlistPdfExportException>().having(
          (error) => error.message,
          'message',
          allOf(contains('Set item 1'), contains('"No rows"')),
        ),
      ),
    );

    final brokenChart = VisualChartDraft(
      id: 'broken-chart',
      title: 'Broken source',
      artist: '',
      createdAt: now,
      updatedAt: now,
      strips: const [
        VisualStrip(
          id: 'missing-strip',
          assetHash: 'missing',
          assetExtension: 'png',
          pixelWidth: 800,
          pixelHeight: 100,
        ),
      ],
    );
    await library.saveDraft(brokenChart);
    await expectLater(
      exporter.exportSetlistBytes(
        LibrarySetlist(
          id: 'broken-chart-set',
          name: 'Broken chart',
          createdAt: now,
          updatedAt: now,
          entries: const [
            LibrarySetlistEntry(
              id: 'broken-chart-entry',
              chartVariantId: 'broken-chart',
            ),
          ],
        ),
        density: VisualExportDensity.original,
      ),
      throwsA(
        isA<SetlistPdfExportException>().having(
          (error) => error.message,
          'message',
          allOf(contains('Set item 1'), contains('"Broken source"')),
        ),
      ),
    );
  });

  test('performance decks are reused until chart content changes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'music_tabbler_performance_cache_',
    );
    final library = await LocalLibrary.forTesting(directory);
    addTearDown(() {
      library.close();
      directory.deleteSync(recursive: true);
    });
    final chart = await _saveChart(
      library,
      id: 'cached-chart',
      title: 'Cached song',
      artist: 'Artist',
      showHeader: true,
    );
    final now = DateTime.utc(2026, 7, 29);
    final setlist = LibrarySetlist(
      id: 'cached-set',
      name: 'Cached gig',
      createdAt: now,
      updatedAt: now,
      entries: [LibrarySetlistEntry(id: 'entry', chartVariantId: chart.id)],
    );
    final exporter = CachedPerformanceDeckBuilder(library);

    final first = await exporter.buildPerformanceDeck(
      setlist,
      density: VisualExportDensity.stageReadable,
    );
    final second = await exporter.buildPerformanceDeck(
      setlist,
      density: VisualExportDensity.stageReadable,
    );

    expect(identical(second, first), isTrue);

    await library.saveDraft(
      chart.copyWith(
        artist: 'Changed artist',
        updatedAt: now.add(const Duration(seconds: 1)),
      ),
    );
    final changed = await exporter.buildPerformanceDeck(
      setlist,
      density: VisualExportDensity.stageReadable,
    );

    expect(identical(changed, first), isFalse);
    expect(
      changed.pages
          .expand((page) => page.elements)
          .where((element) => element.kind == PerformanceElementKind.header)
          .single
          .artist,
      'Changed artist',
    );
  });

  test('one setlist density controls every A4 page orientation', () async {
    final directory = await Directory.systemTemp.createTemp(
      'music_tabbler_setlist_pdf_density_',
    );
    final library = await LocalLibrary.forTesting(directory);
    addTearDown(() {
      library.close();
      directory.deleteSync(recursive: true);
    });
    final now = DateTime.utc(2026, 7, 23);
    final setlist = LibrarySetlist(
      id: 'placeholder-set',
      name: 'Band order',
      createdAt: now,
      updatedAt: now,
      entries: const [
        LibrarySetlistEntry.placeholder(
          id: 'placeholder',
          title: 'Not my song',
        ),
      ],
    );
    final exporter = SetlistPdfExportService(
      CachedPerformanceDeckBuilder(library),
    );

    for (final density in VisualExportDensity.values) {
      final text = latin1.decode(
        await exporter.exportSetlistBytes(setlist, density: density),
        allowInvalid: true,
      );
      final mediaBox = density == VisualExportDensity.stageReadable
          ? '/MediaBox[0 0 841.89 595.28]'
          : '/MediaBox[0 0 595.28 841.89]';
      expect(text, contains(mediaBox), reason: density.name);
    }
  });

  test(
    'staged PDF writer replaces a destination and cleans sidecars',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'music_tabbler_staged_pdf_',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final destination = File(
        '${directory.path}${Platform.pathSeparator}set.pdf',
      );
      await destination.writeAsBytes([9, 9, 9], flush: true);
      final expected = Uint8List.fromList([1, 2, 3, 4, 5]);

      await const StagedPdfFileWriter().write(destination.path, expected);

      expect(await destination.readAsBytes(), expected);
      expect(
        directory.listSync().where(
          (entry) =>
              entry.path.endsWith('.partial') ||
              entry.path.endsWith('.previous'),
        ),
        isEmpty,
      );
    },
  );
}

Future<VisualChartDraft> _saveChart(
  LocalLibrary library, {
  required String id,
  required String title,
  required String artist,
  required bool showHeader,
}) async {
  final source = img.Image(width: 800, height: 100);
  img.fill(source, color: img.ColorRgb8(250, 250, 250));
  for (var y = 18; y <= 70; y += 13) {
    img.drawLine(
      source,
      x1: 20,
      y1: y,
      x2: 780,
      y2: y,
      color: img.ColorRgb8(30, 30, 30),
      thickness: 2,
    );
  }
  final stored = await library.storeAsset(img.encodePng(source), 'png');
  final now = DateTime.utc(2026, 7, 23);
  final draft = VisualChartDraft(
    id: id,
    title: title,
    artist: artist,
    createdAt: now,
    updatedAt: now,
    showHeader: showHeader,
    strips: [
      VisualStrip(
        id: '$id-strip',
        assetHash: stored.hash,
        assetExtension: stored.extension,
        pixelWidth: source.width,
        pixelHeight: source.height,
      ),
    ],
  );
  await library.saveDraft(draft);
  return draft;
}
