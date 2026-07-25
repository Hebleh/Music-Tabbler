import 'package:flutter/material.dart';

import '../../application/app_services.dart';
import '../../application/service_contracts.dart';
import '../../domain/library_models.dart';
import '../../domain/device_preferences.dart';
import '../../domain/visual_chart_models.dart';
import '../chart/chart_editor_screen.dart';
import '../import/visual_import_screen.dart';
import '../performance/performance_preview_screen.dart';
import '../performance/gig_mode_screen.dart';
import '../setlists/setlist_sidebar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.services,
    required this.preferences,
    required this.onPreferencesChanged,
  });

  final AppServices services;
  final DevicePreferences preferences;
  final ValueChanged<DevicePreferences> onPreferencesChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  var _selectedIndex = 0;
  var _libraryRevision = 0;
  late Future<List<VisualChartDraft>> _drafts;

  @override
  void initState() {
    super.initState();
    _reloadDrafts();
  }

  void _reloadDrafts() {
    _drafts = widget.services.library.listDrafts();
  }

  Future<void> _openVisualEditor([VisualChartDraft? draft]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            VisualImportScreen(services: widget.services, initialDraft: draft),
      ),
    );
    if (mounted) setState(_reloadDrafts);
  }

  Future<void> _deleteVisualDraft(VisualChartDraft draft) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete saved chart?'),
        content: Text(
          'Delete "${draft.title}" from Song Pool? Imported source assets are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.services.library.deleteDraft(draft.id);
    } on ChartVariantReferencedBySetlistsException catch (error) {
      if (!mounted) return;
      final removeAndDelete = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Chart is used in setlists'),
          content: Text(
            '"${draft.title}" is used by ${error.setlistIds.length} '
            'setlist(s). Remove every occurrence from those setlists and '
            'delete the chart?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep chart'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove and delete'),
            ),
          ],
        ),
      );
      if (removeAndDelete != true) return;
      await widget.services.library.deleteDraftAndRemoveSetlistReferences(
        draft.id,
        updatedAt: DateTime.now().toUtc(),
      );
    }
    if (!mounted) return;
    setState(() {
      _reloadDrafts();
      _libraryRevision += 1;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Deleted "${draft.title}" from Song Pool.')),
    );
  }

  Future<void> _exportPortableSong(VisualChartDraft draft) async {
    final transfer = widget.services.songBundles;
    if (transfer == null) return;
    try {
      final destination = await transfer.exportSongWithPicker(draft.id);
      if (destination != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Portable song exported to $destination')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _importPortableSong() async {
    final transfer = widget.services.songBundles;
    if (transfer == null) return;
    try {
      final result = await transfer.importSongWithPicker();
      if (result == null || !mounted) return;
      setState(() {
        _reloadDrafts();
        _libraryRevision += 1;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported ${result.importedVariantIds.length} chart variant(s). '
            'Existing copies are retained as separate variants.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _showLibraryTransfer() async {
    final transfer = widget.services.libraryState;
    if (transfer == null) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Library transfer and recovery'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(dialogContext);
              _exportLibraryState();
            },
            child: const ListTile(
              leading: Icon(Icons.upload_file_outlined),
              title: Text('Export .mtstate'),
              subtitle: Text('Songs, setlists, assets, and annotations'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(dialogContext);
              _importLibraryState(StateImportMode.merge);
            },
            child: const ListTile(
              leading: Icon(Icons.merge),
              title: Text('Import and keep local library'),
              subtitle: Text('Conflicts become separate songs or variants'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(dialogContext);
              _confirmReplaceLibrary();
            },
            child: const ListTile(
              leading: Icon(Icons.swap_horiz),
              title: Text('Replace from .mtstate'),
              subtitle: Text('A recoverable backup is created first'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(dialogContext);
              _restoreLibraryBackup();
            },
            child: const ListTile(
              leading: Icon(Icons.restore),
              title: Text('Restore a backup'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportLibraryState() async {
    try {
      final destination = await widget.services.libraryState!
          .exportStateWithPicker();
      if (destination != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Library state exported to $destination')),
        );
      }
    } catch (error) {
      _showTransferError(error);
    }
  }

  Future<void> _confirmReplaceLibrary() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace the local library?'),
        content: const Text(
          'The selected state is fully validated and a recoverable backup of '
          'the current library is created before replacement.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Choose state and replace'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _importLibraryState(StateImportMode.replace);
    }
  }

  Future<void> _importLibraryState(StateImportMode mode) async {
    try {
      final result = await widget.services.libraryState!.importStateWithPicker(
        mode,
      );
      if (result == null || !mounted) return;
      _refreshAfterStateChange();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported ${result.importedVariants} variant(s) and '
            '${result.importedSetlists} setlist(s).',
          ),
        ),
      );
    } catch (error) {
      _showTransferError(error);
    }
  }

  Future<void> _restoreLibraryBackup() async {
    try {
      final backups = await widget.services.libraryState!.listBackups();
      if (!mounted) return;
      if (backups.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No recoverable backups exist yet.')),
        );
        return;
      }
      final selected = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Restore backup'),
          children: [
            for (final path in backups)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, path),
                child: Text(path.split(RegExp(r'[/\\]')).last),
              ),
          ],
        ),
      );
      if (selected == null) return;
      await widget.services.libraryState!.restoreBackup(selected);
      if (!mounted) return;
      _refreshAfterStateChange();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Library backup restored.')));
    } catch (error) {
      _showTransferError(error);
    }
  }

  void _refreshAfterStateChange() {
    setState(() {
      _reloadDrafts();
      _libraryRevision += 1;
    });
  }

  void _showTransferError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toString())));
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _SongPool(
        drafts: _drafts,
        onOpenVisual: _openVisualEditor,
        onDeleteVisual: _deleteVisualDraft,
        onExportPortable: widget.services.songBundles == null
            ? null
            : _exportPortableSong,
        onImportPortable: widget.services.songBundles == null
            ? null
            : _importPortableSong,
        onOpenSemantic: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ChartEditorScreen(
              preferences: widget.preferences,
              onPreferencesChanged: widget.onPreferencesChanged,
            ),
          ),
        ),
      ),
      _GigsAndSetlists(
        key: ValueKey(_libraryRevision),
        services: widget.services,
        preferences: widget.preferences,
      ),
      _ImportSource(onStartVisual: _openVisualEditor),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 840;
        final content = Scaffold(
          appBar: AppBar(
            title: const Text('Music Tabbler'),
            actions: [
              if (widget.services.libraryState != null)
                IconButton(
                  tooltip: 'Library transfer and recovery',
                  onPressed: _showLibraryTransfer,
                  icon: const Icon(Icons.move_to_inbox_outlined),
                ),
              IconButton(
                tooltip: widget.preferences.appTheme == AppThemePreference.dark
                    ? 'Use light theme'
                    : 'Use dark theme',
                onPressed: () => widget.onPreferencesChanged(
                  widget.preferences.copyWith(
                    appTheme:
                        widget.preferences.appTheme == AppThemePreference.dark
                        ? AppThemePreference.light
                        : AppThemePreference.dark,
                  ),
                ),
                icon: Icon(
                  widget.preferences.appTheme == AppThemePreference.dark
                      ? Icons.light_mode
                      : Icons.dark_mode,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: pages[_selectedIndex],
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (value) =>
                      setState(() => _selectedIndex = value),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.library_music_outlined),
                      selectedIcon: Icon(Icons.library_music),
                      label: 'Song Pool',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.queue_music_outlined),
                      selectedIcon: Icon(Icons.queue_music),
                      label: 'Gigs',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.add_box_outlined),
                      selectedIcon: Icon(Icons.add_box),
                      label: 'New / Import',
                    ),
                  ],
                ),
        );
        if (!wide) return content;
        return Scaffold(
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: _selectedIndex,
                labelType: NavigationRailLabelType.all,
                onDestinationSelected: (value) =>
                    setState(() => _selectedIndex = value),
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.library_music_outlined),
                    selectedIcon: Icon(Icons.library_music),
                    label: Text('Song Pool'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.queue_music_outlined),
                    selectedIcon: Icon(Icons.queue_music),
                    label: Text('Gigs'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.add_box_outlined),
                    selectedIcon: Icon(Icons.add_box),
                    label: Text('New / Import'),
                  ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: content),
            ],
          ),
        );
      },
    );
  }
}

class _SongPool extends StatelessWidget {
  const _SongPool({
    required this.drafts,
    required this.onOpenVisual,
    required this.onDeleteVisual,
    required this.onExportPortable,
    required this.onImportPortable,
    required this.onOpenSemantic,
  });

  final Future<List<VisualChartDraft>> drafts;
  final ValueChanged<VisualChartDraft?> onOpenVisual;
  final ValueChanged<VisualChartDraft> onDeleteVisual;
  final ValueChanged<VisualChartDraft>? onExportPortable;
  final VoidCallback? onImportPortable;
  final VoidCallback onOpenSemantic;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Song Pool',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Saved visual charts and semantic song variants.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                if (onImportPortable != null)
                  OutlinedButton.icon(
                    onPressed: onImportPortable,
                    icon: const Icon(Icons.file_open_outlined),
                    label: const Text('Import .mtsong'),
                  ),
                FilledButton.icon(
                  onPressed: () => onOpenVisual(null),
                  icon: const Icon(Icons.add),
                  label: const Text('New visual chart'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        FutureBuilder<List<VisualChartDraft>>(
          future: drafts,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: const Text('Saved charts could not be loaded'),
                  subtitle: Text(snapshot.error.toString()),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snapshot.data!;
            if (items.isEmpty) {
              return const Card(
                child: ListTile(
                  leading: Icon(Icons.photo_library_outlined),
                  title: Text('No saved visual charts yet'),
                  subtitle: Text(
                    'Import screenshots or a PDF to create the first one.',
                  ),
                ),
              );
            }
            return Column(
              children: [
                for (final draft in items)
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.view_stream),
                      ),
                      title: Text(_displayTitle(draft)),
                      subtitle: Text(
                        [
                          if (_displayArtist(draft).isNotEmpty)
                            _displayArtist(draft),
                          '${draft.strips.length} row(s)',
                          'Last edited ${_formatEditedDate(draft.updatedAt)}',
                        ].join(' | '),
                      ),
                      trailing: Wrap(
                        spacing: 8,
                        children: [
                          if (onExportPortable != null)
                            IconButton(
                              tooltip: 'Export portable song',
                              onPressed: () => onExportPortable!(draft),
                              icon: const Icon(Icons.archive_outlined),
                            ),
                          IconButton(
                            tooltip: 'Delete saved chart',
                            onPressed: () => onDeleteVisual(draft),
                            icon: const Icon(Icons.delete_outline),
                          ),
                          FilledButton(
                            onPressed: () => onOpenVisual(draft),
                            child: const Text('Open'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.music_note)),
            title: const Text('Foundation Groove'),
            subtitle: const Text(
              'Music Tabbler - 5-string BEADG - Semantic sample',
            ),
            trailing: FilledButton(
              onPressed: onOpenSemantic,
              child: const Text('Open sample chart'),
            ),
          ),
        ),
      ],
    );
  }
}

String _displayTitle(VisualChartDraft draft) {
  if (_isUntitled(draft.title) && draft.artist.trim().isNotEmpty) {
    return draft.artist.trim();
  }
  return draft.title;
}

String _displayArtist(VisualChartDraft draft) =>
    _isUntitled(draft.title) ? '' : draft.artist.trim();

bool _isUntitled(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized.isEmpty ||
      normalized == 'untitled' ||
      normalized == 'untitled chart';
}

String _formatEditedDate(DateTime value) {
  final local = value.toLocal();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${months[local.month - 1]} ${local.year}, $hour:$minute';
}

class _GigsAndSetlists extends StatefulWidget {
  const _GigsAndSetlists({
    super.key,
    required this.services,
    required this.preferences,
  });

  final AppServices services;
  final DevicePreferences preferences;

  @override
  State<_GigsAndSetlists> createState() => _GigsAndSetlistsState();
}

class _GigsAndSetlistsState extends State<_GigsAndSetlists> {
  late Future<List<LibrarySetlist>> _setlists;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _setlists = widget.services.setlists.listSetlists();
  }

  Future<String?> _askName({String initial = ''}) async {
    var name = initial;
    var showEmptyError = false;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void submit() {
            final value = name.trim();
            if (value.isEmpty) {
              setDialogState(() => showEmptyError = true);
              return;
            }
            Navigator.pop(context, value);
          }

          return AlertDialog(
            title: Text(initial.isEmpty ? 'Create setlist' : 'Rename setlist'),
            content: TextFormField(
              initialValue: initial,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Setlist name',
                errorText: showEmptyError ? 'Enter a setlist name.' : null,
              ),
              onChanged: (value) {
                name = value;
                if (showEmptyError) {
                  setDialogState(() => showEmptyError = false);
                }
              },
              onFieldSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(onPressed: submit, child: const Text('Save')),
            ],
          );
        },
      ),
    );
    return result?.trim();
  }

  Future<void> _create() async {
    final name = await _askName();
    if (name == null || name.isEmpty) return;
    final now = DateTime.now().toUtc();
    await widget.services.setlists.saveSetlist(
      LibrarySetlist(
        id: IdFactory.next('setlist'),
        name: name,
        createdAt: now,
        updatedAt: now,
      ),
    );
    if (!mounted) return;
    setState(_reload);
  }

  Future<void> _open(LibrarySetlist setlist) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SetlistEditorScreen(
          services: widget.services,
          setlistId: setlist.id,
          preferences: widget.preferences,
        ),
      ),
    );
    if (!mounted) return;
    setState(_reload);
  }

  Future<void> _rename(LibrarySetlist setlist) async {
    final name = await _askName(initial: setlist.name);
    if (name == null || name.isEmpty || name == setlist.name) return;
    await widget.services.setlists.saveSetlist(
      LibrarySetlist(
        id: setlist.id,
        name: name,
        createdAt: setlist.createdAt,
        updatedAt: DateTime.now().toUtc(),
        scheduledAt: setlist.scheduledAt,
        notes: setlist.notes,
        entries: setlist.entries,
      ),
    );
    if (mounted) setState(_reload);
  }

  Future<void> _delete(LibrarySetlist setlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete setlist?'),
        content: Text('Delete "${setlist.name}"? Songs remain in Song Pool.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.services.setlists.deleteSetlist(setlist.id);
    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Gigs & Setlists',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 6),
        const Text(
          'Songs stay in the pool; setlists reference them in performance order.',
        ),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.add),
            label: const Text('Create setlist'),
          ),
        ),
        const SizedBox(height: 16),
        FutureBuilder<List<LibrarySetlist>>(
          future: _setlists,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Card(
                child: ListTile(
                  title: const Text('Setlists could not be loaded'),
                  subtitle: Text('${snapshot.error}'),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.data!.isEmpty) {
              return const Card(
                child: ListTile(
                  leading: Icon(Icons.queue_music_outlined),
                  title: Text('No setlists yet'),
                  subtitle: Text(
                    'Create one, then add songs from your Song Pool.',
                  ),
                ),
              );
            }
            return Column(
              children: [
                for (final setlist in snapshot.data!)
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.queue_music),
                      ),
                      title: Text(setlist.name),
                      subtitle: Text('${setlist.entries.length} set item(s)'),
                      onTap: () => _open(setlist),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Setlist actions',
                        onSelected: (action) {
                          if (action == 'rename') _rename(setlist);
                          if (action == 'delete') _delete(setlist);
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 'rename', child: Text('Rename')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SetlistEditorScreen extends StatefulWidget {
  const _SetlistEditorScreen({
    required this.services,
    required this.setlistId,
    required this.preferences,
  });
  final AppServices services;
  final String setlistId;
  final DevicePreferences preferences;

  @override
  State<_SetlistEditorScreen> createState() => _SetlistEditorScreenState();
}

class _SetlistEditorScreenState extends State<_SetlistEditorScreen> {
  LibrarySetlist? _setlist;
  Map<String, VisualChartDraft> _draftsByVariant = const {};
  List<VisualChartDraft> _availableDrafts = const [];
  Object? _error;
  var _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final setlist = await widget.services.setlists.loadSetlist(
        widget.setlistId,
      );
      final drafts = await widget.services.library.listDrafts();
      final byVariant = <String, VisualChartDraft>{};
      for (final draft in drafts) {
        final identity = await widget.services.songVariants.identityForDraft(
          draft.id,
        );
        if (identity != null) {
          byVariant[identity.id] = draft;
        }
      }
      if (!mounted) return;
      setState(() {
        _setlist = setlist;
        _availableDrafts = drafts;
        _draftsByVariant = byVariant;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _saveEntries(List<LibrarySetlistEntry> entries) async {
    final current = _setlist!;
    final updated = LibrarySetlist(
      id: current.id,
      name: current.name,
      createdAt: current.createdAt,
      updatedAt: DateTime.now().toUtc(),
      scheduledAt: current.scheduledAt,
      notes: current.notes,
      entries: entries,
    );
    await widget.services.setlists.saveSetlist(updated);
    if (mounted) setState(() => _setlist = updated);
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
    if (identity == null || !mounted) {
      return;
    }
    await _saveEntries([
      ..._setlist!.entries,
      LibrarySetlistEntry(
        id: IdFactory.next('entry'),
        chartVariantId: identity.id,
      ),
    ]);
  }

  Future<String?> _askPlaceholderName({String initial = ''}) async {
    var name = initial;
    var showEmptyError = false;
    return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void submit() {
            final value = name.trim();
            if (value.isEmpty) {
              setDialogState(() => showEmptyError = true);
              return;
            }
            Navigator.pop(context, value);
          }

          return AlertDialog(
            title: Text(
              initial.isEmpty ? 'Add setlist placeholder' : 'Edit placeholder',
            ),
            content: TextFormField(
              initialValue: initial,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Song or set item name',
                helperText: 'Use this for songs you are not playing.',
                errorText: showEmptyError ? 'Enter a placeholder name.' : null,
              ),
              onChanged: (value) {
                name = value;
                if (showEmptyError) {
                  setDialogState(() => showEmptyError = false);
                }
              },
              onFieldSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(onPressed: submit, child: const Text('Save')),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addPlaceholder() async {
    final name = await _askPlaceholderName();
    if (name == null || name.trim().isEmpty) return;
    await _saveEntries([
      ..._setlist!.entries,
      LibrarySetlistEntry.placeholder(
        id: IdFactory.next('entry'),
        title: name.trim(),
      ),
    ]);
  }

  Future<void> _editPlaceholder(int index) async {
    final current = _setlist!.entries[index];
    if (current.kind != SetlistEntryKind.placeholder) return;
    final name = await _askPlaceholderName(
      initial: current.placeholderTitle ?? '',
    );
    if (name == null || name.trim().isEmpty) return;
    final entries = List<LibrarySetlistEntry>.of(_setlist!.entries);
    entries[index] = LibrarySetlistEntry.placeholder(
      id: current.id,
      title: name.trim(),
    );
    await _saveEntries(entries);
  }

  Future<void> _remove(int index) async {
    final entries = List<LibrarySetlistEntry>.of(_setlist!.entries)
      ..removeAt(index);
    await _saveEntries(entries);
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final entries = List<LibrarySetlistEntry>.of(_setlist!.entries);
    final moved = entries.removeAt(oldIndex);
    entries.insert(newIndex, moved);
    final reorderedAt = DateTime.now().toUtc();
    await widget.services.setlists.reorderSetlistEntries(
      _setlist!.id,
      entries.map((entry) => entry.id).toList(),
      updatedAt: reorderedAt,
    );
    if (mounted) {
      setState(
        () => _setlist = LibrarySetlist(
          id: _setlist!.id,
          name: _setlist!.name,
          createdAt: _setlist!.createdAt,
          updatedAt: reorderedAt,
          scheduledAt: _setlist!.scheduledAt,
          notes: _setlist!.notes,
          entries: entries,
        ),
      );
    }
  }

  Future<VisualExportDensity?> _chooseExportDensity() {
    return showDialog<VisualExportDensity>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Setlist PDF density'),
        children: [
          for (final density in VisualExportDensity.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, density),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  density == VisualExportDensity.stageReadable
                      ? Icons.visibility
                      : Icons.picture_as_pdf_outlined,
                ),
                title: Text(density.label),
                subtitle: Text(switch (density) {
                  VisualExportDensity.original =>
                    'Portrait A4 using the MVP row sizing.',
                  VisualExportDensity.balanced =>
                    'Portrait A4 with a readability floor.',
                  VisualExportDensity.stageReadable =>
                    'Landscape A4 with the largest stage-readable rows.',
                }),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _exportSetlist() async {
    final density = await _chooseExportDensity();
    if (density == null || !mounted) return;
    setState(() => _exporting = true);
    try {
      final path = await widget.services.setlistExporter
          .exportSetlistWithPicker(_setlist!, density: density);
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Exported setlist PDF to $path')));
    } catch (error) {
      if (!mounted) return;
      final message = error is SetlistPdfExportException
          ? error.message
          : 'The setlist PDF could not be exported: $error';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _openPerformancePreview() async {
    final density = await _chooseExportDensity();
    if (density == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PerformancePreviewScreen(
          services: widget.services,
          setlist: _setlist!,
          density: density,
          preferences: widget.preferences,
        ),
      ),
    );
  }

  Future<void> _startGigMode() async {
    final density = await _chooseExportDensity();
    if (density == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GigModeScreen(
          services: widget.services,
          setlist: _setlist!,
          density: density,
          preferences: widget.preferences,
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Setlist')),
        body: Center(child: Text('Setlist could not be loaded: $_error')),
      );
    }
    final setlist = _setlist;
    if (setlist == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(setlist.name),
        actions: [
          IconButton(
            tooltip: 'Start gig mode',
            onPressed: _exporting ? null : _startGigMode,
            icon: const Icon(Icons.play_circle_outline),
          ),
          IconButton(
            tooltip: 'Open performance preview',
            onPressed: _exporting ? null : _openPerformancePreview,
            icon: const Icon(Icons.present_to_all),
          ),
          if (_exporting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Center(
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Export setlist A4 PDF',
              onPressed: _exportSetlist,
              icon: const Icon(Icons.picture_as_pdf),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${setlist.entries.length} set item(s)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                FilledButton.icon(
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
          Expanded(
            child: SetlistSidebar(
              setlist: setlist,
              draftsByVariant: _draftsByVariant,
              onRemove: _remove,
              onEditPlaceholder: _editPlaceholder,
              onReorder: _reorder,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportSource extends StatefulWidget {
  const _ImportSource({required this.onStartVisual});

  final ValueChanged<VisualChartDraft?> onStartVisual;

  @override
  State<_ImportSource> createState() => _ImportSourceState();
}

class _ImportSourceState extends State<_ImportSource> {
  final _urlController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _startFromUrl() {
    try {
      final url = normalizeSourceUrl(_urlController.text);
      final now = DateTime.now().toUtc();
      widget.onStartVisual(
        VisualChartDraft(
          id: IdFactory.next('chart'),
          title: 'Untitled chart',
          artist: '',
          createdAt: now,
          updatedAt: now,
          provenance: SourceProvenance(
            url: url,
            provider: inferSourceProvider(url),
          ),
        ),
      );
    } on FormatException catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('New / Import', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        const Text(
          'Store a source link locally, then attach screenshots or PDFs. '
          'Music Tabbler never fetches the link.',
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _urlController,
          keyboardType: TextInputType.url,
          onSubmitted: (_) => _startFromUrl(),
          decoration: InputDecoration(
            labelText: 'Paste a specific tab or video URL',
            hintText: 'https://www.songsterr.com/...',
            prefixIcon: const Icon(Icons.link),
            suffixIcon: IconButton(
              tooltip: 'Create local source record',
              onPressed: _startFromUrl,
              icon: const Icon(Icons.arrow_forward),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _ImportCard(
              icon: Icons.view_stream_outlined,
              title: 'Visual chart workflow',
              detail:
                  'Import images, clipboard screenshots, or PDF pages; crop and arrange rows.',
              buttonLabel: 'Start',
              onPressed: () => widget.onStartVisual(null),
            ),
            const _ImportCard(
              icon: Icons.auto_fix_high_outlined,
              title: 'Semantic recognition',
              detail:
                  'OCR and note conversion will build on saved source assets later.',
            ),
            const _ImportCard(
              icon: Icons.search,
              title: 'Search sources',
              detail: 'Secondary workflow when no specific version is chosen.',
            ),
          ],
        ),
      ],
    );
  }
}

class _ImportCard extends StatelessWidget {
  const _ImportCard({
    required this.icon,
    required this.title,
    required this.detail,
    this.buttonLabel,
    this.onPressed,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String? buttonLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 30),
              const SizedBox(height: 14),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(detail),
              if (buttonLabel != null) ...[
                const SizedBox(height: 14),
                FilledButton(onPressed: onPressed, child: Text(buttonLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
