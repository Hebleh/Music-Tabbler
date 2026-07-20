import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/visual_chart_models.dart';
import 'resizable_rect_overlay.dart';

class RectEditorDialog extends StatefulWidget {
  const RectEditorDialog({
    super.key,
    required this.imagePath,
    required this.imageAspectRatio,
    required this.title,
    required this.initialRect,
  });

  final String imagePath;
  final double imageAspectRatio;
  final String title;
  final NormalizedRect initialRect;

  @override
  State<RectEditorDialog> createState() => _RectEditorDialogState();
}

class _RectEditorDialogState extends State<RectEditorDialog> {
  late NormalizedRect _rect;

  @override
  void initState() {
    super.initState();
    _rect = widget.initialRect;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: widget.imageAspectRatio,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final height = constraints.maxHeight;
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(File(widget.imagePath), fit: BoxFit.fill),
                        ResizableRectOverlay(
                          rect: _rect,
                          canvasSize: Size(width, height),
                          onChanged: _setRect,
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Drag the box to move it. Use any edge or corner handle to resize. Fine-tune below.',
              ),
              _edgeSlider('Left', _rect.left, 0, _rect.right - 0.01, (value) {
                _setRect(
                  NormalizedRect(value, _rect.top, _rect.right, _rect.bottom),
                );
              }),
              _edgeSlider('Top', _rect.top, 0, _rect.bottom - 0.01, (value) {
                _setRect(
                  NormalizedRect(_rect.left, value, _rect.right, _rect.bottom),
                );
              }),
              _edgeSlider('Right', _rect.right, _rect.left + 0.01, 1, (value) {
                _setRect(
                  NormalizedRect(_rect.left, _rect.top, value, _rect.bottom),
                );
              }),
              _edgeSlider('Bottom', _rect.bottom, _rect.top + 0.01, 1, (value) {
                _setRect(
                  NormalizedRect(_rect.left, _rect.top, _rect.right, value),
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _rect),
          child: const Text('Apply'),
        ),
      ],
    );
  }

  Widget _edgeSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(width: 58, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 42, child: Text('${(value * 100).round()}%')),
      ],
    );
  }

  void _setRect(NormalizedRect candidate) {
    final width = candidate.width;
    final height = candidate.height;
    var left = candidate.left;
    var top = candidate.top;
    var right = candidate.right;
    var bottom = candidate.bottom;
    if (left < 0) {
      left = 0;
      right = width;
    }
    if (top < 0) {
      top = 0;
      bottom = height;
    }
    if (right > 1) {
      right = 1;
      left = 1 - width;
    }
    if (bottom > 1) {
      bottom = 1;
      top = 1 - height;
    }
    setState(() {
      _rect = NormalizedRect(left, top, right, bottom).clamp();
    });
  }
}
