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
  List<VisualChartDraft> _availableDrafts = const [];
  Map<String, VisualChartDraft> _draftsByVariant = const {};
  var _pageIndex = 0;
  var _allowExit = false;

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

  Future<PerformanceDeck> _buildDeck() {
    return widget.services.performanceDeckBuilder.buildPerformanceDeck(
      _setlist,
      density: widget.density,
    );
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
    await widget.services.performanceMode.setActive(false);
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
        if (!didPop) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Use Exit to leave gig mode safely.')),
          );
        }
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
            return const Scaffold(
              backgroundColor: Colors.black,
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final page = deck.pages[_pageIndex.clamp(0, deck.pages.length - 1)];
          final selectedEntryId = page.elements.first.entryId;
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
                      onHorizontalDragEnd: (details) {
                        final velocity = details.primaryVelocity ?? 0;
                        if (velocity < -250) _move(1, deck.pages.length);
                        if (velocity > 250) _move(-1, deck.pages.length);
                      },
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 66),
                        child: Center(
                          child: PerformanceDeckPageView(
                            deck: deck,
                            page: page,
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
                      child: Row(
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
                          const Spacer(),
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
                          const Spacer(),
                          const SizedBox(width: 88),
                        ],
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

String _displayTitle(VisualChartDraft draft) {
  final title = draft.title.trim();
  if (title.isNotEmpty && title != 'Untitled chart') return title;
  final artist = draft.artist.trim();
  return artist.isEmpty ? 'Untitled chart' : artist;
}
