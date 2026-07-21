import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/highlight_geometry.dart';
import '../../application/service_contracts.dart';
import '../../domain/visual_chart_models.dart';
import 'resizable_rect_overlay.dart';
import 'visual_strip_preview.dart';

class TextHighlightSelection {
  const TextHighlightSelection({
    required this.rectsByStrip,
    required this.includeTabBelow,
  });

  final Map<String, List<NormalizedRect>> rectsByStrip;
  final bool includeTabBelow;
}

class TextHighlighterDialog extends StatefulWidget {
  const TextHighlighterDialog({
    super.key,
    required this.strips,
    required this.library,
    required this.textRecognition,
    this.globalTreatment,
  });

  final List<VisualStrip> strips;
  final ChartLibrary library;
  final TextRecognitionService textRecognition;
  final VisualTreatment? globalTreatment;

  @override
  State<TextHighlighterDialog> createState() => _TextHighlighterDialogState();
}

class _TextHighlighterDialogState extends State<TextHighlighterDialog> {
  final Map<String, Future<MetadataSuggestion>> _recognitions = {};
  late final Map<String, _RowHighlightState> _rows;
  bool _includeTabBelow = false;
  bool _freeform = true;
  String? _activeRowId;

  @override
  void initState() {
    super.initState();
    _rows = {
      for (final strip in widget.strips)
        strip.id: _RowHighlightState(
          boxes: strip.highlights
              .map(
                (highlight) => assetRectToCropLocal(highlight.rect, strip.crop),
              )
              .whereType<NormalizedRect>()
              .toList(),
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.backspace):
            _deleteActiveHighlight,
        const SingleActivator(LogicalKeyboardKey.delete):
            _deleteActiveHighlight,
      },
      child: Focus(
        autofocus: true,
        child: AlertDialog(
          title: const Text('Backing-vocal chart highlighter'),
          content: SizedBox(
            width: 1100,
            height: 720,
            child: Column(
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.text_fields),
                      label: Text('Recognized text'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.crop_free),
                      label: Text('Freeform / edit boxes'),
                    ),
                  ],
                  selected: {_freeform},
                  onSelectionChanged: (value) => setState(() {
                    _freeform = value.single;
                    _clearDragState();
                  }),
                ),
                const SizedBox(height: 8),
                Text(
                  _freeform
                      ? 'Draw, select, move, and resize highlight boxes on any current chart row.'
                      : 'Click words or drag across separated lyric fragments. OCR remains an editable proposal.',
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    itemCount: widget.strips.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) =>
                        _buildRow(widget.strips[index], index),
                  ),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _includeTabBelow,
                  onChanged: (value) =>
                      setState(() => _includeTabBelow = value ?? false),
                  title: const Text(
                    'Also highlight the corresponding tab below',
                  ),
                  subtitle: const Text(
                    'Extends selected OCR word highlights downward in the same row and horizontal position.',
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${_selectedTextCount()} text region(s), ${_boxCount()} editable box(es)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(onPressed: _clearAll, child: const Text('Clear all')),
            FilledButton.icon(
              onPressed: () => Navigator.pop(
                context,
                TextHighlightSelection(
                  rectsByStrip: _selectionByStrip(),
                  includeTabBelow: _includeTabBelow,
                ),
              ),
              icon: const Icon(Icons.highlight_alt),
              label: const Text('Apply highlights'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(VisualStrip strip, int index) {
    final row = _rows[strip.id]!;
    final recognition = _recognitions.putIfAbsent(
      strip.id,
      () => widget.textRecognition.recognize(strip),
    );
    final previewStrip = strip.copyWith(
      clearLyricBand: true,
      lyricContrast: 1,
      highlights: const [],
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Row ${index + 1}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                Text(
                  '${row.selectedText.length} word(s), ${row.boxes.length} box(es)',
                ),
                if (_freeform) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Delete selected box',
                    onPressed:
                        _activeRowId == strip.id && row.selectedBox != null
                        ? () => _deleteSelectedBox(strip.id)
                        : null,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
                IconButton(
                  tooltip: 'Clear this row',
                  onPressed: row.selectedText.isEmpty && row.boxes.isEmpty
                      ? null
                      : () => setState(row.clear),
                  icon: const Icon(Icons.layers_clear_outlined),
                ),
              ],
            ),
            FutureBuilder<MetadataSuggestion>(
              future: recognition,
              builder: (context, snapshot) {
                final regions =
                    snapshot.data?.regions ?? const <RecognizedTextRegion>[];
                row.regions = regions;
                return AspectRatio(
                  aspectRatio: strip.croppedAspectRatio,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: _freeform
                            ? null
                            : (details) => _toggleAt(
                                strip.id,
                                _normalized(details.localPosition, size),
                              ),
                        onPanStart: (details) =>
                            _startDrag(strip.id, details.localPosition),
                        onPanUpdate: (details) =>
                            _updateDrag(strip.id, details.localPosition, size),
                        onPanEnd: (_) => _finishDrag(strip.id),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            VisualStripPreview(
                              library: widget.library,
                              strip: previewStrip,
                              globalTreatment: widget.globalTreatment,
                            ),
                            CustomPaint(
                              painter: _TextRegionPainter(
                                regions: regions,
                                selected: row.selectedText,
                                dragRect: row.dragRect,
                                boxes: row.boxes,
                                showBoxHandles: _freeform,
                              ),
                            ),
                            if (_freeform)
                              for (final boxIndex in row.paintOrder)
                                ResizableRectOverlay(
                                  rect: row.boxes[boxIndex],
                                  canvasSize: size,
                                  selected:
                                      _activeRowId == strip.id &&
                                      row.selectedBox == boxIndex,
                                  onSelected: () => setState(() {
                                    _activeRowId = strip.id;
                                    row.selectedBox = boxIndex;
                                  }),
                                  onChanged: (value) => setState(() {
                                    _activeRowId = strip.id;
                                    row.selectedBox = boxIndex;
                                    row.boxes[boxIndex] = value;
                                    row.selectedText.removeWhere(
                                      (index) => _intersects(
                                        value,
                                        row.regions[index].rect,
                                      ),
                                    );
                                  }),
                                ),
                            if (!snapshot.hasData && !snapshot.hasError)
                              const Align(
                                alignment: Alignment.topRight,
                                child: Padding(
                                  padding: EdgeInsets.all(6),
                                  child: SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              ),
                            if (snapshot.hasError)
                              const Align(
                                alignment: Alignment.topRight,
                                child: Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Chip(
                                    label: Text(
                                      'OCR unavailable; use freeform',
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _toggleAt(String rowId, Offset point) {
    final row = _rows[rowId]!;
    for (var index = row.regions.length - 1; index >= 0; index -= 1) {
      if (_contains(row.regions[index].rect, point)) {
        setState(() {
          _activeRowId = rowId;
          if (row.boxes.any(
            (box) => _intersects(box, row.regions[index].rect),
          )) {
            row.selectedText.remove(index);
            return;
          }
          if (!row.selectedText.add(index)) row.selectedText.remove(index);
        });
        return;
      }
    }
  }

  void _startDrag(String rowId, Offset point) {
    final row = _rows[rowId]!;
    _activeRowId = rowId;
    row.dragStart = point;
    setState(() => row.dragRect = null);
  }

  void _updateDrag(String rowId, Offset current, Size size) {
    final row = _rows[rowId]!;
    final start = row.dragStart;
    if (start == null) return;
    final first = _normalized(start, size);
    final second = _normalized(current, size);
    final rect = NormalizedRect(
      first.dx < second.dx ? first.dx : second.dx,
      first.dy < second.dy ? first.dy : second.dy,
      first.dx > second.dx ? first.dx : second.dx,
      first.dy > second.dy ? first.dy : second.dy,
    ).clamp();
    setState(() {
      row.dragRect = rect;
      if (!_freeform) {
        for (var index = 0; index < row.regions.length; index += 1) {
          if (_intersects(rect, row.regions[index].rect)) {
            row.selectedText.add(index);
          }
        }
      }
    });
  }

  void _finishDrag(String rowId) {
    final row = _rows[rowId]!;
    final rect = row.dragRect;
    setState(() {
      if (_freeform &&
          rect != null &&
          rect.width > 0.004 &&
          rect.height > 0.004) {
        var merged = rect;
        final overlappingBoxes = <NormalizedRect>[];
        for (final box in row.boxes) {
          if (_intersects(merged, box)) overlappingBoxes.add(box);
        }
        for (final box in overlappingBoxes) {
          merged = _union(merged, box);
          row.boxes.remove(box);
        }
        row.selectedText.removeWhere(
          (index) => _intersects(merged, row.regions[index].rect),
        );
        row.boxes.add(merged);
        row.selectedBox = row.boxes.length - 1;
        _activeRowId = rowId;
      }
      row.dragRect = null;
      row.dragStart = null;
    });
  }

  void _deleteSelectedBox(String rowId) {
    final row = _rows[rowId]!;
    final index = row.selectedBox;
    if (index == null) return;
    setState(() {
      row.boxes.removeAt(index);
      row.selectedBox = row.boxes.isEmpty
          ? null
          : index.clamp(0, row.boxes.length - 1);
    });
  }

  void _deleteActiveHighlight() {
    final rowId = _activeRowId;
    if (rowId == null) return;
    final row = _rows[rowId]!;
    if (row.selectedBox != null) {
      _deleteSelectedBox(rowId);
      return;
    }
    if (row.selectedText.isEmpty) return;
    setState(row.selectedText.clear);
  }

  void _clearAll() {
    setState(() {
      for (final row in _rows.values) {
        row.clear();
      }
      _activeRowId = null;
    });
  }

  void _clearDragState() {
    for (final row in _rows.values) {
      row.dragRect = null;
      row.dragStart = null;
    }
  }

  Map<String, List<NormalizedRect>> _selectionByStrip() {
    return {
      for (final strip in widget.strips)
        strip.id: [
          ..._rows[strip.id]!.boxes,
          for (final index in _rows[strip.id]!.selectedText)
            if (!_rows[strip.id]!.boxes.any(
              (box) => _intersects(box, _rows[strip.id]!.regions[index].rect),
            ))
              _includeTabBelow
                  ? _withTabBelow(_rows[strip.id]!.regions[index].rect)
                  : _rows[strip.id]!.regions[index].rect,
        ],
    };
  }

  int _selectedTextCount() =>
      _rows.values.fold(0, (total, row) => total + row.selectedText.length);

  int _boxCount() =>
      _rows.values.fold(0, (total, row) => total + row.boxes.length);

  Offset _normalized(Offset point, Size size) => Offset(
    (point.dx / size.width).clamp(0.0, 1.0),
    (point.dy / size.height).clamp(0.0, 1.0),
  );

  bool _contains(NormalizedRect rect, Offset point) =>
      point.dx >= rect.left &&
      point.dx <= rect.right &&
      point.dy >= rect.top &&
      point.dy <= rect.bottom;

  bool _intersects(NormalizedRect a, NormalizedRect b) =>
      a.left < b.right &&
      a.right > b.left &&
      a.top < b.bottom &&
      a.bottom > b.top;

  NormalizedRect _union(NormalizedRect left, NormalizedRect right) =>
      NormalizedRect(
        left.left < right.left ? left.left : right.left,
        left.top < right.top ? left.top : right.top,
        left.right > right.right ? left.right : right.right,
        left.bottom > right.bottom ? left.bottom : right.bottom,
      );

  NormalizedRect _withTabBelow(NormalizedRect rect) => NormalizedRect(
    (rect.left - 0.006).clamp(0.0, 0.99),
    rect.top,
    (rect.right + 0.006).clamp(rect.left + 0.01, 1.0),
    (rect.bottom + 0.35).clamp(rect.top + 0.01, 1.0),
  );
}

class _RowHighlightState {
  _RowHighlightState({required this.boxes});

  final Set<int> selectedText = {};
  final List<NormalizedRect> boxes;
  List<RecognizedTextRegion> regions = const [];
  int? selectedBox;
  Offset? dragStart;
  NormalizedRect? dragRect;

  List<int> get paintOrder {
    final order = [
      for (var index = 0; index < boxes.length; index += 1)
        if (index != selectedBox) index,
    ];
    final selected = selectedBox;
    if (selected != null) order.add(selected);
    return order;
  }

  void clear() {
    selectedText.clear();
    boxes.clear();
    selectedBox = null;
    dragStart = null;
    dragRect = null;
  }
}

class _TextRegionPainter extends CustomPainter {
  const _TextRegionPainter({
    required this.regions,
    required this.selected,
    required this.dragRect,
    required this.boxes,
    required this.showBoxHandles,
  });

  final List<RecognizedTextRegion> regions;
  final Set<int> selected;
  final NormalizedRect? dragRect;
  final List<NormalizedRect> boxes;
  final bool showBoxHandles;

  @override
  void paint(Canvas canvas, Size size) {
    if (!showBoxHandles) {
      for (final box in boxes) {
        _drawFill(canvas, size, box, Colors.yellow.withValues(alpha: 0.38));
      }
    }
    for (var index = 0; index < regions.length; index += 1) {
      final region = regions[index].rect;
      final rect = _pixelRect(region, size);
      final isSelected = selected.contains(index);
      canvas.drawRect(
        rect,
        Paint()
          ..color = isSelected
              ? Colors.yellow.withValues(alpha: 0.42)
              : Colors.lightBlueAccent.withValues(alpha: 0.12),
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = isSelected ? Colors.amber : Colors.lightBlueAccent
          ..strokeWidth = isSelected ? 2 : 1
          ..style = PaintingStyle.stroke,
      );
    }
    if (dragRect case final drag?) {
      canvas.drawRect(
        _pixelRect(drag, size),
        Paint()
          ..color = Colors.amber
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
  }

  void _drawFill(Canvas canvas, Size size, NormalizedRect rect, Color color) {
    canvas.drawRect(_pixelRect(rect, size), Paint()..color = color);
  }

  Rect _pixelRect(NormalizedRect rect, Size size) => Rect.fromLTRB(
    rect.left * size.width,
    rect.top * size.height,
    rect.right * size.width,
    rect.bottom * size.height,
  );

  @override
  bool shouldRepaint(covariant _TextRegionPainter oldDelegate) => true;
}
