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
}
