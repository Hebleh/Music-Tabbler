import 'package:flutter/material.dart';

import '../../application/gig_viewport_layout.dart';
import 'performance_preview_screen.dart';

/// Presentation-only command row for unlocked Gig Mode.
///
/// Every mutation and navigation decision is supplied by the parent. This
/// widget only reflects the current viewport/annotation state and forwards the
/// selected command.
class GigCommandBar extends StatelessWidget {
  const GigCommandBar({
    super.key,
    required this.dark,
    required this.alignment,
    required this.annotationTool,
    required this.canAnnotate,
    required this.canUndo,
    required this.annotationsVisible,
    required this.annotationsIncludedInPdf,
    required this.pageNumber,
    required this.pageCount,
    required this.onOpenSetlist,
    required this.onExit,
    required this.onToggleTheme,
    required this.onLockStage,
    required this.onAlignmentChanged,
    required this.onAnnotationToolChanged,
    required this.onUndo,
    required this.onToggleAnnotationVisibility,
    required this.onToggleAnnotationPdfInclusion,
    required this.onClearAllPerformanceNotes,
    required this.onPrevious,
    required this.onNext,
  });

  final bool dark;
  final GigHorizontalAlignment alignment;
  final AnnotationTool annotationTool;
  final bool canAnnotate;
  final bool canUndo;
  final bool annotationsVisible;
  final bool annotationsIncludedInPdf;
  final int pageNumber;
  final int pageCount;
  final VoidCallback onOpenSetlist;
  final VoidCallback onExit;
  final VoidCallback onToggleTheme;
  final VoidCallback onLockStage;
  final ValueChanged<GigHorizontalAlignment> onAlignmentChanged;
  final ValueChanged<AnnotationTool> onAnnotationToolChanged;
  final VoidCallback? onUndo;
  final VoidCallback? onToggleAnnotationVisibility;
  final VoidCallback? onToggleAnnotationPdfInclusion;
  final VoidCallback onClearAllPerformanceNotes;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  Color _selectedColor(bool selected) => selected ? Colors.amber : Colors.white;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Open setlist sidebar',
            onPressed: onOpenSetlist,
            color: Colors.white,
            icon: const Icon(Icons.queue_music),
          ),
          TextButton(onPressed: onExit, child: const Text('Exit')),
          IconButton(
            tooltip: dark
                ? 'Use dark-on-light gig theme'
                : 'Use light-on-black gig theme',
            onPressed: onToggleTheme,
            color: Colors.white,
            icon: Icon(dark ? Icons.light_mode : Icons.dark_mode),
          ),
          IconButton(
            tooltip: 'Lock stage controls',
            onPressed: onLockStage,
            color: Colors.white,
            icon: const Icon(Icons.lock_open),
          ),
          IconButton(
            tooltip: 'Align bars left',
            onPressed: () => onAlignmentChanged(GigHorizontalAlignment.left),
            color: _selectedColor(alignment == GigHorizontalAlignment.left),
            icon: const Icon(Icons.format_align_left),
          ),
          IconButton(
            tooltip: 'Align bars center',
            onPressed: () => onAlignmentChanged(GigHorizontalAlignment.center),
            color: _selectedColor(alignment == GigHorizontalAlignment.center),
            icon: const Icon(Icons.format_align_center),
          ),
          IconButton(
            tooltip: 'Align bars right',
            onPressed: () => onAlignmentChanged(GigHorizontalAlignment.right),
            color: _selectedColor(alignment == GigHorizontalAlignment.right),
            icon: const Icon(Icons.format_align_right),
          ),
          IconButton(
            tooltip: 'Draw annotations',
            onPressed: canAnnotate
                ? () => onAnnotationToolChanged(
                    annotationTool == AnnotationTool.draw
                        ? AnnotationTool.none
                        : AnnotationTool.draw,
                  )
                : null,
            color: _selectedColor(annotationTool == AnnotationTool.draw),
            icon: const Icon(Icons.draw),
          ),
          IconButton(
            tooltip: 'Highlight performance notes',
            onPressed: canAnnotate
                ? () => onAnnotationToolChanged(
                    annotationTool == AnnotationTool.highlight
                        ? AnnotationTool.none
                        : AnnotationTool.highlight,
                  )
                : null,
            color: _selectedColor(annotationTool == AnnotationTool.highlight),
            icon: const Icon(Icons.border_color),
          ),
          IconButton(
            tooltip: 'Erase annotations',
            onPressed: canAnnotate
                ? () => onAnnotationToolChanged(
                    annotationTool == AnnotationTool.erase
                        ? AnnotationTool.none
                        : AnnotationTool.erase,
                  )
                : null,
            color: _selectedColor(annotationTool == AnnotationTool.erase),
            icon: const Icon(Icons.auto_fix_normal),
          ),
          IconButton(
            tooltip: 'Undo annotation',
            onPressed: canUndo ? onUndo : null,
            color: Colors.white,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: annotationsVisible
                ? 'Hide annotations'
                : 'Show annotations',
            onPressed: onToggleAnnotationVisibility,
            color: Colors.white,
            icon: Icon(
              annotationsVisible ? Icons.visibility : Icons.visibility_off,
            ),
          ),
          IconButton(
            tooltip: annotationsIncludedInPdf
                ? 'Exclude annotations from PDF'
                : 'Include annotations in PDF',
            onPressed: onToggleAnnotationPdfInclusion,
            color: _selectedColor(annotationsIncludedInPdf),
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
          IconButton(
            tooltip: 'Clear all performance notes',
            onPressed: onClearAllPerformanceNotes,
            color: Colors.white,
            icon: const Icon(Icons.layers_clear),
          ),
          IconButton(
            tooltip: 'Previous page',
            onPressed: onPrevious,
            color: Colors.white,
            icon: const Icon(Icons.arrow_back),
          ),
          Text(
            '$pageNumber / $pageCount',
            style: const TextStyle(color: Colors.white),
          ),
          IconButton(
            tooltip: 'Next page',
            onPressed: onNext,
            color: Colors.white,
            icon: const Icon(Icons.arrow_forward),
          ),
        ],
      ),
    );
  }
}
