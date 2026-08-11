import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/application/gig_annotation_session.dart';
import 'package:music_tabbler/application/library_contracts.dart';
import 'package:music_tabbler/application/performance_deck.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';

void main() {
  test(
    'gig annotation session persists, patches the deck, and undoes',
    () async {
      final now = DateTime.utc(2026, 8, 11);
      final draft = VisualChartDraft(
      id: 'variant',
      title: 'Song',
      artist: 'Artist',
        createdAt: now,
        updatedAt: now,
        strips: const [
          VisualStrip(
            id: 'strip',
            assetHash: 'hash',
            assetExtension: 'png',
            pixelWidth: 100,
            pixelHeight: 20,
          ),
        ],
      );
      const stroke = VisualAnnotationStroke(
        id: 'stroke',
        points: [NormalizedPoint(0.2, 0.3), NormalizedPoint(0.4, 0.5)],
        colorArgb: 0xFFFFD740,
        width: 0.004,
      );
      const element = PerformanceDeckElement(
        kind: PerformanceElementKind.strip,
        entryIndex: 0,
        entryId: 'entry',
        chartVariantId: 'variant',
        sourceStripId: 'strip',
        width: 100,
        height: 20,
      );
      const deck = PerformanceDeck(
        setlistId: 'set',
        setlistName: 'Set',
        density: VisualExportDensity.original,
        pageWidth: 100,
        pageHeight: 100,
        margin: 0,
        gap: 0,
        pages: [
          PerformanceDeckPage(id: 'page', index: 0, elements: [element]),
        ],
      );
      final library = _ChartRepository(draft);
      final session = GigAnnotationSession(library: library, clock: () => now);
      session.rememberStroke(element, stroke);

      final added = await session.save(
        element: element,
        draftsByVariant: {'variant': draft},
        deck: deck,
        updateStrip: (strip) => strip.copyWith(annotations: [stroke]),
        patchElement: (element) => element.copyWith(annotations: [stroke]),
      );

      expect(added!.draft.strips.single.annotations, [stroke]);
      expect(added.deck!.pages.single.elements.single.annotations, [stroke]);
      expect(session.undoElementForPage(const [element]), element);

      final undone = await session.undo(
        element: element,
        draftsByVariant: {'variant': added.draft},
        deck: added.deck,
      );

      expect(undone!.draft.strips.single.annotations, isEmpty);
      expect(undone.deck!.pages.single.elements.single.annotations, isEmpty);
      expect(session.undoElementForPage(const [element]), isNull);
      expect(library.saved, same(undone.draft));
    },
  );
}

class _ChartRepository implements ChartLibrary {
  _ChartRepository(this.saved);

  VisualChartDraft saved;

  @override
  Future<VisualChartDraft?> loadDraft(String id) async => saved;

  @override
  Future<void> saveDraft(VisualChartDraft draft) async => saved = draft;

  @override
  String assetPath(String hash, String extension) => throw UnimplementedError();

  @override
  Future<void> deleteDraft(String id) => throw UnimplementedError();

  @override
  Future<void> deleteDraftAndRemoveSetlistReferences(
    String id, {
    required DateTime updatedAt,
  }) => throw UnimplementedError();

  @override
  Future<List<VisualChartDraft>> listDrafts() => throw UnimplementedError();

  @override
  Future<StoredAsset> storeAsset(List<int> bytes, String extension) =>
      throw UnimplementedError();
}
