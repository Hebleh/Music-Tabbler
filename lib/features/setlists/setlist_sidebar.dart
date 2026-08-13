import 'package:flutter/material.dart';

import '../../domain/library_models.dart';
import '../../domain/visual_chart_models.dart';

/// The ordered set view used by the setlist editor and, later, gig mode.
///
/// This widget owns no persistence or navigation. Its parent supplies the
/// callbacks, which keeps the same ordering surface reusable as a gig sidebar.
class SetlistSidebar extends StatelessWidget {
  const SetlistSidebar({
    super.key,
    required this.setlist,
    required this.draftsByVariant,
    required this.onRemove,
    required this.onEditPlaceholder,
    required this.onReorder,
    this.onEntryTap,
    this.selectedEntryId,
  });

  final LibrarySetlist setlist;
  final Map<String, VisualChartDraft> draftsByVariant;
  final ValueChanged<int> onRemove;
  final ValueChanged<int> onEditPlaceholder;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<int>? onEntryTap;
  final String? selectedEntryId;

  @override
  Widget build(BuildContext context) {
    if (setlist.entries.isEmpty) {
      return const Center(
        child: Text(
          'This setlist is empty. Add a song or a non-playing placeholder.',
        ),
      );
    }
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: setlist.entries.length,
      onReorderItem: onReorder,
      buildDefaultDragHandles: false,
      itemBuilder: (context, index) {
        final entry = setlist.entries[index];
        final isPlaceholder = entry.kind == SetlistEntryKind.placeholder;
        final draft = isPlaceholder
            ? null
            : draftsByVariant[entry.chartVariantId];
        final title = isPlaceholder
            ? entry.placeholderTitle!
            : draft == null
            ? 'Missing chart'
            : draft.displayTitle;
        final subtitle = isPlaceholder
            ? 'Not playing'
            : draft == null
            ? 'Referenced chart is unavailable (${entry.chartVariantId})'
            : draft.artist.trim().isEmpty
            ? null
            : draft.artist;
        return Card(
          key: ValueKey(entry.id),
          color: isPlaceholder
              ? Colors.red.shade100
              : entry.id == selectedEntryId
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          child: ListTile(
            onTap: onEntryTap == null ? null : () => onEntryTap!(index),
            leading: CircleAvatar(
              backgroundColor: isPlaceholder ? Colors.red.shade300 : null,
              foregroundColor: isPlaceholder ? Colors.black87 : null,
              child: Text('${index + 1}'),
            ),
            title: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: isPlaceholder
                  ? const TextStyle(color: Colors.black87)
                  : null,
            ),
            subtitle: subtitle == null
                ? null
                : Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: isPlaceholder
                        ? const TextStyle(color: Colors.black54)
                        : null,
                  ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isPlaceholder)
                  IconButton(
                    tooltip: 'Edit placeholder',
                    color: Colors.black87,
                    onPressed: () => onEditPlaceholder(index),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                IconButton(
                  tooltip: 'Remove from setlist',
                  color: isPlaceholder ? Colors.black87 : null,
                  onPressed: () => onRemove(index),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: Tooltip(
                    message: 'Drag to reorder',
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(
                        Icons.drag_handle,
                        color: isPlaceholder ? Colors.black87 : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
