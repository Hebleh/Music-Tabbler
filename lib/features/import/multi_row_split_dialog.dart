import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../domain/visual_chart_models.dart';
import '../../application/horizontal_row_detector.dart';
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
  final ScrollController _scrollController = ScrollController();
  bool _detecting = false;

  @override
  void initState() {
    super.initState();
    _rows = _evenRows(5);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
                  value: _rows.length.clamp(1, 32),
                  items: [
                    for (var count = 1; count <= 32; count += 1)
                      DropdownMenuItem(value: count, child: Text('$count')),
                  ],
                  onChanged: (count) {
                    if (count != null) setState(() => _rows = _evenRows(count));
                  },
                ),
                FilledButton.tonalIcon(
                  onPressed: _detecting ? null : _detectRows,
                  icon: _detecting
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_fix_high_outlined),
                  label: Text(_detecting ? 'Detecting...' : 'Detect rows'),
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
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: Listener(
                  onPointerSignal: (event) {
                    if (event is PointerScrollEvent &&
                        _scrollController.hasClients) {
                      GestureBinding.instance.pointerSignalResolver.register(
                        event,
                        (resolvedEvent) {
                          final scroll = resolvedEvent as PointerScrollEvent;
                          final position = _scrollController.position;
                          _scrollController.jumpTo(
                            (position.pixels + scroll.scrollDelta.dy).clamp(
                              position.minScrollExtent,
                              position.maxScrollExtent,
                            ),
                          );
                        },
                      );
                    }
                  },
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    primary: false,
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
                              Image.file(
                                File(widget.imagePath),
                                fit: BoxFit.fill,
                              ),
                              for (final index in _paintOrder)
                                ResizableRectOverlay(
                                  rect: _rows[index],
                                  canvasSize: size,
                                  color:
                                      Colors.primaries[index %
                                          Colors.primaries.length],
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

  List<int> get _paintOrder => [
    for (var index = 0; index < _rows.length; index += 1)
      if (index != _selected) index,
    if (_rows.isNotEmpty) _selected,
  ];

  Future<void> _detectRows() async {
    setState(() => _detecting = true);
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final detected = await compute(_detectRowsInBackground, {
        'bytes': bytes,
        'sourceRect': widget.sourceRect.toJson(),
      });
      if (!mounted) return;
      final rows = [
        for (final value in detected)
          NormalizedRect.fromJson(value.cast<String, Object?>()),
      ];
      setState(() {
        _rows = rows.isEmpty ? _evenRows(5) : rows;
        _selected = 0;
      });
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
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

List<Map<String, Object>> _detectRowsInBackground(Map<String, Object> request) {
  final sourceRect = NormalizedRect.fromJson(
    (request['sourceRect']! as Map).cast<String, Object?>(),
  );
  return const HorizontalRowDetector()
      .detect(request['bytes']! as Uint8List, sourceRect: sourceRect)
      .map((row) => row.toJson())
      .toList(growable: false);
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
