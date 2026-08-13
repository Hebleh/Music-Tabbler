import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../application/visual_deskew.dart';
import '../../domain/visual_chart_models.dart';
import 'resizable_rect_overlay.dart';

class RectEditorDialog extends StatefulWidget {
  const RectEditorDialog({
    super.key,
    required this.imagePath,
    required this.imageAspectRatio,
    required this.title,
    required this.initialRect,
    this.viewportRect = const NormalizedRect.full(),
    this.deskewDegrees = 0,
  });

  final String imagePath;
  final double imageAspectRatio;
  final String title;
  final NormalizedRect initialRect;
  final NormalizedRect viewportRect;
  final double deskewDegrees;

  @override
  State<RectEditorDialog> createState() => _RectEditorDialogState();
}

class _RectEditorDialogState extends State<RectEditorDialog> {
  late NormalizedRect _rect;
  late final Future<Uint8List> _imageBytes;

  @override
  void initState() {
    super.initState();
    _rect = widget.initialRect;
    _imageBytes = compute(_cropDialogImage, {
      'path': widget.imagePath,
      'crop': widget.viewportRect.toJson(),
      'deskewDegrees': widget.deskewDegrees,
    });
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
                        FutureBuilder<Uint8List>(
                          future: _imageBytes,
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return const Center(
                                child: Text('Crop preview unavailable'),
                              );
                            }
                            if (!snapshot.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            return Image.memory(
                              snapshot.data!,
                              fit: BoxFit.fill,
                            );
                          },
                        ),
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
              _edgeSlider('Top', _rect.top, 0, _rect.bottom - 0.01, (value) {
                _setRect(
                  NormalizedRect(_rect.left, value, _rect.right, _rect.bottom),
                );
              }),
              _edgeSlider('Bottom', _rect.bottom, _rect.top + 0.01, 1, (value) {
                _setRect(
                  NormalizedRect(_rect.left, _rect.top, _rect.right, value),
                );
              }),
              _edgeSlider('Left', _rect.left, 0, _rect.right - 0.01, (value) {
                _setRect(
                  NormalizedRect(value, _rect.top, _rect.right, _rect.bottom),
                );
              }),
              _edgeSlider('Right', _rect.right, _rect.left + 0.01, 1, (value) {
                _setRect(
                  NormalizedRect(_rect.left, _rect.top, value, _rect.bottom),
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

Uint8List _cropDialogImage(Map<String, Object> request) {
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
  final crop = NormalizedRect.fromJson(
    (request['crop']! as Map).cast<String, Object?>(),
  );
  final left = (crop.left * image.width).floor().clamp(0, image.width - 1);
  final top = (crop.top * image.height).floor().clamp(0, image.height - 1);
  final right = (crop.right * image.width).ceil().clamp(left + 1, image.width);
  final bottom = (crop.bottom * image.height).ceil().clamp(
    top + 1,
    image.height,
  );
  final cropped = img.copyCrop(
    image,
    x: left,
    y: top,
    width: right - left,
    height: bottom - top,
  );
  return Uint8List.fromList(img.encodePng(cropped, level: 3));
}
