import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/application/pdf_export_service.dart';

void main() {
  test(
    'A4 layout stacks strips in one column and adds a page before overflow',
    () {
      const layout = A4StripLayout();

      final pages = layout.plan(List.filled(6, 4.0));

      expect(pages, hasLength(2));
      expect(pages.first.strips, hasLength(5));
      expect(pages.last.strips, hasLength(1));
      expect(pages.first.headerHeight, 24);
      expect(pages.last.headerHeight, 0);
      expect(
        pages.expand((page) => page.strips).map((strip) => strip.index),
        orderedEquals([0, 1, 2, 3, 4, 5]),
      );
    },
  );

  test('an A4-shaped source page is reduced only enough to fit one page', () {
    const layout = A4StripLayout();

    final pages = layout.plan([595.28 / 841.89]);
    final strip = pages.single.strips.single;

    expect(strip.height, lessThanOrEqualTo(841.89 - 10 - 24));
    expect(strip.width / strip.height, closeTo(595.28 / 841.89, 0.0001));
  });

  test('hidden header reserves no space on any page', () {
    const layout = A4StripLayout();
    final pages = layout.plan(
      List.filled(6, 4.0),
      includeFirstPageHeader: false,
    );
    expect(pages.every((page) => page.headerHeight == 0), isTrue);
  });

  test('default A4 layout leaves no artificial gap between tab rows', () {
    const layout = A4StripLayout();

    expect(layout.gap, 0);
    expect(layout.margin, lessThanOrEqualTo(5));
  });

  test('readability floor rejects rows instead of stretching or clipping', () {
    const layout = A4StripLayout(minimumRowHeight: 60);

    expect(
      () => layout.plan([20]),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('below the 60 pt minimum'),
        ),
      ),
    );
  });

  test('readability floor permits a narrow real-world tolerance band', () {
    const layout = A4StripLayout(minimumRowHeight: 48);

    final pages = layout.plan([12.8]);

    expect(pages.single.strips.single.height, closeTo(45.73, 0.1));
  });

  test('every setlist song occurrence starts on a fresh page', () {
    final layout = SetlistA4Layout.fromStripLayout(const A4StripLayout());

    final pages = layout.plan(const [
      SetlistLayoutEntry.chart(
        entryIndex: 0,
        aspectRatios: [4],
        showHeader: true,
      ),
      SetlistLayoutEntry.chart(
        entryIndex: 1,
        aspectRatios: [4],
        showHeader: true,
      ),
      SetlistLayoutEntry.chart(
        entryIndex: 2,
        aspectRatios: [4],
        showHeader: true,
      ),
    ]);

    expect(pages, hasLength(3));
    expect(
      pages.map((page) => page.elements.first.entryIndex),
      orderedEquals([0, 1, 2]),
    );
    expect(
      pages.expand((page) => page.elements).map((element) => element.kind),
      everyElement(
        anyOf(
          PlannedSetlistElementKind.header,
          PlannedSetlistElementKind.strip,
        ),
      ),
    );
  });

  test('setlist header moves with its first row instead of being orphaned', () {
    final layout = SetlistA4Layout.fromStripLayout(const A4StripLayout());

    final pages = layout.plan(const [
      SetlistLayoutEntry.chart(
        entryIndex: 0,
        aspectRatios: [0.7],
        showHeader: true,
      ),
      SetlistLayoutEntry.chart(
        entryIndex: 1,
        aspectRatios: [4],
        showHeader: true,
      ),
    ]);

    expect(pages, hasLength(2));
    expect(pages.last.elements.map((element) => element.entryIndex).toSet(), {
      1,
    });
    expect(pages.last.elements.first.kind, PlannedSetlistElementKind.header);
    expect(pages.last.elements[1].kind, PlannedSetlistElementKind.strip);
  });

  test('setlist header appears once when one song spans several pages', () {
    final layout = SetlistA4Layout.fromStripLayout(const A4StripLayout());

    final pages = layout.plan([
      SetlistLayoutEntry.chart(
        entryIndex: 0,
        aspectRatios: List.filled(8, 2),
        showHeader: true,
      ),
    ]);

    expect(pages.length, greaterThan(1));
    expect(
      pages
          .expand((page) => page.elements)
          .where((element) => element.kind == PlannedSetlistElementKind.header),
      hasLength(1),
    );
  });

  test('hidden headers and placeholders retain exact setlist order', () {
    final layout = SetlistA4Layout.fromStripLayout(const A4StripLayout());

    final pages = layout.plan(const [
      SetlistLayoutEntry.chart(
        entryIndex: 0,
        aspectRatios: [4],
        showHeader: false,
      ),
      SetlistLayoutEntry.placeholder(entryIndex: 1),
      SetlistLayoutEntry.chart(
        entryIndex: 2,
        aspectRatios: [4],
        showHeader: true,
      ),
    ]);
    final elements = pages.expand((page) => page.elements).toList();

    expect(elements.map((element) => element.entryIndex), [0, 0, 1, 2, 2]);
    expect(elements.first.kind, PlannedSetlistElementKind.boundary);
    expect(elements[2].kind, PlannedSetlistElementKind.placeholder);
    expect(elements[3].kind, PlannedSetlistElementKind.header);
    expect(pages, hasLength(3));
    expect(
      pages[1].elements.single.kind,
      PlannedSetlistElementKind.placeholder,
    );
    expect(pages[1].elements.single.entryIndex, 1);
  });

  test('common metadata punctuation has a built-in PDF-safe fallback', () {
    expect(
      pdfSafeMetadata('Bass Guitar â€” finger… “stage”'),
      'Bass Guitar - finger... "stage"',
    );
  });

  test('setlist readability errors name the set item and row', () {
    const layout = SetlistA4Layout(
      pageWidth: 595.28,
      pageHeight: 841.89,
      margin: 5,
      songHeaderHeight: 24,
      minimumRowHeight: 60,
    );

    expect(
      () => layout.plan(const [
        SetlistLayoutEntry.chart(
          entryIndex: 3,
          aspectRatios: [20],
          showHeader: true,
        ),
      ]),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(contains('Set item 4'), contains('row 1')),
        ),
      ),
    );
  });

  test('setlist readability floor permits a narrow tolerance band', () {
    const layout = SetlistA4Layout(
      pageWidth: 841.89,
      pageHeight: 595.28,
      margin: 5,
      songHeaderHeight: 24,
      minimumRowHeight: 48,
    );

    final pages = layout.plan(const [
      SetlistLayoutEntry.chart(
        entryIndex: 0,
        aspectRatios: [18.15],
        showHeader: true,
      ),
    ]);
    final row = pages.single.elements.singleWhere(
      (element) => element.kind == PlannedSetlistElementKind.strip,
    );

    expect(row.height, closeTo(45.83, 0.1));
  });

  test(
    'density floor permits compacting a song to avoid a sparse tail page',
    () {
      const layout = SetlistA4Layout(
        pageWidth: 595.28,
        pageHeight: 260,
        margin: 5,
        songHeaderHeight: 24,
        minimumRowHeight: 34,
      );

      final pages = layout.plan(const [
        SetlistLayoutEntry.chart(
          entryIndex: 0,
          aspectRatios: [6, 6, 6],
          showHeader: true,
        ),
      ]);

      expect(pages, hasLength(1));
      final rows = pages.single.elements.where(
        (element) => element.kind == PlannedSetlistElementKind.strip,
      );
      expect(rows, hasLength(3));
      expect(rows.every((row) => row.height >= 34 * 0.9), isTrue);
    },
  );
}
