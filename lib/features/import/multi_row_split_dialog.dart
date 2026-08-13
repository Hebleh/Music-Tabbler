import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../../domain/visual_chart_models.dart';
import '../../application/horizontal_row_detector.dart';
import '../../application/visual_deskew.dart';
import 'resizable_rect_overlay.dart';

class MultiRowSplitResult {
  const MultiRowSplitResult({
    required this.rows,
    required this.masterLeft,
    required this.masterRight,
  });

  final List<NormalizedRect> rows;
  final double masterLeft;
  final double masterRight;
}

class MultiRowSplitDialog extends StatefulWidget {
  const MultiRowSplitDialog({
    super.key,
    required this.imagePath,
    required this.imageAspectRatio,
    required this.sourceRect,
    this.initialRows = const [],
    this.initialMasterLeft,
    this.initialMasterRight,
    this.deskewDegrees = 0,
  });

  final String imagePath;
  final double imageAspectRatio;
  final NormalizedRect sourceRect;
  final List<NormalizedRect> initialRows;
  final double? initialMasterLeft;
  final double? initialMasterRight;
  final double deskewDegrees;

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
  late final Future<Uint8List> _imageBytes;
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
    _masterLeft = (widget.initialMasterLeft ?? widget.sourceRect.left)
        .clamp(widget.sourceRect.left, widget.sourceRect.right - 0.01)
        .toDouble();
    _masterRight = (widget.initialMasterRight ?? widget.sourceRect.right)
        .clamp(_masterLeft + 0.01, widget.sourceRect.right)
        .toDouble();
    _reapplyPersistentMasterCrop();
    _imageBytes = compute(_prepareSplitImage, {
      'path': widget.imagePath,
      'deskewDegrees': widget.deskewDegrees,
    });
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
                      final contextPanelWidth =
                          viewportConstraints.maxWidth >= 850 ? 270.0 : 0.0;
                      final controlSize = Size(
                        viewportConstraints.maxWidth - contextPanelWidth,
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
                            child: Row(
                              children: [
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
                                                  .register(event, (
                                                    resolvedEvent,
                                                  ) {
                                                    final scroll =
                                                        resolvedEvent
                                                            as PointerScrollEvent;
                                                    final position =
                                                        _scrollController
                                                            .position;
                                                    _scrollController.jumpTo(
                                                      (position.pixels +
                                                              scroll
                                                                  .scrollDelta
                                                                  .dy)
                                                          .clamp(
                                                            position
                                                                .minScrollExtent,
                                                            position
                                                                .maxScrollExtent,
                                                          ),
                                                    );
                                                  });
                                            }
                                          },
                                          child: SingleChildScrollView(
                                            controller: _scrollController,
                                            primary: false,
                                            child: AspectRatio(
                                              aspectRatio:
                                                  widget.imageAspectRatio,
                                              child: LayoutBuilder(
                                                builder: (context, constraints) {
                                                  final size = Size(
                                                    constraints.maxWidth,
                                                    constraints.maxHeight,
                                                  );
                                                  return Stack(
                                                    fit: StackFit.expand,
                                                    children: [
                                                      FutureBuilder<Uint8List>(
                                                        future: _imageBytes,
                                                        builder: (context, snapshot) {
                                                          if (snapshot
                                                              .hasError) {
                                                            return const Center(
                                                              child: Text(
                                                                'Split preview unavailable',
                                                              ),
                                                            );
                                                          }
                                                          if (!snapshot
                                                              .hasData) {
                                                            return const Center(
                                                              child:
                                                                  CircularProgressIndicator(),
                                                            );
                                                          }
                                                          return Image.memory(
                                                            snapshot.data!,
                                                            fit: BoxFit.fill,
                                                          );
                                                        },
                                                      ),
                                                      for (final index
                                                          in _paintOrder)
                                                        ResizableRectOverlay(
                                                          rect: _rows[index],
                                                          canvasSize: size,
                                                          color:
                                                              Colors
                                                                  .primaries[index %
                                                                  Colors
                                                                      .primaries
                                                                      .length],
                                                          label:
                                                              'Row ${index + 1}',
                                                          selected:
                                                              index ==
                                                              _selected,
                                                          onSelected: () =>
                                                              setState(
                                                                () =>
                                                                    _selected =
                                                                        index,
                                                              ),
                                                          onChanged: (value) =>
                                                              setState(() {
                                                                _selected =
                                                                    index;
                                                                _rows[index] =
                                                                    value;
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
                                        controlSize.width,
                                      ),
                                      _buildMasterGuide(
                                        _masterRight,
                                        controlSize.width,
                                      ),
                                    ],
                                  ),
                                ),
                                if (contextPanelWidth > 0)
                                  SizedBox(
                                    width: contextPanelWidth,
                                    child: _buildDerivedRowsContext(),
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
                Navigator.pop(
                  context,
                  MultiRowSplitResult(
                    rows: sorted,
                    masterLeft: _masterLeft,
                    masterRight: _masterRight,
                  ),
                );
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

  Widget _buildDerivedRowsContext() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: FutureBuilder<Uint8List>(
        future: _imageBytes,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final sourcePreviewHeight = (constraints.maxHeight * 0.32)
                  .clamp(72.0, 180.0)
                  .toDouble();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 10, 12, 6),
                    child: Text(
                      'Source page -> derived rows',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  SizedBox(
                    height: sourcePreviewHeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: widget.imageAspectRatio,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(snapshot.data!, fit: BoxFit.fill),
                              IgnorePointer(
                                child: CustomPaint(
                                  painter: _SelectedCropPainter(
                                    _rows[_selected],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      key: const ValueKey('derived-row-context-list'),
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      itemCount: _rows.length,
                      itemBuilder: (context, index) {
                        final row = _rows[index];
                        return Card(
                          color: index == _selected
                              ? Theme.of(context).colorScheme.secondaryContainer
                              : null,
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => setState(() => _selected = index),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Row ${index + 1}'),
                                  const SizedBox(height: 4),
                                  AspectRatio(
                                    aspectRatio:
                                        widget.imageAspectRatio *
                                        row.width /
                                        row.height,
                                    child: _PageCropPreview(
                                      bytes: snapshot.data!,
                                      crop: row,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

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
      final bytes = await _imageBytes;
      final detected = await compute(_detectRowsInBackground, {
        'bytes': bytes,
        'sourceRect': widget.sourceRect.toJson(),
      });
      if (!mounted) return;
      final rows = [
        for (final value in detected['rows']! as List)
          NormalizedRect.fromJson((value as Map).cast<String, Object?>()),
      ];
      setState(() {
        _rows = rows.isEmpty ? _evenRows(5) : rows;
        _masterLeft = (detected['masterLeft']! as num).toDouble();
        _masterRight = (detected['masterRight']! as num).toDouble();
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

class _PageCropPreview extends StatelessWidget {
  const _PageCropPreview({required this.bytes, required this.crop});

  final Uint8List bytes;
  final NormalizedRect crop;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: -crop.left / crop.width * constraints.maxWidth,
              top: -crop.top / crop.height * constraints.maxHeight,
              width: constraints.maxWidth / crop.width,
              height: constraints.maxHeight / crop.height,
              child: Image.memory(bytes, fit: BoxFit.fill),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedCropPainter extends CustomPainter {
  const _SelectedCropPainter(this.crop);

  final NormalizedRect crop;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(
      crop.left * size.width,
      crop.top * size.height,
      crop.right * size.width,
      crop.bottom * size.height,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _SelectedCropPainter oldDelegate) =>
      oldDelegate.crop != crop;
}

Uint8List _prepareSplitImage(Map<String, Object> request) {
  var image = img.decodeImage(
    File(request['path']! as String).readAsBytesSync(),
  );
  if (image == null) {
    throw const FormatException('Stored chart image is invalid.');
  }
  image = img.bakeOrientation(image);
  image = applyDeskewRotation(
    image,
    (request['deskewDegrees'] as num?)?.toDouble() ?? 0,
  );
  return Uint8List.fromList(img.encodePng(image, level: 3));
}

Map<String, Object> _detectRowsInBackground(Map<String, Object> request) {
  final sourceRect = NormalizedRect.fromJson(
    (request['sourceRect']! as Map).cast<String, Object?>(),
  );
  final proposal = const HorizontalRowDetector().detectPageAware(
    request['bytes']! as Uint8List,
    sourceRect: sourceRect,
  );
  return {
    'rows': proposal.rows.map((row) => row.toJson()).toList(growable: false),
    'masterLeft': proposal.masterLeft,
    'masterRight': proposal.masterRight,
  };
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
