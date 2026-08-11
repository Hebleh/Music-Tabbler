import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../application/app_services.dart';
import '../../application/gig_bar_repacker.dart';
import '../../application/gig_annotation_session.dart';
import '../../application/gig_viewport_layout.dart';
import '../../application/gig_viewport_session.dart';
import '../../application/performance_deck.dart';
import '../../application/setlist_edit_session.dart';
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
  late final SetlistEditSession _setlistEditSession;
  late final GigAnnotationSession _annotationSession;
  late Future<PerformanceDeck> _deck;
  PerformanceDeck? _resolvedDeck;
  List<VisualChartDraft> _availableDrafts = const [];
  Map<String, VisualChartDraft> _draftsByVariant = const {};
  late final GigViewportSession _viewport;
  var _allowExit = false;
  var _exiting = false;
  var _annotationTool = AnnotationTool.none;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setlist = widget.setlist;
    _setlistEditSession = SetlistEditSession(
      initialSetlist: widget.setlist,
      repository: widget.services.setlists,
    );
    _annotationSession = GigAnnotationSession(library: widget.services.library);
    _viewport = GigViewportSession(
      initialZoom: widget.preferences.gigZoom,
      initialTheme: widget.preferences.gigTheme,
    );
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
    final sourceDeck = await widget.services.performanceDeckBuilder
        .buildPerformanceDeck(_setlist, density: widget.density);
    final imageByteCount = sourceDeck.pages.fold<int>(
      0,
      (pageTotal, page) =>
          pageTotal +
          page.elements.fold<int>(
            0,
            (elementTotal, element) =>
                elementTotal + (element.imageBytes?.length ?? 0),
          ),
    );
    final deck = imageByteCount < 64 * 1024
        ? repackGigDeckIntoBars(sourceDeck)
        : PerformanceDeck.fromMessage(
            await compute(repackGigDeckMessage, sourceDeck.toMessage()),
          );
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
    final updated = await _setlistEditSession.replaceEntries(entries);
    if (!mounted) return;
    setState(() {
      _setlist = updated;
      _viewport.resetPage();
      _deck = _buildDeck().then((deck) {
        if (keepEntryId != null) {
          final target = deck.pages.indexWhere(
            (page) =>
                page.elements.any((element) => element.entryId == keepEntryId),
          );
          if (target >= 0) _viewport.selectPage(target);
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
                      child: Text(draft.displayTitle),
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
    if (variantId == null) return;
    final result = await _annotationSession.save(
      element: element,
      draftsByVariant: _draftsByVariant,
      deck: _resolvedDeck,
      updateStrip: update,
      patchElement: patch,
    );
    if (result == null) return;
    if (!mounted) return;
    setState(() {
      _draftsByVariant = {..._draftsByVariant, variantId: result.draft};
      if (result.deck case final patchedDeck?) {
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
    _annotationSession.rememberStroke(element, stroke);
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
        _annotationSession.clearUndo();
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
    final variantId = element.chartVariantId;
    if (variantId == null) return;
    final result = await _annotationSession.undo(
      element: element,
      draftsByVariant: _draftsByVariant,
      deck: _resolvedDeck,
    );
    if (result == null || !mounted) return;
    setState(() {
      _draftsByVariant = {..._draftsByVariant, variantId: result.draft};
      if (result.deck case final patchedDeck?) {
        _resolvedDeck = patchedDeck;
        _deck = Future.value(patchedDeck);
      }
    });
  }

  Future<void> _setPageAnnotationVisibility(
    List<PerformanceDeckElement> elements, {
    required bool visible,
  }) async {
    for (final element in elements) {
      await _saveAnnotatedDraft(
        element,
        (strip) => strip.copyWith(annotationsVisible: visible),
        (deckElement) => deckElement.copyWith(annotationsVisible: visible),
      );
    }
  }

  Future<void> _setPageAnnotationPdfInclusion(
    List<PerformanceDeckElement> elements, {
    required bool included,
  }) async {
    for (final element in elements) {
      await _saveAnnotatedDraft(
        element,
        (strip) => strip.copyWith(includeAnnotationsInPdf: included),
        (deckElement) =>
            deckElement.copyWith(includeAnnotationsInPdf: included),
      );
    }
  }

  PerformanceDeckElement? _undoElementForPage(
    List<PerformanceDeckElement> elements,
  ) {
    return _annotationSession.undoElementForPage(elements);
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
      _annotationSession.clearUndo();
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

  void _jumpToEntry(List<GigViewportPage> pages, int entryIndex) {
    final entryId = _setlist.entries[entryIndex].id;
    final target = gigPageIndexForEntry(pages, entryId);
    if (target >= 0) {
      setState(() => _viewport.selectPage(target));
    }
    Navigator.of(context).pop();
  }

  void _move(int delta, int pageCount) {
    if (_viewport.move(delta, pageCount)) setState(() {});
  }

  Future<void> _saveGigZoom(double value) async {
    final current = await widget.services.preferences.load();
    await widget.services.preferences.save(current.copyWith(gigZoom: value));
  }

  Future<void> _setGigTheme(GigThemePreference value) async {
    if (!_viewport.setTheme(value)) return;
    setState(() {});
    final current = await widget.services.preferences.load();
    await widget.services.preferences.save(current.copyWith(gigTheme: value));
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
    final dark = _viewport.theme == GigThemePreference.lightOnBlack;
    final background = dark ? Colors.black : Colors.white;
    final gigThemeData = dark ? ThemeData.dark() : ThemeData.light();
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
          return LayoutBuilder(
            builder: (context, constraints) {
              final safePadding = MediaQuery.paddingOf(context);
              final controlsHeight = _viewport.stageLocked
                  ? 18.0
                  : (_viewport.toolbarVisible ? 174.0 : 0.0);
              final viewportWidth = (constraints.maxWidth - 16).clamp(
                1.0,
                double.infinity,
              );
              final viewportHeight =
                  (constraints.maxHeight -
                          safePadding.vertical -
                          controlsHeight -
                          16)
                      .clamp(1.0, double.infinity);
              final gigPages = const GigViewportLayout().plan(
                deck: deck,
                viewportWidth: viewportWidth,
                viewportHeight: viewportHeight,
                zoom: _viewport.setWideZoom,
                zoomByEntry: _viewport.songZoomByEntry,
                alignment: _viewport.alignment,
              );
              if (gigPages.isEmpty) {
                return const Scaffold(
                  body: Center(
                    child: Text('This gig has no displayable rows.'),
                  ),
                );
              }
              final safePageIndex = _viewport.pageIndex.clamp(
                0,
                gigPages.length - 1,
              );
              final page = gigPages[safePageIndex];
              final selectedEntryId = page.entryId;
              final annotationElements = page.items
                  .map((item) => item.element)
                  .where(
                    (element) => element.kind == PerformanceElementKind.strip,
                  )
                  .toList(growable: false);
              final annotationTargets = <PerformanceDeckElement>[];
              final annotationTargetIds = <String>{};
              for (final element in annotationElements) {
                final variantId = element.chartVariantId;
                final stripId = element.sourceStripId;
                if (variantId == null || stripId == null) continue;
                if (annotationTargetIds.add('$variantId\u0000$stripId')) {
                  annotationTargets.add(element);
                }
              }
              final annotationElement = annotationElements.isEmpty
                  ? null
                  : annotationElements.first;
              final undoElement = _undoElementForPage(annotationTargets);
              final pageAnnotationsVisible =
                  annotationTargets.isNotEmpty &&
                  annotationTargets.every(
                    (element) => element.annotationsVisible,
                  );
              final pageAnnotationsIncludedInPdf =
                  annotationTargets.isNotEmpty &&
                  annotationTargets.every(
                    (element) => element.includeAnnotationsInPdf,
                  );
              return Theme(
                data: gigThemeData,
                child: Scaffold(
                  key: _scaffoldKey,
                  backgroundColor: background,
                  drawerEnableOpenDragGesture: !_viewport.stageLocked,
                  drawer: _viewport.stageLocked
                      ? null
                      : Drawer(
                          width: 420,
                          child: SafeArea(
                            child: Column(
                              children: [
                                ListTile(
                                  title: Text(
                                    _setlist.name,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                  subtitle: const Text(
                                    'Tap a song to jump to it.',
                                  ),
                                  trailing: IconButton(
                                    tooltip: 'Close setlist sidebar',
                                    onPressed: () => Navigator.pop(context),
                                    icon: const Icon(Icons.close),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
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
                                    onEntryTap: (index) =>
                                        _jumpToEntry(gigPages, index),
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
                            key: const Key('gig-stage-surface'),
                            behavior: HitTestBehavior.opaque,
                            onTap:
                                !_viewport.stageLocked &&
                                    _annotationTool == AnnotationTool.none
                                ? () => setState(_viewport.toggleToolbar)
                                : null,
                            onHorizontalDragEnd:
                                (_viewport.stageLocked ||
                                    _annotationTool == AnnotationTool.none)
                                ? (details) {
                                    final velocity =
                                        details.primaryVelocity ?? 0;
                                    if (velocity < -250) {
                                      _move(1, gigPages.length);
                                    }
                                    if (velocity > 250) {
                                      _move(-1, gigPages.length);
                                    }
                                  }
                                : null,
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                8,
                                8,
                                8,
                                _viewport.stageLocked ||
                                        !_viewport.toolbarVisible
                                    ? 8
                                    : 174,
                              ),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (child, animation) =>
                                    FadeTransition(
                                      opacity: animation,
                                      child: SlideTransition(
                                        position: Tween<Offset>(
                                          begin: Offset(
                                            _viewport.pageDirection * 0.10,
                                            0,
                                          ),
                                          end: Offset.zero,
                                        ).animate(animation),
                                        child: child,
                                      ),
                                    ),
                                child: PerformanceViewportPageView(
                                  key: ValueKey('gig-page-$safePageIndex'),
                                  page: page,
                                  width: viewportWidth,
                                  height: viewportHeight,
                                  annotationTool: _viewport.stageLocked
                                      ? AnnotationTool.none
                                      : _annotationTool,
                                  onStrokeCompleted: _addStroke,
                                  onEraseAt: _eraseAt,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (!_viewport.stageLocked && _viewport.toolbarVisible)
                          Positioned(
                            left: 8,
                            right: 8,
                            bottom: 8,
                            child: Material(
                              color: Colors.black.withValues(alpha: 0.82),
                              borderRadius: BorderRadius.circular(18),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      const SizedBox(
                                        width: 88,
                                        child: Padding(
                                          padding: EdgeInsets.only(left: 12),
                                          child: Text(
                                            'This song',
                                            style: TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Slider(
                                          key: const Key(
                                            'gig-song-zoom-slider',
                                          ),
                                          value: _viewport.zoomForEntry(
                                            page.entryId,
                                          ),
                                          min: 0.45,
                                          max: 1.5,
                                          divisions: 21,
                                          label:
                                              '${(_viewport.zoomForEntry(page.entryId) * 100).round()}%',
                                          onChanged: (value) {
                                            final anchor = page.items
                                                .where(
                                                  (item) =>
                                                      item.element.kind ==
                                                      PerformanceElementKind
                                                          .strip,
                                                )
                                                .firstOrNull
                                                ?.element;
                                            final zooms = {
                                              ..._viewport.songZoomByEntry,
                                              page.entryId: value,
                                            };
                                            final reflowed =
                                                const GigViewportLayout().plan(
                                                  deck: deck,
                                                  viewportWidth: viewportWidth,
                                                  viewportHeight:
                                                      viewportHeight,
                                                  zoom: _viewport.setWideZoom,
                                                  zoomByEntry: zooms,
                                                  alignment:
                                                      _viewport.alignment,
                                                );
                                            final target =
                                                gigPageIndexForAnchor(
                                                  reflowed,
                                                  entryId: page.entryId,
                                                  sourceStripId:
                                                      anchor?.sourceStripId,
                                                  rowIndex: anchor?.rowIndex,
                                                );
                                            setState(() {
                                              _viewport.setSongZoom(
                                                page.entryId,
                                                value,
                                                anchorPage: target,
                                              );
                                            });
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      const SizedBox(
                                        width: 88,
                                        child: Padding(
                                          padding: EdgeInsets.only(left: 12),
                                          child: Text(
                                            'Whole set',
                                            style: TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const Icon(
                                        Icons.zoom_out,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      Expanded(
                                        child: Slider(
                                          key: const Key('gig-zoom-slider'),
                                          value: _viewport.setWideZoom,
                                          min: 0.45,
                                          max: 1.5,
                                          divisions: 21,
                                          label:
                                              '${(_viewport.setWideZoom * 100).round()}%',
                                          onChanged: (value) {
                                            final anchor = page.items
                                                .where(
                                                  (item) =>
                                                      item.element.kind ==
                                                      PerformanceElementKind
                                                          .strip,
                                                )
                                                .firstOrNull
                                                ?.element;
                                            final reflowed =
                                                const GigViewportLayout().plan(
                                                  deck: deck,
                                                  viewportWidth: viewportWidth,
                                                  viewportHeight:
                                                      viewportHeight,
                                                  zoom: value,
                                                  zoomByEntry:
                                                      _viewport.songZoomByEntry,
                                                  alignment:
                                                      _viewport.alignment,
                                                );
                                            final target =
                                                gigPageIndexForAnchor(
                                                  reflowed,
                                                  entryId: page.entryId,
                                                  sourceStripId:
                                                      anchor?.sourceStripId,
                                                  rowIndex: anchor?.rowIndex,
                                                );
                                            setState(() {
                                              _viewport.updateSetWideZoom(
                                                value,
                                                anchorPage: target,
                                              );
                                            });
                                          },
                                          onChangeEnd: (value) =>
                                              unawaited(_saveGigZoom(value)),
                                        ),
                                      ),
                                      const Icon(
                                        Icons.zoom_in,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      SizedBox(
                                        width: 112,
                                        child: Text(
                                          '${(_viewport.setWideZoom * 100).round()}% zoom',
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Open setlist sidebar',
                                          onPressed: () => _scaffoldKey
                                              .currentState
                                              ?.openDrawer(),
                                          color: Colors.white,
                                          icon: const Icon(Icons.queue_music),
                                        ),
                                        TextButton(
                                          onPressed: _exit,
                                          child: const Text('Exit'),
                                        ),
                                        IconButton(
                                          tooltip: dark
                                              ? 'Use dark-on-light gig theme'
                                              : 'Use light-on-black gig theme',
                                          onPressed: () => unawaited(
                                            _setGigTheme(
                                              dark
                                                  ? GigThemePreference
                                                        .darkOnLight
                                                  : GigThemePreference
                                                        .lightOnBlack,
                                            ),
                                          ),
                                          color: Colors.white,
                                          icon: Icon(
                                            dark
                                                ? Icons.light_mode
                                                : Icons.dark_mode,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Lock stage controls',
                                          onPressed: () => setState(() {
                                            _viewport.lockStage();
                                            _annotationTool =
                                                AnnotationTool.none;
                                          }),
                                          color: Colors.white,
                                          icon: const Icon(Icons.lock_open),
                                        ),
                                        IconButton(
                                          tooltip: 'Align bars left',
                                          onPressed: () => setState(
                                            () => _viewport.setAlignment(
                                              GigHorizontalAlignment.left,
                                            ),
                                          ),
                                          color:
                                              _viewport.alignment ==
                                                  GigHorizontalAlignment.left
                                              ? Colors.amber
                                              : Colors.white,
                                          icon: const Icon(
                                            Icons.format_align_left,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Align bars center',
                                          onPressed: () => setState(
                                            () => _viewport.setAlignment(
                                              GigHorizontalAlignment.center,
                                            ),
                                          ),
                                          color:
                                              _viewport.alignment ==
                                                  GigHorizontalAlignment.center
                                              ? Colors.amber
                                              : Colors.white,
                                          icon: const Icon(
                                            Icons.format_align_center,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Align bars right',
                                          onPressed: () => setState(
                                            () => _viewport.setAlignment(
                                              GigHorizontalAlignment.right,
                                            ),
                                          ),
                                          color:
                                              _viewport.alignment ==
                                                  GigHorizontalAlignment.right
                                              ? Colors.amber
                                              : Colors.white,
                                          icon: const Icon(
                                            Icons.format_align_right,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Draw annotations',
                                          onPressed: annotationElement == null
                                              ? null
                                              : () => setState(
                                                  () => _annotationTool =
                                                      _annotationTool ==
                                                          AnnotationTool.draw
                                                      ? AnnotationTool.none
                                                      : AnnotationTool.draw,
                                                ),
                                          color:
                                              _annotationTool ==
                                                  AnnotationTool.draw
                                              ? Colors.amber
                                              : Colors.white,
                                          icon: const Icon(Icons.draw),
                                        ),
                                        IconButton(
                                          tooltip:
                                              'Highlight performance notes',
                                          onPressed: annotationElement == null
                                              ? null
                                              : () => setState(
                                                  () => _annotationTool =
                                                      _annotationTool ==
                                                          AnnotationTool
                                                              .highlight
                                                      ? AnnotationTool.none
                                                      : AnnotationTool
                                                            .highlight,
                                                ),
                                          color:
                                              _annotationTool ==
                                                  AnnotationTool.highlight
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
                                          color:
                                              _annotationTool ==
                                                  AnnotationTool.erase
                                              ? Colors.amber
                                              : Colors.white,
                                          icon: const Icon(
                                            Icons.auto_fix_normal,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Undo annotation',
                                          onPressed: undoElement == null
                                              ? null
                                              : () => _undoAnnotation(
                                                  undoElement,
                                                ),
                                          color: Colors.white,
                                          icon: const Icon(Icons.undo),
                                        ),
                                        IconButton(
                                          tooltip: pageAnnotationsVisible
                                              ? 'Hide annotations'
                                              : 'Show annotations',
                                          onPressed: annotationTargets.isEmpty
                                              ? null
                                              : () => _setPageAnnotationVisibility(
                                                  annotationTargets,
                                                  visible:
                                                      !pageAnnotationsVisible,
                                                ),
                                          color: Colors.white,
                                          icon: Icon(
                                            pageAnnotationsVisible
                                                ? Icons.visibility
                                                : Icons.visibility_off,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: pageAnnotationsIncludedInPdf
                                              ? 'Exclude annotations from PDF'
                                              : 'Include annotations in PDF',
                                          onPressed: annotationTargets.isEmpty
                                              ? null
                                              : () => _setPageAnnotationPdfInclusion(
                                                  annotationTargets,
                                                  included:
                                                      !pageAnnotationsIncludedInPdf,
                                                ),
                                          color: pageAnnotationsIncludedInPdf
                                              ? Colors.amber
                                              : Colors.white,
                                          icon: const Icon(
                                            Icons.picture_as_pdf_outlined,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip:
                                              'Clear all performance notes',
                                          onPressed: _clearAllPerformanceNotes,
                                          color: Colors.white,
                                          icon: const Icon(Icons.layers_clear),
                                        ),
                                        IconButton(
                                          tooltip: 'Previous page',
                                          onPressed: safePageIndex == 0
                                              ? null
                                              : () =>
                                                    _move(-1, gigPages.length),
                                          color: Colors.white,
                                          icon: const Icon(Icons.arrow_back),
                                        ),
                                        Text(
                                          '${safePageIndex + 1} / ${gigPages.length}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Next page',
                                          onPressed:
                                              safePageIndex + 1 ==
                                                  gigPages.length
                                              ? null
                                              : () => _move(1, gigPages.length),
                                          color: Colors.white,
                                          icon: const Icon(Icons.arrow_forward),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (_viewport.stageLocked)
                          Positioned(
                            left: 4,
                            bottom: 4,
                            child: Material(
                              color: Colors.black.withValues(alpha: 0.55),
                              shape: const CircleBorder(),
                              child: IconButton(
                                key: const Key('gig-unlock-button'),
                                tooltip: 'Unlock stage controls',
                                visualDensity: VisualDensity.compact,
                                iconSize: 18,
                                color: Colors.white70,
                                onPressed: () => setState(() {
                                  _viewport.unlockStage();
                                }),
                                icon: const Icon(Icons.lock),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
