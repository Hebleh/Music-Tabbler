import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/app_services.dart';
import '../../application/performance_deck.dart';
import '../../domain/device_preferences.dart';
import '../../domain/library_models.dart';
import '../../domain/visual_chart_models.dart';
import '../setlists/setlist_sidebar.dart';
import 'performance_preview_screen.dart';

class GigModeScreen extends StatefulWidget {
  const GigModeScreen({
    super.key,
    required this.services,
    required this.setlist,
    required this.density,
    required this.preferences,
  });

  final AppServices services;
  final LibrarySetlist setlist;
  final VisualExportDensity density;
  final DevicePreferences preferences;

  @override
  State<GigModeScreen> createState() => _GigModeScreenState();
}

class _GigModeScreenState extends State<GigModeScreen>
    with WidgetsBindingObserver {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late LibrarySetlist _setlist;
  late Future<PerformanceDeck> _deck;
  PerformanceDeck? _resolvedDeck;
  List<VisualChartDraft> _availableDrafts = const [];
  Map<String, VisualChartDraft> _draftsByVariant = const {};
  var _pageIndex = 0;
  var _allowExit = false;
  var _exiting = false;
  var _annotationTool = AnnotationTool.none;
  _AnnotationUndo? _lastAnnotation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setlist = widget.setlist;
    _deck = _buildDeck();
    unawaited(_loadDrafts());
    unawaited(widget.services.performanceMode.setActive(true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(
      widget.services.performanceMode.setActive(
        state == AppLifecycleState.resumed,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.services.performanceMode.setActive(false));
    super.dispose();
  }

  Future<PerformanceDeck> _buildDeck() async {
    final deck = await widget.services.performanceDeckBuilder
        .buildPerformanceDeck(_setlist, density: widget.density);
    _resolvedDeck = deck;
    return deck;
  }

  Future<void> _loadDrafts() async {
    final drafts = await widget.services.library.listDrafts();
    final byVariant = <String, VisualChartDraft>{};
    for (final draft in drafts) {
      final identity = await widget.services.songVariants.identityForDraft(
        draft.id,
      );
      if (identity != null) byVariant[identity.id] = draft;
    }
    if (!mounted) return;
    setState(() {
      _availableDrafts = drafts;
      _draftsByVariant = byVariant;
    });
  }

  Future<void> _saveEntries(
    List<LibrarySetlistEntry> entries, {
    String? keepEntryId,
  }) async {
    final updated = LibrarySetlist(
      id: _setlist.id,
      name: _setlist.name,
      createdAt: _setlist.createdAt,
      updatedAt: DateTime.now().toUtc(),
      scheduledAt: _setlist.scheduledAt,
      notes: _setlist.notes,
      entries: entries,
    );
    await widget.services.setlists.saveSetlist(updated);
    if (!mounted) return;
    setState(() {
      _setlist = updated;
      _pageIndex = 0;
      _deck = _buildDeck().then((deck) {
        if (keepEntryId != null) {
          final target = deck.pages.indexWhere(
            (page) =>
                page.elements.any((element) => element.entryId == keepEntryId),
          );
          if (target >= 0) _pageIndex = target;
        }
        return deck;
      });
    });
  }

  Future<void> _chooseSong() async {
    final selected = await showDialog<VisualChartDraft>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Add song from Song Pool'),
        children: _availableDrafts.isEmpty
            ? [
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No saved visual charts are available.'),
                ),
              ]
            : [
                for (final draft in _availableDrafts)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, draft),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(_displayTitle(draft)),
                    ),
                  ),
              ],
      ),
    );
    if (selected == null) return;
    final identity = await widget.services.songVariants.identityForDraft(
      selected.id,
    );
    if (identity == null || !mounted) return;
    final entry = LibrarySetlistEntry(
      id: IdFactory.next('entry'),
      chartVariantId: identity.id,
    );
    await _saveEntries([..._setlist.entries, entry], keepEntryId: entry.id);
  }

  Future<String?> _askPlaceholderName({String initial = ''}) async {
    var value = initial;
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(initial.isEmpty ? 'Add placeholder' : 'Edit placeholder'),
        content: TextFormField(
          initialValue: initial,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Song or set item name',
            helperText: 'Use this for songs you are not playing.',
          ),
          onChanged: (changed) => value = changed,
          onFieldSubmitted: (_) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _addPlaceholder() async {
    final name = await _askPlaceholderName();
    if (name == null) return;
    final entry = LibrarySetlistEntry.placeholder(
      id: IdFactory.next('entry'),
      title: name,
    );
    await _saveEntries([..._setlist.entries, entry], keepEntryId: entry.id);
  }

  Future<void> _editPlaceholder(int index) async {
    final entry = _setlist.entries[index];
    final name = await _askPlaceholderName(
      initial: entry.placeholderTitle ?? '',
    );
    if (name == null) return;
    final entries = List<LibrarySetlistEntry>.of(_setlist.entries);
    entries[index] = LibrarySetlistEntry.placeholder(id: entry.id, title: name);
    await _saveEntries(entries, keepEntryId: entry.id);
  }

  Future<void> _remove(int index) async {
    final removed = _setlist.entries[index];
    final entries = List<LibrarySetlistEntry>.of(_setlist.entries)
      ..removeAt(index);
    final keep = entries.isEmpty
        ? null
        : entries[index.clamp(0, entries.length - 1)].id;
    await _saveEntries(entries, keepEntryId: keep ?? removed.id);
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final entries = List<LibrarySetlistEntry>.of(_setlist.entries);
    final moved = entries.removeAt(oldIndex);
    entries.insert(newIndex, moved);
    await _saveEntries(entries, keepEntryId: moved.id);
  }

  Future<void> _saveAnnotatedDraft(
    PerformanceDeckElement element,
    VisualStrip Function(VisualStrip strip) update,
    PerformanceDeckElement Function(PerformanceDeckElement element) patch,
  ) async {
    final variantId = element.chartVariantId;
    final stripId = element.sourceStripId;
    if (variantId == null || stripId == null) return;
    final draft =
        _draftsByVariant[variantId] ??
        await widget.services.library.loadDraft(variantId);
    if (draft == null) return;
    final strips = [
      for (final strip in draft.strips)
        if (strip.id == stripId) update(strip) else strip,
    ];
    final updated = draft.copyWith(
      strips: strips,
      updatedAt: DateTime.now().toUtc(),
    );
    await widget.services.library.saveDraft(updated);
    if (!mounted) return;
    final currentDeck = _resolvedDeck;
    final patchedDeck = currentDeck?.copyWith(
      pages: [
        for (final page in currentDeck.pages)
          PerformanceDeckPage(
            id: page.id,
            index: page.index,
            elements: [
              for (final deckElement in page.elements)
                if (deckElement.chartVariantId == variantId &&
                    deckElement.sourceStripId == stripId)
                  patch(deckElement)
                else
                  deckElement,
            ],
          ),
      ],
    );
    setState(() {
      _draftsByVariant = {..._draftsByVariant, variantId: updated};
      if (patchedDeck != null) {
        _resolvedDeck = patchedDeck;
        _deck = Future.value(patchedDeck);
      }
    });
  }

  Future<void> _addStroke(
    PerformanceDeckElement element,
    List<NormalizedPoint> rowLocalPoints,
    AnnotationTool tool,
  ) async {
    final row = element.sourceRowRect;
    if (row == null || rowLocalPoints.length < 2) return;
    final stroke = VisualAnnotationStroke(
      id: IdFactory.next('stroke'),
      points: List.unmodifiable([
        for (final point in rowLocalPoints)
          NormalizedPoint(
            row.left + point.x * row.width,
            row.top + point.y * row.height,
            pressure: point.pressure,
          ).clamp(),
      ]),
      colorArgb: tool == AnnotationTool.highlight ? 0x66FFEB3B : 0xFFFFD740,
      width: tool == AnnotationTool.highlight ? 0.035 : 0.004,
    );
    _lastAnnotation = _AnnotationUndo(
      chartVariantId: element.chartVariantId!,
      stripId: element.sourceStripId!,
      stroke: stroke,
    );
    await _saveAnnotatedDraft(
      element,
      (strip) => strip.copyWith(annotations: [...strip.annotations, stroke]),
      (deckElement) {
        if (deckElement.sourceRowRect != row) return deckElement;
        return deckElement.copyWith(
          annotations: [
            ...deckElement.annotations,
            VisualAnnotationStroke(
              id: stroke.id,
              points: rowLocalPoints,
              colorArgb: stroke.colorArgb,
              width: stroke.width,
            ),
          ],
        );
      },
    );
  }

  Future<void> _eraseAt(
    PerformanceDeckElement element,
    List<NormalizedPoint> rowLocalPoints,
  ) async {
    final row = element.sourceRowRect;
    if (row == null) return;
    final sourcePoints = [
      for (final point in rowLocalPoints)
        NormalizedPoint(
          row.left + point.x * row.width,
          row.top + point.y * row.height,
        ),
    ];
    final removedIds = <String>{};
    await _saveAnnotatedDraft(
      element,
      (strip) {
        const threshold = 0.0025;
        for (final stroke in strip.annotations) {
          var erase = false;
          for (final point in stroke.points) {
            for (final sourcePoint in sourcePoints) {
              final dx = point.x - sourcePoint.x;
              final dy = point.y - sourcePoint.y;
              if (dx * dx + dy * dy <= threshold) {
                erase = true;
                break;
              }
            }
            if (erase) break;
          }
          if (erase) removedIds.add(stroke.id);
        }
        if (removedIds.isEmpty) return strip;
        _lastAnnotation = null;
        return strip.copyWith(
          annotations: strip.annotations
              .where((stroke) => !removedIds.contains(stroke.id))
              .toList(growable: false),
        );
      },
      (deckElement) {
        return deckElement.copyWith(
          annotations: deckElement.annotations
              .where((stroke) => !removedIds.contains(stroke.id))
              .toList(growable: false),
        );
      },
    );
  }

  Future<void> _undoAnnotation(PerformanceDeckElement element) async {
    final undo = _lastAnnotation;
    if (undo == null ||
        undo.chartVariantId != element.chartVariantId ||
        undo.stripId != element.sourceStripId) {
      return;
    }
    await _saveAnnotatedDraft(
      element,
      (strip) => strip.copyWith(
        annotations: strip.annotations
            .where((stroke) => stroke.id != undo.stroke.id)
            .toList(growable: false),
      ),
      (deckElement) => deckElement.copyWith(
        annotations: deckElement.annotations
            .where((stroke) => stroke.id != undo.stroke.id)
            .toList(growable: false),
      ),
    );
    if (mounted) setState(() => _lastAnnotation = null);
  }

  Future<void> _toggleAnnotationVisibility(
    PerformanceDeckElement element,
  ) async {
    await _saveAnnotatedDraft(
      element,
      (strip) => strip.copyWith(annotationsVisible: !strip.annotationsVisible),
      (deckElement) => deckElement.copyWith(
        annotationsVisible: !deckElement.annotationsVisible,
      ),
    );
  }

  Future<void> _toggleAnnotationPdf(PerformanceDeckElement element) async {
    await _saveAnnotatedDraft(
      element,
      (strip) => strip.copyWith(
        includeAnnotationsInPdf: !strip.includeAnnotationsInPdf,
      ),
      (deckElement) => deckElement.copyWith(
        includeAnnotationsInPdf: !deckElement.includeAnnotationsInPdf,
      ),
    );
  }

  Future<void> _clearAllPerformanceNotes() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all performance notes?'),
        content: const Text(
          'This removes pen strokes and performance highlights from every '
          'song in this gig. Chart-editor lyric highlights are not changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear performance notes'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final variantIds = _setlist.entries
        .map((entry) => entry.chartVariantId)
        .whereType<String>()
        .toSet();
    final updatedDrafts = <String, VisualChartDraft>{};
    for (final variantId in variantIds) {
      final draft =
          _draftsByVariant[variantId] ??
          await widget.services.library.loadDraft(variantId);
      if (draft == null) continue;
      final updated = draft.copyWith(
        updatedAt: DateTime.now().toUtc(),
        strips: [
          for (final strip in draft.strips)
            strip.copyWith(annotations: const []),
        ],
      );
      await widget.services.library.saveDraft(updated);
      updatedDrafts[variantId] = updated;
    }
    if (!mounted) return;
    final currentDeck = _resolvedDeck;
    setState(() {
      _lastAnnotation = null;
      _draftsByVariant = {..._draftsByVariant, ...updatedDrafts};
      if (currentDeck != null) {
        final patched = currentDeck.copyWith(
          pages: [
            for (final page in currentDeck.pages)
              PerformanceDeckPage(
                id: page.id,
                index: page.index,
                elements: [
                  for (final element in page.elements)
                    element.kind == PerformanceElementKind.strip
                        ? element.copyWith(annotations: const [])
                        : element,
                ],
              ),
          ],
        );
        _resolvedDeck = patched;
        _deck = Future.value(patched);
      }
    });
  }

  void _jumpToEntry(PerformanceDeck deck, int entryIndex) {
    final entryId = _setlist.entries[entryIndex].id;
    final target = deck.pages.indexWhere(
      (page) => page.elements.any((element) => element.entryId == entryId),
    );
    if (target >= 0) setState(() => _pageIndex = target);
    Navigator.of(context).pop();
  }

  void _move(int delta, int pageCount) {
    final next = (_pageIndex + delta).clamp(0, pageCount - 1);
    if (next != _pageIndex) setState(() => _pageIndex = next);
  }

  Future<void> _exit() async {
    if (_exiting) return;
    _exiting = true;
    try {
      await widget.services.performanceMode.setActive(false);
    } catch (_) {
      // Navigation must remain recoverable even if a native fullscreen or
      // keep-awake release reports an error.
    }
    if (!mounted) return;
    setState(() => _allowExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final background =
        widget.preferences.gigTheme == GigThemePreference.lightOnBlack
        ? Colors.black
        : const Color(0xFFE8E8E8);
    return PopScope(
      canPop: _allowExit,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_exit());
      },
      child: FutureBuilder<PerformanceDeck>(
        future: _deck,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              appBar: AppBar(title: const Text('Gig mode')),
              body: Center(
                child: Text('Gig mode could not open: ${snapshot.error}'),
              ),
            );
          }
          final deck = snapshot.data;
          if (deck == null) {
            return Scaffold(
              backgroundColor: background,
              appBar: AppBar(
                title: const Text('Gig mode'),
                leading: IconButton(
                  tooltip: 'Exit gig mode',
                  onPressed: _exit,
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
              body: Center(
                child: Semantics(
                  liveRegion: true,
                  label: 'Preparing performance pages',
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 18),
                      Text('Preparing performance pages...'),
                      SizedBox(height: 6),
                      Text('You can exit safely while the set is loading.'),
                    ],
                  ),
                ),
              ),
            );
          }
          final page = deck.pages[_pageIndex.clamp(0, deck.pages.length - 1)];
          final selectedEntryId = page.elements.first.entryId;
          final annotationElements = page.elements
              .where((element) => element.kind == PerformanceElementKind.strip)
              .toList(growable: false);
          final annotationElement = annotationElements.isEmpty
              ? null
              : annotationElements.first;
          return Scaffold(
            key: _scaffoldKey,
            backgroundColor: background,
            drawer: Drawer(
              width: 420,
              child: SafeArea(
                child: Column(
                  children: [
                    ListTile(
                      title: Text(
                        _setlist.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      subtitle: const Text('Tap a song to jump to it.'),
                      trailing: IconButton(
                        tooltip: 'Close setlist sidebar',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: _chooseSong,
                            icon: const Icon(Icons.playlist_add),
                            label: const Text('Add song'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _addPlaceholder,
                            icon: const Icon(Icons.not_interested),
                            label: const Text('Add placeholder'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: SetlistSidebar(
                        setlist: _setlist,
                        draftsByVariant: _draftsByVariant,
                        selectedEntryId: selectedEntryId,
                        onEntryTap: (index) => _jumpToEntry(deck, index),
                        onRemove: _remove,
                        onEditPlaceholder: _editPlaceholder,
                        onReorder: _reorder,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            body: SafeArea(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragEnd:
                          _annotationTool == AnnotationTool.none
                          ? (details) {
                              final velocity = details.primaryVelocity ?? 0;
                              if (velocity < -250) _move(1, deck.pages.length);
                              if (velocity > 250) _move(-1, deck.pages.length);
                            }
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 66),
                        child: Center(
                          child: PerformanceDeckPageView(
                            deck: deck,
                            page: page,
                            annotationTool: _annotationTool,
                            onStrokeCompleted: _addStroke,
                            onEraseAt: _eraseAt,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(18),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Open setlist sidebar',
                              onPressed: () =>
                                  _scaffoldKey.currentState?.openDrawer(),
                              color: Colors.white,
                              icon: const Icon(Icons.queue_music),
                            ),
                            TextButton(
                              onPressed: _exit,
                              child: const Text('Exit'),
                            ),
                            IconButton(
                              tooltip: 'Draw annotations',
                              onPressed: annotationElement == null
                                  ? null
                                  : () => setState(
                                      () => _annotationTool =
                                          _annotationTool == AnnotationTool.draw
                                          ? AnnotationTool.none
                                          : AnnotationTool.draw,
                                    ),
                              color: _annotationTool == AnnotationTool.draw
                                  ? Colors.amber
                                  : Colors.white,
                              icon: const Icon(Icons.draw),
                            ),
                            IconButton(
                              tooltip: 'Highlight performance notes',
                              onPressed: annotationElement == null
                                  ? null
                                  : () => setState(
                                      () => _annotationTool =
                                          _annotationTool ==
                                              AnnotationTool.highlight
                                          ? AnnotationTool.none
                                          : AnnotationTool.highlight,
                                    ),
                              color: _annotationTool == AnnotationTool.highlight
                                  ? Colors.amber
                                  : Colors.white,
                              icon: const Icon(Icons.border_color),
                            ),
                            IconButton(
                              tooltip: 'Erase annotations',
                              onPressed: annotationElement == null
                                  ? null
                                  : () => setState(
                                      () => _annotationTool =
                                          _annotationTool ==
                                              AnnotationTool.erase
                                          ? AnnotationTool.none
                                          : AnnotationTool.erase,
                                    ),
                              color: _annotationTool == AnnotationTool.erase
                                  ? Colors.amber
                                  : Colors.white,
                              icon: const Icon(Icons.auto_fix_normal),
                            ),
                            IconButton(
                              tooltip: 'Undo annotation',
                              onPressed:
                                  annotationElement == null ||
                                      _lastAnnotation == null
                                  ? null
                                  : () => _undoAnnotation(annotationElement),
                              color: Colors.white,
                              icon: const Icon(Icons.undo),
                            ),
                            IconButton(
                              tooltip:
                                  annotationElement?.annotationsVisible == true
                                  ? 'Hide annotations'
                                  : 'Show annotations',
                              onPressed: annotationElement == null
                                  ? null
                                  : () => _toggleAnnotationVisibility(
                                      annotationElement,
                                    ),
                              color: Colors.white,
                              icon: Icon(
                                annotationElement?.annotationsVisible == true
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                            ),
                            IconButton(
                              tooltip:
                                  annotationElement?.includeAnnotationsInPdf ==
                                      true
                                  ? 'Exclude annotations from PDF'
                                  : 'Include annotations in PDF',
                              onPressed: annotationElement == null
                                  ? null
                                  : () =>
                                        _toggleAnnotationPdf(annotationElement),
                              color:
                                  annotationElement?.includeAnnotationsInPdf ==
                                      true
                                  ? Colors.amber
                                  : Colors.white,
                              icon: const Icon(Icons.picture_as_pdf_outlined),
                            ),
                            IconButton(
                              tooltip: 'Clear all performance notes',
                              onPressed: _clearAllPerformanceNotes,
                              color: Colors.white,
                              icon: const Icon(Icons.layers_clear),
                            ),
                            IconButton(
                              tooltip: 'Previous page',
                              onPressed: _pageIndex == 0
                                  ? null
                                  : () => _move(-1, deck.pages.length),
                              color: Colors.white,
                              icon: const Icon(Icons.arrow_back),
                            ),
                            Text(
                              '${_pageIndex + 1} / ${deck.pages.length}',
                              style: const TextStyle(color: Colors.white),
                            ),
                            IconButton(
                              tooltip: 'Next page',
                              onPressed: _pageIndex + 1 == deck.pages.length
                                  ? null
                                  : () => _move(1, deck.pages.length),
                              color: Colors.white,
                              icon: const Icon(Icons.arrow_forward),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
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

String _displayTitle(VisualChartDraft draft) {
  final title = draft.title.trim();
  if (title.isNotEmpty && title != 'Untitled chart') return title;
  final artist = draft.artist.trim();
  return artist.isEmpty ? 'Untitled chart' : artist;
}
