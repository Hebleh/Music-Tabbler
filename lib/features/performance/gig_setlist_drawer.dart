import 'package:flutter/material.dart';

import '../../domain/library_models.dart';
import '../../domain/visual_chart_models.dart';
import '../setlists/setlist_sidebar.dart';

/// Presentation-only setlist drawer used by Gig Mode.
///
/// The parent owns navigation and every mutation. Keeping those callbacks out
/// of this widget leaves the drawer reusable without creating a second setlist
/// session or viewport owner.
class GigSetlistDrawer extends StatelessWidget {
  const GigSetlistDrawer({
    super.key,
    required this.setlist,
    required this.draftsByVariant,
    required this.selectedEntryId,
    required this.titleStyle,
    required this.onClose,
    required this.onAddSong,
    required this.onAddPlaceholder,
    required this.onEntryTap,
    required this.onRemove,
    required this.onEditPlaceholder,
    required this.onReorder,
  });

  final LibrarySetlist setlist;
  final Map<String, VisualChartDraft> draftsByVariant;
  final String selectedEntryId;
  final TextStyle? titleStyle;
  final VoidCallback onClose;
  final VoidCallback onAddSong;
  final VoidCallback onAddPlaceholder;
  final ValueChanged<int> onEntryTap;
  final ValueChanged<int> onRemove;
  final ValueChanged<int> onEditPlaceholder;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 420,
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              title: Text(setlist.name, style: titleStyle),
              subtitle: const Text('Tap a song to jump to it.'),
              trailing: IconButton(
                tooltip: 'Close setlist sidebar',
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: onAddSong,
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('Add song'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: onAddPlaceholder,
                    icon: const Icon(Icons.not_interested),
                    label: const Text('Add placeholder'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SetlistSidebar(
                setlist: setlist,
                draftsByVariant: draftsByVariant,
                selectedEntryId: selectedEntryId,
                onEntryTap: onEntryTap,
                onRemove: onRemove,
                onEditPlaceholder: onEditPlaceholder,
                onReorder: onReorder,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
