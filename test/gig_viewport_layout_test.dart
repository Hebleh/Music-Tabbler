import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/application/gig_viewport_layout.dart';
import 'package:music_tabbler/application/performance_deck.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';

void main() {
  PerformanceDeck deckWithRows(List<(String, int)> entries) {
    var pageIndex = 0;
    return PerformanceDeck(
      setlistId: 'set',
      setlistName: 'Gig',
      density: VisualExportDensity.stageReadable,
      pageWidth: 840,
      pageHeight: 595,
      margin: 5,
      gap: 4,
      pages: [
        for (final entry in entries)
          PerformanceDeckPage(
            id: 'page-${pageIndex++}',
            index: pageIndex - 1,
            elements: [
              for (var row = 0; row < entry.$2; row += 1)
                PerformanceDeckElement(
                  kind: PerformanceElementKind.strip,
                  entryIndex: pageIndex - 1,
                  entryId: entry.$1,
                  width: 400,
                  height: 100,
                  title: 'Title ${entry.$1}',
                  artist: 'Artist ${entry.$1}',
                  sourceStripId: '${entry.$1}-strip-$row',
                  rowIndex: row,
                  imageBytes: Uint8List(0),
                ),
            ],
          ),
      ],
    );
  }

  test('zooming out fits more rows and packs rows beside each other', () {
    final deck = deckWithRows([('song-a', 8)]);
    const layout = GigViewportLayout();

    final compact = layout.plan(
      deck: deck,
      viewportWidth: 600,
      viewportHeight: 240,
      zoom: 0.45,
    );
    final large = layout.plan(
      deck: deck,
      viewportWidth: 600,
      viewportHeight: 240,
      zoom: 1.5,
    );

    expect(compact.length, lessThan(large.length));
    expect(compact.first.items.any((item) => item.left > 0), isTrue);
    for (final page in compact) {
      for (final item in page.items) {
        expect(item.left + item.width, lessThanOrEqualTo(600.01));
        expect(item.top + item.height, lessThanOrEqualTo(240.01));
      }
    }
  });

  test('each setlist entry starts on a fresh gig screen', () {
    final pages = const GigViewportLayout().plan(
      deck: deckWithRows([('song-a', 2), ('song-b', 2)]),
      viewportWidth: 1200,
      viewportHeight: 800,
      zoom: 0.45,
    );

    expect(pages, hasLength(2));
    expect(pages[0].entryId, 'song-a');
    expect(pages[1].entryId, 'song-b');
    expect(
      pages.every(
        (page) =>
            page.items.every((item) => item.element.entryId == page.entryId),
      ),
      isTrue,
    );
  });

  test('every packed strip line is horizontally centered', () {
    final pages = const GigViewportLayout().plan(
      deck: deckWithRows([('song-a', 5)]),
      viewportWidth: 600,
      viewportHeight: 400,
      zoom: 0.45,
    );

    final strips = pages.first.items
        .where((item) => item.element.kind == PerformanceElementKind.strip)
        .toList();
    final lines = <double, List<GigViewportItem>>{};
    for (final item in strips) {
      lines.putIfAbsent(item.top, () => []).add(item);
    }
    for (final line in lines.values) {
      final left = line.first.left;
      final right = 600 - (line.last.left + line.last.width);
      expect(left, closeTo(right, 0.01));
    }
  });

  test('gig planner adds a compact title when PDF headers are disabled', () {
    final pages = const GigViewportLayout().plan(
      deck: deckWithRows([('song-a', 1)]),
      viewportWidth: 600,
      viewportHeight: 400,
      zoom: 0.75,
    );

    expect(
      pages.single.items.first.element.kind,
      PerformanceElementKind.header,
    );
    expect(pages.single.items.first.element.title, 'Title song-a');
  });

  test(
    'sidebar entry lookup uses reflowed gig pages, not PDF page indices',
    () {
      final deck = deckWithRows([('song-a', 12), ('song-b', 1)]);
      final pages = const GigViewportLayout().plan(
        deck: deck,
        viewportWidth: 600,
        viewportHeight: 150,
        zoom: 0.75,
      );

      final target = gigPageIndexForEntry(pages, 'song-b');
      expect(target, greaterThan(1));
      expect(pages[target].entryId, 'song-b');
    },
  );

  test('zoom reflow keeps the visible strip anchored', () {
    const layout = GigViewportLayout();
    final deck = deckWithRows([('song-a', 12), ('song-b', 2)]);
    final before = layout.plan(
      deck: deck,
      viewportWidth: 600,
      viewportHeight: 240,
      zoom: 1.2,
    );
    final current = before.firstWhere(
      (page) => page.items.any(
        (item) => item.element.sourceStripId == 'song-a-strip-6',
      ),
    );
    final anchor = current.items
        .firstWhere((item) => item.element.kind == PerformanceElementKind.strip)
        .element;

    final after = layout.plan(
      deck: deck,
      viewportWidth: 600,
      viewportHeight: 240,
      zoom: 0.55,
    );
    final target = gigPageIndexForAnchor(
      after,
      entryId: current.entryId,
      sourceStripId: anchor.sourceStripId,
      rowIndex: anchor.rowIndex,
    );

    expect(target, isNonNegative);
    expect(after[target].entryId, current.entryId);
    expect(
      after[target].items.any(
        (item) => item.element.sourceStripId == anchor.sourceStripId,
      ),
      isTrue,
    );
  });
}
