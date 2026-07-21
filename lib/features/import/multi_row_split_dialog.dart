import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/visual_chart_models.dart';
import '../../application/horizontal_row_detector.dart';
import 'resizable_rect_overlay.dart';

class MultiRowSplitDialog extends StatefulWidget {
  const MultiRowSplitDialog({
    super.key,
    required this.imagePath,
    required this.imageAspectRatio,
    required this.sourceRect,
    this.initialRows = const [],
  });

  final String imagePath;
  final double imageAspectRatio;
  final NormalizedRect sourceRect;
  final List<NormalizedRect> initialRows;

  @override
  State<MultiRowSplitDialog> createState() => _MultiRowSplitDialogState();
}

class _MultiRowSplitDialogState extends State<MultiRowSplitDialog> {
  late List<NormalizedRect> _rows;
  int _selected = 0;
  final ScrollController _scrollController = ScrollController();
  bool _detecting = false;
  late double _masterLeft;
  late double _masterRight;
  final Set<int> _leftCaught = {};
  final Set<int> _rightCaught = {};
  _MasterSide? _activeMaster;
  double? _masterGestureStart;
  Offset? _masterPointerStart;

  @override
  void initState() {
    super.initState();
    _rows = widget.initialRows.isEmpty
        ? _evenRows(5)
        : List.of(widget.initialRows);
    _selected = _selected.clamp(0, _rows.length - 1);
    _masterLeft = widget.sourceRect.left;
    _masterRight = widget.sourceRect.right;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.backspace): _deleteSelected,
        const SingleActivator(LogicalKeyboardKey.delete): _deleteSelected,
      },
      child: Focus(
        autofocus: true,
        child: AlertDialog(
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
                        if (count != null) {
                          setState(() {
                            _rows = _evenRows(count);
                            _reapplyPersistentMasterCrop();
                          });
                        }
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
                      onPressed: () => setState(() {
                        _rows = _evenRows(_rows.length);
                        _reapplyPersistentMasterCrop();
                      }),
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
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.vertical_align_center, size: 18),
                    const SizedBox(width: 6),
                    const Flexible(
                      child: Text(
                        'Master side crop: drag either blue vertical bar inward. It catches row edges as it reaches them and keeps caught edges together.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 6),
                    TextButton(
                      onPressed: _resetMasterSides,
                      child: const Text('Reset master sides'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: LayoutBuilder(
                    builder: (context, viewportConstraints) {
                      final controlSize = Size(
                        viewportConstraints.maxWidth,
                        34,
                      );
                      return Column(
                        children: [
                          SizedBox(
                            height: controlSize.height,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                _buildMasterHandle(
                                  _MasterSide.left,
                                  controlSize,
                                  _masterLeft,
                                ),
                                _buildMasterHandle(
                                  _MasterSide.right,
                                  controlSize,
                                  _masterRight,
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Stack(
                              children: [
                                Scrollbar(
                                  controller: _scrollController,
                                  thumbVisibility: true,
                                  child: Listener(
                                    onPointerSignal: (event) {
                                      if (event is PointerScrollEvent &&
                                          _scrollController.hasClients) {
                                        GestureBinding
                                            .instance
                                            .pointerSignalResolver
                                            .register(event, (resolvedEvent) {
                                              final scroll =
                                                  resolvedEvent
                                                      as PointerScrollEvent;
                                              final position =
                                                  _scrollController.position;
                                              _scrollController.jumpTo(
                                                (position.pixels +
                                                        scroll.scrollDelta.dy)
                                                    .clamp(
                                                      position.minScrollExtent,
                                                      position.maxScrollExtent,
                                                    ),
                                              );
                                            });
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
                                                            Colors
                                                                .primaries
                                                                .length],
                                                    label: 'Row ${index + 1}',
                                                    selected:
                                                        index == _selected,
                                                    onSelected: () => setState(
                                                      () => _selected = index,
                                                    ),
                                                    onChanged: (value) =>
                                                        setState(() {
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
                                _buildMasterGuide(
                                  _masterLeft,
                                  viewportConstraints.maxWidth,
                                ),
                                _buildMasterGuide(
                                  _masterRight,
                                  viewportConstraints.maxWidth,
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
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
                final sorted = [..._rows]
                  ..sort((a, b) => a.top.compareTo(b.top));
                Navigator.pop(context, sorted);
              },
              icon: const Icon(Icons.call_split),
              label: Text('Create ${_rows.length} rows'),
            ),
          ],
        ),
      ),
    );
  }

  List<int> get _paintOrder => [
    for (var index = 0; index < _rows.length; index += 1)
      if (index != _selected) index,
    if (_rows.isNotEmpty) _selected,
  ];

  Widget _buildMasterHandle(_MasterSide side, Size canvasSize, double value) {
    final x = value * canvasSize.width;
    return Positioned(
      left: x - 16,
      top: 0,
      width: 32,
      height: 32,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) {
            _activeMaster = side;
            _masterGestureStart = value;
            _masterPointerStart = details.globalPosition;
          },
          onPanUpdate: (details) =>
              _dragMasterSide(side, details.globalPosition, canvasSize),
          onPanEnd: (_) => _endMasterDrag(),
          onPanCancel: _endMasterDrag,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.lightBlueAccent,
              borderRadius: BorderRadius.all(Radius.circular(6)),
            ),
            child: Icon(Icons.drag_handle, color: Colors.black87),
          ),
        ),
      ),
    );
  }

  Widget _buildMasterGuide(double value, double width) => Positioned(
    left: value * width - 1.5,
    top: 0,
    bottom: 0,
    width: 3,
    child: const IgnorePointer(
      child: ColoredBox(color: Colors.lightBlueAccent),
    ),
  );

  void _dragMasterSide(
    _MasterSide side,
    Offset globalPosition,
    Size canvasSize,
  ) {
    if (_activeMaster != side ||
        _masterGestureStart == null ||
        _masterPointerStart == null) {
      return;
    }
    final delta =
        (globalPosition.dx - _masterPointerStart!.dx) / canvasSize.width;
    final proposed = _masterGestureStart! + delta;
    setState(() {
      if (side == _MasterSide.left) {
        final previousValue = _masterLeft;
        _masterLeft = proposed.clamp(
          widget.sourceRect.left,
          _masterRight - 0.01,
        );
        _rows = applyStickyMasterCrop(
          rows: _rows,
          caughtRows: _leftCaught,
          value: _masterLeft,
          previousValue: previousValue,
          sourceRect: widget.sourceRect,
          leftSide: true,
        );
      } else {
        final previousValue = _masterRight;
        _masterRight = proposed.clamp(
          _masterLeft + 0.01,
          widget.sourceRect.right,
        );
        _rows = applyStickyMasterCrop(
          rows: _rows,
          caughtRows: _rightCaught,
          value: _masterRight,
          previousValue: previousValue,
          sourceRect: widget.sourceRect,
          leftSide: false,
        );
      }
    });
  }

  void _endMasterDrag() {
    _activeMaster = null;
    _masterGestureStart = null;
    _masterPointerStart = null;
  }

  void _resetMasterSides() {
    setState(() {
      _masterLeft = widget.sourceRect.left;
      _masterRight = widget.sourceRect.right;
      _leftCaught.clear();
      _rightCaught.clear();
      _endMasterDrag();
    });
  }

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
        _reapplyPersistentMasterCrop();
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
      _reapplyPersistentMasterCrop();
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
      _reapplyPersistentMasterCrop();
    });
  }

  void _deleteSelected() {
    if (_rows.length <= 1) return;
    setState(() {
      _rows.removeAt(_selected);
      _selected = _selected.clamp(0, _rows.length - 1);
      _reapplyPersistentMasterCrop();
    });
  }

  void _reapplyPersistentMasterCrop() {
    _leftCaught.clear();
    _rightCaught.clear();
    for (var index = 0; index < _rows.length; index += 1) {
      if (_masterLeft > widget.sourceRect.left &&
          _rows[index].left <= _masterLeft) {
        _leftCaught.add(index);
      }
      if (_masterRight < widget.sourceRect.right &&
          _rows[index].right >= _masterRight) {
        _rightCaught.add(index);
      }
    }
    _rows = applyStickyMasterCrop(
      rows: _rows,
      caughtRows: _leftCaught,
      value: _masterLeft,
      previousValue: _masterLeft,
      sourceRect: widget.sourceRect,
      leftSide: true,
    );
    _rows = applyStickyMasterCrop(
      rows: _rows,
      caughtRows: _rightCaught,
      value: _masterRight,
      previousValue: _masterRight,
      sourceRect: widget.sourceRect,
      leftSide: false,
    );
    _endMasterDrag();
  }
}

enum _MasterSide { left, right }

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

List<NormalizedRect> applyStickyMasterCrop({
  required List<NormalizedRect> rows,
  required Set<int> caughtRows,
  required double value,
  required double previousValue,
  required NormalizedRect sourceRect,
  required bool leftSide,
}) {
  final movingInward = leftSide ? value > previousValue : value < previousValue;
  if (movingInward) {
    for (var index = 0; index < rows.length; index += 1) {
      if (caughtRows.contains(index)) continue;
      final edge = leftSide ? rows[index].left : rows[index].right;
      final crossed = leftSide
          ? previousValue <= edge && value >= edge
          : previousValue >= edge && value <= edge;
      if (crossed) caughtRows.add(index);
    }
  }
  return [
    for (var index = 0; index < rows.length; index += 1)
      if (!caughtRows.contains(index))
        rows[index]
      else if (leftSide)
        NormalizedRect(
          value.clamp(sourceRect.left, rows[index].right - 0.01),
          rows[index].top,
          rows[index].right,
          rows[index].bottom,
        )
      else
        NormalizedRect(
          rows[index].left,
          rows[index].top,
          value.clamp(rows[index].left + 0.01, sourceRect.right),
          rows[index].bottom,
        ),
  ];
}
