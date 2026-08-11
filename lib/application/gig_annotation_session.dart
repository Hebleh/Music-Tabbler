import '../domain/visual_chart_models.dart';
import 'library_contracts.dart';
import 'performance_deck.dart';

class GigAnnotationUpdate {
  const GigAnnotationUpdate({required this.draft, required this.deck});

  final VisualChartDraft draft;
  final PerformanceDeck? deck;
}

/// Owns Gig annotation persistence, deck patching, and one-step undo identity.
class GigAnnotationSession {
  GigAnnotationSession({required this.library, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final ChartLibrary library;
  final DateTime Function() _clock;
  _AnnotationUndo? _lastUndo;

  void rememberStroke(
    PerformanceDeckElement element,
    VisualAnnotationStroke stroke,
  ) {
    final variantId = element.chartVariantId;
    final stripId = element.sourceStripId;
    if (variantId == null || stripId == null) return;
    _lastUndo = _AnnotationUndo(
      chartVariantId: variantId,
      stripId: stripId,
      stroke: stroke,
    );
  }

  void clearUndo() => _lastUndo = null;

  PerformanceDeckElement? undoElementForPage(
    List<PerformanceDeckElement> elements,
  ) {
    final undo = _lastUndo;
    if (undo == null) return null;
    for (final element in elements) {
      if (element.chartVariantId == undo.chartVariantId &&
          element.sourceStripId == undo.stripId) {
        return element;
      }
    }
    return null;
  }

  Future<GigAnnotationUpdate?> save({
    required PerformanceDeckElement element,
    required Map<String, VisualChartDraft> draftsByVariant,
    required PerformanceDeck? deck,
    required VisualStrip Function(VisualStrip strip) updateStrip,
    required PerformanceDeckElement Function(PerformanceDeckElement element)
    patchElement,
  }) async {
    final variantId = element.chartVariantId;
    final stripId = element.sourceStripId;
    if (variantId == null || stripId == null) return null;
    final draft =
        draftsByVariant[variantId] ?? await library.loadDraft(variantId);
    if (draft == null) return null;
    final updated = draft.copyWith(
      strips: [
        for (final strip in draft.strips)
          if (strip.id == stripId) updateStrip(strip) else strip,
      ],
      updatedAt: _clock().toUtc(),
    );
    await library.saveDraft(updated);
    final patchedDeck = deck?.copyWith(
      pages: [
        for (final page in deck.pages)
          PerformanceDeckPage(
            id: page.id,
            index: page.index,
            elements: [
              for (final deckElement in page.elements)
                if (deckElement.chartVariantId == variantId &&
                    deckElement.sourceStripId == stripId)
                  patchElement(deckElement)
                else
                  deckElement,
            ],
          ),
      ],
    );
    return GigAnnotationUpdate(draft: updated, deck: patchedDeck);
  }

  Future<GigAnnotationUpdate?> undo({
    required PerformanceDeckElement element,
    required Map<String, VisualChartDraft> draftsByVariant,
    required PerformanceDeck? deck,
  }) async {
    final undo = _lastUndo;
    if (undo == null ||
        undo.chartVariantId != element.chartVariantId ||
        undo.stripId != element.sourceStripId) {
      return null;
    }
    final result = await save(
      element: element,
      draftsByVariant: draftsByVariant,
      deck: deck,
      updateStrip: (strip) => strip.copyWith(
        annotations: strip.annotations
            .where((stroke) => stroke.id != undo.stroke.id)
            .toList(growable: false),
      ),
      patchElement: (deckElement) => deckElement.copyWith(
        annotations: deckElement.annotations
            .where((stroke) => stroke.id != undo.stroke.id)
            .toList(growable: false),
      ),
    );
    if (result != null) _lastUndo = null;
    return result;
  }
}

class _AnnotationUndo {
  const _AnnotationUndo({
    required this.chartVariantId,
    required this.stripId,
    required this.stroke,
  });

  final String chartVariantId;
  final String stripId;
  final VisualAnnotationStroke stroke;
}
