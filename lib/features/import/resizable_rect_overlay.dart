import 'package:flutter/material.dart';

import '../../domain/visual_chart_models.dart';

class ResizableRectOverlay extends StatefulWidget {
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
  State<ResizableRectOverlay> createState() => _ResizableRectOverlayState();
}

class _ResizableRectOverlayState extends State<ResizableRectOverlay> {
  NormalizedRect? _gestureStartRect;
  Offset? _gestureStartGlobal;

  @override
  Widget build(BuildContext context) {
    final pixelRect = Rect.fromLTRB(
      widget.rect.left * widget.canvasSize.width,
      widget.rect.top * widget.canvasSize.height,
      widget.rect.right * widget.canvasSize.width,
      widget.rect.bottom * widget.canvasSize.height,
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fromRect(
          rect: pixelRect,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onSelected,
            onPanStart: (details) => _startGesture(details.globalPosition),
            onPanUpdate: (details) => _move(details.globalPosition),
            onPanEnd: (_) => _endGesture(),
            onPanCancel: _endGesture,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: widget.color.withValues(
                  alpha: widget.selected ? 0.16 : 0.08,
                ),
                border: Border.all(
                  color: widget.color,
                  width: widget.selected ? 3 : 2,
                ),
              ),
              child: widget.label == null
                  ? null
                  : Align(
                      alignment: Alignment.topLeft,
                      child: ColoredBox(
                        color: widget.color,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Text(
                            widget.label!,
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
        if (widget.selected)
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
        onPanStart: (details) => _startGesture(details.globalPosition),
        onPanUpdate: (details) => _resize(handle, details.globalPosition),
        onPanEnd: (_) => _endGesture(),
        onPanCancel: _endGesture,
        child: Center(
          child: Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: widget.color,
              border: Border.all(color: Colors.black87),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }

  void _startGesture(Offset globalPosition) {
    widget.onSelected?.call();
    _gestureStartRect = widget.rect;
    _gestureStartGlobal = globalPosition;
  }

  void _endGesture() {
    _gestureStartRect = null;
    _gestureStartGlobal = null;
  }

  Offset? _totalDelta(Offset globalPosition) {
    final start = _gestureStartGlobal;
    if (start == null) return null;
    return Offset(
      (globalPosition.dx - start.dx) / widget.canvasSize.width,
      (globalPosition.dy - start.dy) / widget.canvasSize.height,
    );
  }

  void _move(Offset globalPosition) {
    final rect = _gestureStartRect;
    final delta = _totalDelta(globalPosition);
    if (rect == null || delta == null) return;
    final width = rect.width;
    final height = rect.height;
    final left = (rect.left + delta.dx).clamp(0.0, 1.0 - width);
    final top = (rect.top + delta.dy).clamp(0.0, 1.0 - height);
    widget.onChanged(NormalizedRect(left, top, left + width, top + height));
  }

  void _resize(_Handle handle, Offset globalPosition) {
    final rect = _gestureStartRect;
    final delta = _totalDelta(globalPosition);
    if (rect == null || delta == null) return;
    var left = rect.left;
    var top = rect.top;
    var right = rect.right;
    var bottom = rect.bottom;
    final dx = delta.dx;
    final dy = delta.dy;
    if (handle.usesLeft) left = (left + dx).clamp(0.0, right - 0.01);
    if (handle.usesRight) right = (right + dx).clamp(left + 0.01, 1.0);
    if (handle.usesTop) top = (top + dy).clamp(0.0, bottom - 0.01);
    if (handle.usesBottom) bottom = (bottom + dy).clamp(top + 0.01, 1.0);
    widget.onChanged(NormalizedRect(left, top, right, bottom));
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
