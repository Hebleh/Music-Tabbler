import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/visual_chart_models.dart';
import 'resizable_rect_overlay.dart';

class MultiRowSplitDialog extends StatefulWidget {
  const MultiRowSplitDialog({
    super.key,
    required this.imagePath,
    required this.imageAspectRatio,
    required this.sourceRect,
  });

  final String imagePath;
  final double imageAspectRatio;
  final NormalizedRect sourceRect;

  @override
  State<MultiRowSplitDialog> createState() => _MultiRowSplitDialogState();
}

class _MultiRowSplitDialogState extends State<MultiRowSplitDialog> {
  late List<NormalizedRect> _rows;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _rows = _evenRows(5);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Split page into tab rows'),
      content: SizedBox(
        width: 1050,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Rows'),
                DropdownButton<int>(
                  value: _rows.length.clamp(1, 16),
                  items: [
                    for (var count = 1; count <= 16; count += 1)
                      DropdownMenuItem(value: count, child: Text('$count')),
                  ],
                  onChanged: (count) {
                    if (count != null) setState(() => _rows = _evenRows(count));
                  },
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      setState(() => _rows = _evenRows(_rows.length)),
                  icon: const Icon(Icons.vertical_distribute),
                  label: const Text('Evenly divide'),
                ),
                OutlinedButton.icon(
                  onPressed: _addRow,
                  icon: const Icon(Icons.add),
                  label: const Text('Add row box'),
                ),
                OutlinedButton.icon(
                  onPressed: _rows.isEmpty ? null : _duplicateSelected,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Duplicate selected'),
                ),
                OutlinedButton.icon(
                  onPressed: _rows.length <= 1 ? null : _deleteSelected,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete selected'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'All row boxes stay visible together. Click a box, drag it, or resize it from any edge or corner.',
            ),
            const SizedBox(height: 10),
            Flexible(
              child: SingleChildScrollView(
                child: AspectRatio(
                  aspectRatio: widget.imageAspectRatio,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(File(widget.imagePath), fit: BoxFit.fill),
                          for (var index = 0; index < _rows.length; index += 1)
                            ResizableRectOverlay(
                              rect: _rows[index],
                              canvasSize: size,
                              color: Colors
                                  .primaries[index % Colors.primaries.length],
                              label: 'Row ${index + 1}',
                              selected: index == _selected,
                              onSelected: () =>
                                  setState(() => _selected = index),
                              onChanged: (value) => setState(() {
                                _selected = index;
                                _rows[index] = value;
                              }),
                            ),
                        ],
                      );
                    },
                  ),
                ),
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
        FilledButton.icon(
          onPressed: () {
            final sorted = [..._rows]..sort((a, b) => a.top.compareTo(b.top));
            Navigator.pop(context, sorted);
          },
          icon: const Icon(Icons.call_split),
          label: Text('Create ${_rows.length} rows'),
        ),
      ],
    );
  }

  List<NormalizedRect> _evenRows(int count) {
    final result = evenRowRects(widget.sourceRect, count);
    _selected = _selected.clamp(0, count - 1);
    return result;
  }

  void _addRow() {
    final selected = _rows[_selected];
    final height = (selected.height * 0.8).clamp(0.03, 0.25);
    final top = (selected.bottom + 0.01).clamp(
      widget.sourceRect.top,
      widget.sourceRect.bottom - height,
    );
    setState(() {
      _rows.add(
        NormalizedRect(
          widget.sourceRect.left,
          top,
          widget.sourceRect.right,
          top + height,
        ),
      );
      _selected = _rows.length - 1;
    });
  }

  void _duplicateSelected() {
    final source = _rows[_selected];
    final dy = (source.height * 0.15).clamp(0.01, 0.05);
    var top = (source.top + dy).clamp(0.0, 1.0 - source.height);
    setState(() {
      _rows.add(
        NormalizedRect(source.left, top, source.right, top + source.height),
      );
      _selected = _rows.length - 1;
    });
  }

  void _deleteSelected() {
    setState(() {
      _rows.removeAt(_selected);
      _selected = _selected.clamp(0, _rows.length - 1);
    });
  }
}

List<NormalizedRect> evenRowRects(NormalizedRect source, int count) {
  if (count < 1) throw ArgumentError.value(count, 'count', 'Must be positive.');
  final result = <NormalizedRect>[];
  final height = source.height / count;
  for (var index = 0; index < count; index += 1) {
    final top = source.top + height * index;
    result.add(
      NormalizedRect(
        source.left,
        top,
        source.right,
        index == count - 1 ? source.bottom : top + height,
      ),
    );
  }
  return result;
}
