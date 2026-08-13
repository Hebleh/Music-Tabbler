import 'package:flutter/material.dart';

import '../../domain/visual_tab_transform_models.dart';

class VisualAnalysisToolbar extends StatelessWidget {
  const VisualAnalysisToolbar({
    super.key,
    required this.analyses,
    required this.currentIndex,
    required this.analysis,
    required this.rerunningSource,
    required this.drawing,
    required this.stripCount,
    required this.selectedTokenCount,
    required this.onRowSelected,
    required this.onRerunCurrent,
    required this.onRerunAll,
    required this.onDrawingChanged,
    required this.onEdit,
    required this.onMerge,
    required this.onSplit,
    required this.onDelete,
  });

  final List<VisualTabAnalysis?> analyses;
  final int currentIndex;
  final VisualTabAnalysis analysis;
  final bool rerunningSource;
  final bool drawing;
  final int stripCount;
  final int selectedTokenCount;
  final ValueChanged<int> onRowSelected;
  final VoidCallback onRerunCurrent;
  final VoidCallback onRerunAll;
  final ValueChanged<bool> onDrawingChanged;
  final VoidCallback onEdit;
  final VoidCallback onMerge;
  final VoidCallback onSplit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<int>(
              value: currentIndex,
              items: [
                for (var index = 0; index < analyses.length; index += 1)
                  DropdownMenuItem(
                    value: index,
                    enabled: analyses[index] != null,
                    child: Text('Row ${index + 1}'),
                  ),
              ],
              onChanged: (value) {
                if (value != null) onRowSelected(value);
              },
            ),
            Chip(
              avatar: Icon(
                analysis.sourceType == VisualTabSourceType.positionedPdf
                    ? Icons.picture_as_pdf_outlined
                    : Icons.document_scanner_outlined,
              ),
              label: Text(
                analysis.sourceType == VisualTabSourceType.positionedPdf
                    ? 'Positioned PDF text'
                    : 'Raster / OCR',
              ),
            ),
            Text(
              '${analysis.systems.length} system(s), '
              '${analysis.enabledFretTokenCount} fret/dead-note token(s)',
            ),
            OutlinedButton.icon(
              onPressed: rerunningSource ? null : onRerunCurrent,
              icon: rerunningSource
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.document_scanner_outlined),
              label: const Text('Use raster / OCR'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('raster-ocr-all-rows'),
              onPressed: rerunningSource || stripCount == 0 ? null : onRerunAll,
              icon: const Icon(Icons.document_scanner),
              label: const Text('Raster / OCR all rows'),
            ),
            FilterChip(
              selected: drawing,
              avatar: const Icon(Icons.add_box_outlined),
              label: const Text('Draw missing token'),
              onSelected: onDrawingChanged,
            ),
            OutlinedButton.icon(
              onPressed: selectedTokenCount == 1 ? onEdit : null,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit'),
            ),
            OutlinedButton.icon(
              onPressed: selectedTokenCount > 1 ? onMerge : null,
              icon: const Icon(Icons.call_merge),
              label: const Text('Merge'),
            ),
            OutlinedButton.icon(
              onPressed: selectedTokenCount == 1 ? onSplit : null,
              icon: const Icon(Icons.call_split),
              label: const Text('Separate'),
            ),
            OutlinedButton.icon(
              onPressed: selectedTokenCount == 0 ? null : onDelete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }
}
