import 'package:flutter/material.dart';

import '../chart/chart_editor_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onToggleTheme,
    required this.isDark,
  });

  final VoidCallback onToggleTheme;
  final bool isDark;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  var _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      _SongPool(
        onOpenChart: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ChartEditorScreen(
              onToggleTheme: widget.onToggleTheme,
              isDark: widget.isDark,
            ),
          ),
        ),
      ),
      const _GigsAndSetlists(),
      const _ImportSource(),
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
  const _SongPool({required this.onOpenChart});

  final VoidCallback onOpenChart;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Song Pool', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(
          'Processed songs, tunings, chart variants, lyrics and annotations.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.music_note)),
            title: const Text('Foundation Groove'),
            subtitle: const Text(
              'Music Tabbler • 5-string BEADG • Semantic sample',
            ),
            trailing: FilledButton(
              onPressed: onOpenChart,
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
              'Setlist and gig mode will be built on this shared shell.',
            ),
          ),
        ),
      ],
    );
  }
}

class _ImportSource extends StatelessWidget {
  const _ImportSource();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('New / Import', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        const Text(
          'A chosen source link comes first; local material is always available as fallback.',
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
        const Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _ImportCard(
              icon: Icons.image_outlined,
              title: 'Screenshots & images',
              detail: 'PNG and JPEG crop/arrange is the first importer.',
            ),
            _ImportCard(
              icon: Icons.picture_as_pdf_outlined,
              title: 'PDF score or tab',
              detail: 'Extract visual regions, then convert or retain them.',
            ),
            _ImportCard(
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
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
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
            ],
          ),
        ),
      ),
    );
  }
}
