import 'package:flutter/material.dart';

import '../../application/app_services.dart';
import '../../domain/visual_chart_models.dart';
import '../chart/chart_editor_screen.dart';
import '../import/visual_import_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.services,
    required this.onToggleTheme,
    required this.isDark,
  });

  final AppServices services;
  final VoidCallback onToggleTheme;
  final bool isDark;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  var _selectedIndex = 0;
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
    await widget.services.library.deleteDraft(draft.id);
    if (!mounted) return;
    setState(_reloadDrafts);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Deleted "${draft.title}" from Song Pool.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _SongPool(
        drafts: _drafts,
        onOpenVisual: _openVisualEditor,
        onDeleteVisual: _deleteVisualDraft,
        onOpenSemantic: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ChartEditorScreen(
              onToggleTheme: widget.onToggleTheme,
              isDark: widget.isDark,
            ),
          ),
        ),
      ),
      const _GigsAndSetlists(),
      _ImportSource(onStartVisual: _openVisualEditor),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 840;
        final content = Scaffold(
          appBar: AppBar(
            title: const Text('Music Tabbler'),
            actions: [
              IconButton(
                tooltip: widget.isDark ? 'Use light theme' : 'Use dark theme',
                onPressed: widget.onToggleTheme,
                icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode),
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
    required this.onOpenSemantic,
  });

  final Future<List<VisualChartDraft>> drafts;
  final ValueChanged<VisualChartDraft?> onOpenVisual;
  final ValueChanged<VisualChartDraft> onDeleteVisual;
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
            FilledButton.icon(
              onPressed: () => onOpenVisual(null),
              icon: const Icon(Icons.add),
              label: const Text('New visual chart'),
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
                      title: Text(draft.title),
                      subtitle: Text(
                        '${draft.artist.isEmpty ? 'Unknown artist' : draft.artist} - ${draft.strips.length} row(s)',
                      ),
                      trailing: Wrap(
                        spacing: 8,
                        children: [
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

class _GigsAndSetlists extends StatelessWidget {
  const _GigsAndSetlists();

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
        const Card(
          child: ListTile(
            leading: Icon(Icons.event),
            title: Text('16 August 2026'),
            subtitle: Text(
              'Setlist persistence and gig mode are a later slice.',
            ),
          ),
        ),
      ],
    );
  }
}

class _ImportSource extends StatelessWidget {
  const _ImportSource({required this.onStartVisual});

  final ValueChanged<VisualChartDraft?> onStartVisual;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('New / Import', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        const Text(
          'Local screenshot and PDF import is available now. Source links remain future adapters.',
        ),
        const SizedBox(height: 24),
        TextField(
          decoration: InputDecoration(
            labelText: 'Paste a specific tab or video URL',
            hintText: 'Songsterr, Ultimate Guitar, YouTube, or a future source',
            prefixIcon: const Icon(Icons.link),
            suffixIcon: IconButton(
              tooltip: 'Source adapters are not implemented yet',
              onPressed: null,
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
              onPressed: () => onStartVisual(null),
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
