import 'dart:math' as math;

import 'performance_deck.dart';

class GigViewportItem {
  const GigViewportItem({
    required this.element,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final PerformanceDeckElement element;
  final double left;
  final double top;
  final double width;
  final double height;

  GigViewportItem shiftedHorizontally(double offset) => GigViewportItem(
    element: element,
    left: left + offset,
    top: top,
    width: width,
    height: height,
  );
}

class GigViewportPage {
  const GigViewportPage({
    required this.index,
    required this.entryId,
    required this.items,
  });

  final int index;
  final String entryId;
  final List<GigViewportItem> items;
}

int gigPageIndexForEntry(List<GigViewportPage> pages, String entryId) =>
    pages.indexWhere((page) => page.entryId == entryId);

int gigPageIndexForAnchor(
  List<GigViewportPage> pages, {
  required String entryId,
  String? sourceStripId,
  int? rowIndex,
}) {
  final exact = pages.indexWhere(
    (page) =>
        page.entryId == entryId &&
        page.items.any((item) {
          final element = item.element;
          if (sourceStripId != null) {
            return element.sourceStripId == sourceStripId;
          }
          return rowIndex != null && element.rowIndex == rowIndex;
        }),
  );
  return exact >= 0 ? exact : gigPageIndexForEntry(pages, entryId);
}

/// Reflows PDF-planned performance rows for the actual gig viewport.
///
/// The source deck remains the deterministic PDF/preview representation. This
/// planner only changes live placement: rows share a consistent target height,
/// wrap into adjacent columns when they fit, and each setlist entry starts on a
/// fresh screen.
class GigViewportLayout {
  const GigViewportLayout({
    this.horizontalGap = 8,
    this.verticalGap = 8,
    this.baseRowHeight = 72,
  });

  final double horizontalGap;
  final double verticalGap;
  final double baseRowHeight;

  List<GigViewportPage> plan({
    required PerformanceDeck deck,
    required double viewportWidth,
    required double viewportHeight,
    required double zoom,
  }) {
    if (viewportWidth <= 0 || viewportHeight <= 0) return const [];
    final elements = _flatten(deck);
    if (elements.isEmpty) return const [];
    final groups = <List<PerformanceDeckElement>>[];
    for (final element in elements) {
      if (groups.isEmpty || groups.last.first.entryId != element.entryId) {
        groups.add([element]);
      } else {
        groups.last.add(element);
      }
    }

    final pages = <GigViewportPage>[];
    for (final group in groups) {
      _planEntry(
        _withGigHeader(group),
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight,
        zoom: zoom.clamp(0.45, 2.0),
        output: pages,
      );
    }
    return List.unmodifiable([
      for (var index = 0; index < pages.length; index += 1)
        GigViewportPage(
          index: index,
          entryId: pages[index].entryId,
          items: pages[index].items,
        ),
    ]);
  }

  List<PerformanceDeckElement> _flatten(PerformanceDeck deck) => [
    for (final page in deck.pages)
      for (final element in page.elements) element,
  ];

  List<PerformanceDeckElement> _withGigHeader(
    List<PerformanceDeckElement> elements,
  ) {
    if (elements.isEmpty ||
        elements.first.kind == PerformanceElementKind.placeholder ||
        elements.any(
          (element) => element.kind == PerformanceElementKind.header,
        )) {
      return elements;
    }
    final first = elements.first;
    return [
      PerformanceDeckElement(
        kind: PerformanceElementKind.header,
        entryIndex: first.entryIndex,
        entryId: first.entryId,
        chartVariantId: first.chartVariantId,
        title: first.title,
        artist: first.artist,
        width: first.width,
        height: 30,
      ),
      ...elements,
    ];
  }

  void _planEntry(
    List<PerformanceDeckElement> elements, {
    required double viewportWidth,
    required double viewportHeight,
    required double zoom,
    required List<GigViewportPage> output,
  }) {
    var items = <GigViewportItem>[];
    var x = 0.0;
    var y = 0.0;
    var lineHeight = 0.0;
    var lineStart = 0;

    void centerLine() {
      if (lineHeight == 0) return;
      final usedWidth = math.max(0.0, x - horizontalGap);
      final offset = math.max(0.0, (viewportWidth - usedWidth) / 2);
      for (var index = lineStart; index < items.length; index += 1) {
        items[index] = items[index].shiftedHorizontally(offset);
      }
    }

    void finishLine() {
      if (lineHeight == 0) return;
      centerLine();
      x = 0;
      y += lineHeight + verticalGap;
      lineHeight = 0;
      lineStart = items.length;
    }

    void finishPage() {
      if (items.isEmpty) return;
      centerLine();
      output.add(
        GigViewportPage(
          index: output.length,
          entryId: elements.first.entryId,
          items: List.unmodifiable(items),
        ),
      );
      items = <GigViewportItem>[];
      x = 0;
      y = 0;
      lineHeight = 0;
      lineStart = 0;
    }

    for (final element in elements) {
      final fullWidth = element.kind != PerformanceElementKind.strip;
      if (fullWidth) finishLine();
      final size = _sizeFor(
        element,
        viewportWidth: viewportWidth,
        zoom: zoom,
        fullWidth: fullWidth,
      );

      if (!fullWidth && x > 0 && x + size.width > viewportWidth + 0.01) {
        finishLine();
      }
      if (y > 0 && y + size.height > viewportHeight + 0.01) {
        finishPage();
      }

      items.add(
        GigViewportItem(
          element: element,
          left: fullWidth ? 0 : x,
          top: y,
          width: size.width,
          height: size.height,
        ),
      );
      if (fullWidth) {
        y += size.height + verticalGap;
        lineStart = items.length;
      } else {
        x += size.width + horizontalGap;
        lineHeight = math.max(lineHeight, size.height);
      }
    }
    finishPage();
  }

  ({double width, double height}) _sizeFor(
    PerformanceDeckElement element, {
    required double viewportWidth,
    required double zoom,
    required bool fullWidth,
  }) {
    if (fullWidth) {
      final naturalHeight = switch (element.kind) {
        PerformanceElementKind.header => 44.0,
        PerformanceElementKind.placeholder => 40.0,
        PerformanceElementKind.boundary => 2.0,
        PerformanceElementKind.strip => baseRowHeight,
      };
      return (
        width: viewportWidth,
        height: element.kind == PerformanceElementKind.header
            ? naturalHeight
            : naturalHeight * zoom,
      );
    }
    final aspect = element.width / element.height;
    var height = baseRowHeight * zoom;
    var width = height * aspect;
    if (width > viewportWidth) {
      width = viewportWidth;
      height = width / aspect;
    }
    return (width: width, height: height);
  }
}
