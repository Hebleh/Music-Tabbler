import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/application/performance_deck.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';

void main() {
  test(
    'performance deck message round-trip preserves page identity and bytes',
    () {
      final deck = PerformanceDeck(
        setlistId: 'gig',
        setlistName: 'August gig',
        density: VisualExportDensity.stageReadable,
        pageWidth: 841.89,
        pageHeight: 595.28,
        margin: 5,
        gap: 0,
        pages: [
          PerformanceDeckPage(
            id: 'gig:stageReadable:0',
            index: 0,
            elements: [
              PerformanceDeckElement(
                kind: PerformanceElementKind.strip,
                entryIndex: 1,
                entryId: 'repeat-entry',
                chartVariantId: 'chart-one',
                rowIndex: 2,
                width: 800,
                height: 60,
                imageBytes: Uint8List.fromList([1, 2, 3]),
              ),
            ],
          ),
        ],
      );

      final restored = PerformanceDeck.fromMessage(deck.toMessage());

      expect(restored.setlistId, 'gig');
      expect(restored.density, VisualExportDensity.stageReadable);
      expect(restored.pages.single.id, 'gig:stageReadable:0');
      expect(restored.pages.single.elements.single.entryId, 'repeat-entry');
      expect(restored.pages.single.elements.single.imageBytes, [1, 2, 3]);
    },
  );

  test('cursor advances and retreats without leaving the deck', () {
    const start = PerformanceDeckCursor(pageCount: 3);

    expect(start.retreat(), same(start));
    final last = start.advance().advance();
    expect(last.pageIndex, 2);
    expect(last.canAdvance, isFalse);
    expect(last.advance(), same(last));
    expect(last.retreat().pageIndex, 1);
  });
}
