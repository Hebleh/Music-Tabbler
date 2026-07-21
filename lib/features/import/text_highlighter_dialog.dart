import 'dart:io';

import 'package:flutter/material.dart';

import '../../application/service_contracts.dart';
import '../../domain/visual_chart_models.dart';

class TextHighlightSelection {
  const TextHighlightSelection({
    required this.rects,
    required this.includeTabBelow,
  });

  final List<NormalizedRect> rects;
  final bool includeTabBelow;
}

class TextHighlighterDialog extends StatefulWidget {
  const TextHighlighterDialog({
    super.key,
    required this.imagePath,
    required this.imageAspectRatio,
    required this.strip,
    required this.textRecognition,
  });

  final String imagePath;
  final double imageAspectRatio;
  final VisualStrip strip;
  final TextRecognitionService textRecognition;

  @override
  State<TextHighlighterDialog> createState() => _TextHighlighterDialogState();
}

class _TextHighlighterDialogState extends State<TextHighlighterDialog> {
  late final Future<MetadataSuggestion> _recognition;
  final Set<int> _selected = {};
  final List<NormalizedRect> _manualRects = [];
  Offset? _dragStart;
  NormalizedRect? _dragRect;
  bool _includeTabBelow = false;
  bool _freeform = false;

  @override
  void initState() {
    super.initState();
    _recognition = widget.textRecognition.recognize(widget.strip);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Backing-vocal highlighter'),
      content: SizedBox(
        width: 1050,
        child: FutureBuilder<MetadataSuggestion>(
          future: _recognition,
          builder: (context, snapshot) {
            if (!snapshot.hasData && !snapshot.hasError) {
              return const SizedBox(
                height: 280,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Finding text locally…'),
                    ],
                  ),
                ),
              );
            }
            final regions =
                snapshot.data?.regions ?? const <RecognizedTextRegion>[];
            return Column(
              mainAxisSize: MainAxisSize.min,
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
                      label: Text('Freeform'),
                    ),
                  ],
                  selected: {_freeform},
                  onSelectionChanged: (value) =>
                      setState(() => _freeform = value.single),
                ),
                const SizedBox(height: 8),
                Text(
                  regions.isEmpty
                      ? 'OCR did not find selectable words here. Draw freeform highlight boxes instead.'
                      : _freeform
                      ? 'Drag a box over any lyric OCR missed.'
                      : 'Drag across words like a PDF highlighter, or click individual detected words.',
                ),
                const SizedBox(height: 8),
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
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: _freeform
                                ? null
                                : (details) => _toggleAt(
                                    _normalized(details.localPosition, size),
                                    regions,
                                  ),
                            onPanStart: (details) {
                              _dragStart = details.localPosition;
                              setState(() => _dragRect = null);
                            },
                            onPanUpdate: (details) => _updateDrag(
                              details.localPosition,
                              size,
                              regions,
                            ),
                            onPanEnd: (_) => _finishDrag(),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(
                                  File(widget.imagePath),
                                  fit: BoxFit.fill,
                                ),
                                CustomPaint(
                                  painter: _TextRegionPainter(
                                    regions: regions,
                                    selected: _selected,
                                    dragRect: _dragRect,
                                    manualRects: _manualRects,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
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
                    'Extends each selected word highlight downward in the same horizontal position.',
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${_selected.length} text region(s), ${_manualRects.length} freeform box(es)',
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => setState(() {
            _selected.clear();
            _manualRects.clear();
          }),
          child: const Text('Clear'),
        ),
        FutureBuilder<MetadataSuggestion>(
          future: _recognition,
          builder: (context, snapshot) => FilledButton.icon(
            onPressed: (_selected.isEmpty && _manualRects.isEmpty)
                ? null
                : () {
                    final rects = [
                      if (snapshot.hasData)
                        for (final index in _selected)
                          _includeTabBelow
                              ? _withTabBelow(
                                  snapshot.data!.regions[index].rect,
                                )
                              : snapshot.data!.regions[index].rect,
                      ..._manualRects,
                    ];
                    Navigator.pop(
                      context,
                      TextHighlightSelection(
                        rects: rects,
                        includeTabBelow: _includeTabBelow,
                      ),
                    );
                  },
            icon: const Icon(Icons.highlight_alt),
            label: const Text('Apply highlights'),
          ),
        ),
      ],
    );
  }

  void _toggleAt(Offset point, List<RecognizedTextRegion> regions) {
    for (var index = regions.length - 1; index >= 0; index -= 1) {
      if (_contains(regions[index].rect, point)) {
        setState(() {
          if (!_selected.add(index)) _selected.remove(index);
        });
        return;
      }
    }
  }

  void _updateDrag(
    Offset current,
    Size size,
    List<RecognizedTextRegion> regions,
  ) {
    final start = _dragStart;
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
      _dragRect = rect;
      if (!_freeform) {
        for (var index = 0; index < regions.length; index += 1) {
          if (_intersects(rect, regions[index].rect)) _selected.add(index);
        }
      }
    });
  }

  void _finishDrag() {
    final rect = _dragRect;
    setState(() {
      if (_freeform &&
          rect != null &&
          rect.width > 0.004 &&
          rect.height > 0.004) {
        _manualRects.add(rect);
      }
      _dragRect = null;
      _dragStart = null;
    });
  }

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

  NormalizedRect _withTabBelow(NormalizedRect rect) => NormalizedRect(
    (rect.left - 0.006).clamp(0.0, 0.99),
    rect.top,
    (rect.right + 0.006).clamp(rect.left + 0.01, 1.0),
    (rect.bottom + 0.16).clamp(rect.top + 0.01, 1.0),
  );
}

class _TextRegionPainter extends CustomPainter {
  const _TextRegionPainter({
    required this.regions,
    required this.selected,
    required this.dragRect,
    required this.manualRects,
  });

  final List<RecognizedTextRegion> regions;
  final Set<int> selected;
  final NormalizedRect? dragRect;
  final List<NormalizedRect> manualRects;

  @override
  void paint(Canvas canvas, Size size) {
    for (final region in manualRects) {
      canvas.drawRect(
        Rect.fromLTRB(
          region.left * size.width,
          region.top * size.height,
          region.right * size.width,
          region.bottom * size.height,
        ),
        Paint()..color = Colors.yellow.withValues(alpha: 0.42),
      );
    }
    for (var index = 0; index < regions.length; index += 1) {
      final region = regions[index].rect;
      final rect = Rect.fromLTRB(
        region.left * size.width,
        region.top * size.height,
        region.right * size.width,
        region.bottom * size.height,
      );
      final isSelected = selected.contains(index);
      canvas.drawRect(
        rect,
        Paint()
          ..color = isSelected
              ? Colors.yellow.withValues(alpha: 0.42)
              : Colors.lightBlueAccent.withValues(alpha: 0.12)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = isSelected ? Colors.amber : Colors.lightBlueAccent
          ..strokeWidth = isSelected ? 2 : 1
          ..style = PaintingStyle.stroke,
      );
    }
    final drag = dragRect;
    if (drag != null) {
      canvas.drawRect(
        Rect.fromLTRB(
          drag.left * size.width,
          drag.top * size.height,
          drag.right * size.width,
          drag.bottom * size.height,
        ),
        Paint()
          ..color = Colors.amber
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TextRegionPainter oldDelegate) => true;
}
