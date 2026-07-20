import 'package:flutter/material.dart';

import '../../domain/visual_chart_models.dart';

class ResizableRectOverlay extends StatelessWidget {
  const ResizableRectOverlay({
    super.key,
    required this.rect,
    required this.canvasSize,
    required this.onChanged,
    this.color = Colors.amber,
    this.label,
    this.selected = true,
    this.onSelected,
  });

  final NormalizedRect rect;
  final Size canvasSize;
  final ValueChanged<NormalizedRect> onChanged;
  final Color color;
  final String? label;
  final bool selected;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final pixelRect = Rect.fromLTRB(
      rect.left * canvasSize.width,
      rect.top * canvasSize.height,
      rect.right * canvasSize.width,
      rect.bottom * canvasSize.height,
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fromRect(
          rect: pixelRect,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSelected,
            onPanStart: (_) => onSelected?.call(),
            onPanUpdate: (details) => _move(details.delta),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color.withValues(alpha: selected ? 0.16 : 0.08),
                border: Border.all(color: color, width: selected ? 3 : 2),
              ),
              child: label == null
                  ? null
                  : Align(
                      alignment: Alignment.topLeft,
                      child: ColoredBox(
                        color: color,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Text(
                            label!,
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
        if (selected)
          for (final handle in _Handle.values) _buildHandle(handle, pixelRect),
      ],
    );
  }

  Widget _buildHandle(_Handle handle, Rect pixelRect) {
    final point = switch (handle) {
      _Handle.topLeft => pixelRect.topLeft,
      _Handle.top => pixelRect.topCenter,
      _Handle.topRight => pixelRect.topRight,
      _Handle.right => pixelRect.centerRight,
      _Handle.bottomRight => pixelRect.bottomRight,
      _Handle.bottom => pixelRect.bottomCenter,
      _Handle.bottomLeft => pixelRect.bottomLeft,
      _Handle.left => pixelRect.centerLeft,
    };
    const hitSize = 28.0;
    return Positioned(
      left: point.dx - hitSize / 2,
      top: point.dy - hitSize / 2,
      width: hitSize,
      height: hitSize,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => onSelected?.call(),
        onPanUpdate: (details) => _resize(handle, details.delta),
        child: Center(
          child: Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: color,
              border: Border.all(color: Colors.black87),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }

  void _move(Offset delta) {
    final dx = delta.dx / canvasSize.width;
    final dy = delta.dy / canvasSize.height;
    final width = rect.width;
    final height = rect.height;
    final left = (rect.left + dx).clamp(0.0, 1.0 - width);
    final top = (rect.top + dy).clamp(0.0, 1.0 - height);
    onChanged(NormalizedRect(left, top, left + width, top + height));
  }

  void _resize(_Handle handle, Offset delta) {
    final dx = delta.dx / canvasSize.width;
    final dy = delta.dy / canvasSize.height;
    var left = rect.left;
    var top = rect.top;
    var right = rect.right;
    var bottom = rect.bottom;
    if (handle.usesLeft) left = (left + dx).clamp(0.0, right - 0.01);
    if (handle.usesRight) right = (right + dx).clamp(left + 0.01, 1.0);
    if (handle.usesTop) top = (top + dy).clamp(0.0, bottom - 0.01);
    if (handle.usesBottom) bottom = (bottom + dy).clamp(top + 0.01, 1.0);
    onChanged(NormalizedRect(left, top, right, bottom));
  }
}

enum _Handle {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left;

  bool get usesLeft => this == topLeft || this == bottomLeft || this == left;
  bool get usesRight =>
      this == topRight || this == bottomRight || this == right;
  bool get usesTop => this == topLeft || this == top || this == topRight;
  bool get usesBottom =>
      this == bottomLeft || this == bottom || this == bottomRight;
}
