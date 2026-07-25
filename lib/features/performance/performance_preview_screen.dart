import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../../application/app_services.dart';
import '../../application/performance_deck.dart';
import '../../domain/device_preferences.dart';
import '../../domain/library_models.dart';
import '../../domain/visual_chart_models.dart';

class PerformancePreviewScreen extends StatefulWidget {
  const PerformancePreviewScreen({
    super.key,
    required this.services,
    required this.setlist,
    required this.density,
    required this.preferences,
  });

  final AppServices services;
  final LibrarySetlist setlist;
  final VisualExportDensity density;
  final DevicePreferences preferences;

  @override
  State<PerformancePreviewScreen> createState() =>
      _PerformancePreviewScreenState();
}

class _PerformancePreviewScreenState extends State<PerformancePreviewScreen> {
  late Future<PerformanceDeck> _deck;
  final _focusNode = FocusNode(debugLabel: 'performance-preview');
  var _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _deck = widget.services.performanceDeckBuilder.buildPerformanceDeck(
      widget.setlist,
      density: widget.density,
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _move(int delta, int pageCount) {
    final next = (_pageIndex + delta).clamp(0, pageCount - 1);
    if (next != _pageIndex) setState(() => _pageIndex = next);
  }

  KeyEventResult _handleKey(KeyEvent event, int pageCount) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.pageDown ||
        event.logicalKey == LogicalKeyboardKey.space) {
      _move(1, pageCount);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.pageUp) {
      _move(-1, pageCount);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PerformanceDeck>(
      future: _deck,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Performance preview')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Preview could not be prepared: ${snapshot.error}'),
              ),
            ),
          );
        }
        final deck = snapshot.data;
        if (deck == null) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final background =
            widget.preferences.gigTheme == GigThemePreference.lightOnBlack
            ? Colors.black
            : const Color(0xFFE8E8E8);
        final page = deck.pages[_pageIndex];
        return Scaffold(
          backgroundColor: background,
          body: KeyboardListener(
            autofocus: true,
            focusNode: _focusNode,
            onKeyEvent: (event) => _handleKey(event, deck.pages.length),
            child: SafeArea(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 72),
                      child: Center(
                        child: PerformanceDeckPageView(deck: deck, page: page),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 10,
                    child: _PreviewControls(
                      pageIndex: _pageIndex,
                      pageCount: deck.pages.length,
                      onPrevious: _pageIndex == 0
                          ? null
                          : () => _move(-1, deck.pages.length),
                      onNext: _pageIndex + 1 == deck.pages.length
                          ? null
                          : () => _move(1, deck.pages.length),
                      onExit: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

enum AnnotationTool { none, draw, highlight, erase }

typedef PerformanceStrokeCallback =
    void Function(
      PerformanceDeckElement element,
      List<NormalizedPoint> rowLocalPoints,
      AnnotationTool tool,
    );
typedef PerformanceEraseCallback =
    void Function(
      PerformanceDeckElement element,
      List<NormalizedPoint> rowLocalPoints,
    );

class PerformanceDeckPageView extends StatelessWidget {
  const PerformanceDeckPageView({
    super.key,
    required this.deck,
    required this.page,
    this.annotationTool = AnnotationTool.none,
    this.onStrokeCompleted,
    this.onEraseAt,
  });

  final PerformanceDeck deck;
  final PerformanceDeckPage page;
  final AnnotationTool annotationTool;
  final PerformanceStrokeCallback? onStrokeCompleted;
  final PerformanceEraseCallback? onEraseAt;

  @override
  Widget build(BuildContext context) {
    final contentWidth = deck.pageWidth - deck.margin * 2;
    final contentHeight = deck.pageHeight - deck.margin * 2;
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: deck.pageWidth,
        height: deck.pageHeight,
        child: ColoredBox(
          color: Colors.white,
          child: Padding(
            padding: EdgeInsets.all(deck.margin),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: contentWidth,
                height: contentHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (
                      var index = 0;
                      index < page.elements.length;
                      index += 1
                    ) ...[
                      if (index > 0) SizedBox(height: deck.gap),
                      _PerformanceElementView(
                        element: page.elements[index],
                        annotationTool: annotationTool,
                        onStrokeCompleted: onStrokeCompleted,
                        onEraseAt: onEraseAt,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PerformanceElementView extends StatefulWidget {
  const _PerformanceElementView({
    required this.element,
    required this.annotationTool,
    this.onStrokeCompleted,
    this.onEraseAt,
  });

  final PerformanceDeckElement element;
  final AnnotationTool annotationTool;
  final PerformanceStrokeCallback? onStrokeCompleted;
  final PerformanceEraseCallback? onEraseAt;

  @override
  State<_PerformanceElementView> createState() =>
      _PerformanceElementViewState();
}

class _PerformanceElementViewState extends State<_PerformanceElementView> {
  final _currentPoints = <NormalizedPoint>[];
  final _pendingStrokes = <VisualAnnotationStroke>[];
  int? _activePointer;
  PointerDeviceKind? _activeKind;

  @override
  void didUpdateWidget(covariant _PerformanceElementView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.element.annotations.length >
        oldWidget.element.annotations.length) {
      _pendingStrokes.clear();
    }
  }

  NormalizedPoint _point(PointerEvent event, Size size) {
    final range = event.pressureMax - event.pressureMin;
    final pressure = range <= 0
        ? 1.0
        : ((event.pressure - event.pressureMin) / range).clamp(0.2, 1.0);
    return NormalizedPoint(
      event.localPosition.dx / size.width,
      event.localPosition.dy / size.height,
      pressure: pressure,
    ).clamp();
  }

  bool _isStylus(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus;

  AnnotationTool _toolFor(PointerEvent event) =>
      event.kind == PointerDeviceKind.invertedStylus
      ? AnnotationTool.erase
      : widget.annotationTool;

  void _pointerDown(PointerDownEvent event) {
    final tool = _toolFor(event);
    if (tool == AnnotationTool.none) return;
    if (_activePointer != null) {
      final stylusSupersedesTouch =
          _isStylus(event.kind) &&
          _activeKind != null &&
          !_isStylus(_activeKind!);
      if (!stylusSupersedesTouch) return;
      _currentPoints.clear();
    }
    _activePointer = event.pointer;
    _activeKind = event.kind;
    final box = context.findRenderObject()! as RenderBox;
    final point = _point(event, box.size);
    if (tool == AnnotationTool.erase) {
      _currentPoints.add(point);
      return;
    }
    setState(() => _currentPoints.add(point));
  }

  void _pointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    final box = context.findRenderObject()! as RenderBox;
    final point = _point(event, box.size);
    if (_toolFor(event) == AnnotationTool.erase) {
      _currentPoints.add(point);
      return;
    }
    if (_toolFor(event) == AnnotationTool.draw ||
        _toolFor(event) == AnnotationTool.highlight) {
      if (_currentPoints.isNotEmpty) {
        final previous = _currentPoints.last;
        final dx = previous.x - point.x;
        final dy = previous.y - point.y;
        if (dx * dx + dy * dy < 0.000004) return;
      }
      setState(() => _currentPoints.add(point));
    }
  }

  void _pointerUp(PointerEvent event) {
    if (event.pointer != _activePointer) return;
    final tool = _toolFor(event);
    if ((tool == AnnotationTool.draw || tool == AnnotationTool.highlight) &&
        _currentPoints.length >= 2) {
      final pending = VisualAnnotationStroke(
        id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
        points: List.unmodifiable(_currentPoints),
        colorArgb: tool == AnnotationTool.highlight ? 0x66FFEB3B : 0xFFFFD740,
        width: tool == AnnotationTool.highlight ? 0.035 : 0.004,
      );
      setState(() => _pendingStrokes.add(pending));
      widget.onStrokeCompleted?.call(
        widget.element,
        List.unmodifiable(_currentPoints),
        tool,
      );
    } else if (tool == AnnotationTool.erase && _currentPoints.isNotEmpty) {
      widget.onEraseAt?.call(widget.element, List.unmodifiable(_currentPoints));
    }
    _clearPointer();
  }

  void _clearPointer() {
    _activePointer = null;
    _activeKind = null;
    if (mounted) setState(_currentPoints.clear);
  }

  @override
  Widget build(BuildContext context) {
    final element = widget.element;
    final visual = switch (element.kind) {
      PerformanceElementKind.header => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Text(
                element.title ?? 'Untitled chart',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          if ((element.artist ?? '').isNotEmpty)
            SizedBox(
              height: 9,
              child: FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: Text(
                  element.artist!,
                  style: const TextStyle(color: Colors.black, fontSize: 8),
                ),
              ),
            ),
        ],
      ),
      PerformanceElementKind.boundary => const DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.black54, width: 0.5)),
        ),
      ),
      PerformanceElementKind.placeholder => ColoredBox(
        color: const Color(0xFFFFCCD1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Not playing - ${element.title}',
              style: const TextStyle(
                color: Colors.black,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
      PerformanceElementKind.strip => Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            element.imageBytes!,
            fit: BoxFit.fill,
            gaplessPlayback: true,
          ),
          if (element.annotationsVisible)
            CustomPaint(
              painter: _AnnotationPainter(
                strokes: [...element.annotations, ..._pendingStrokes],
                currentPoints: _currentPoints,
                currentTool: widget.annotationTool,
              ),
            ),
          if (widget.annotationTool != AnnotationTool.none)
            Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _pointerDown,
              onPointerMove: _pointerMove,
              onPointerUp: _pointerUp,
              onPointerCancel: _pointerUp,
            ),
        ],
      ),
    };
    return SizedBox(
      width: element.width,
      height: element.height,
      child: visual,
    );
  }
}

class _AnnotationPainter extends CustomPainter {
  const _AnnotationPainter({
    required this.strokes,
    required this.currentPoints,
    required this.currentTool,
  });

  final List<VisualAnnotationStroke> strokes;
  final List<NormalizedPoint> currentPoints;
  final AnnotationTool currentTool;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      _paintStroke(
        canvas,
        size,
        stroke.points,
        Color(stroke.colorArgb),
        stroke.width,
      );
    }
    _paintStroke(
      canvas,
      size,
      currentPoints,
      currentTool == AnnotationTool.highlight
          ? const Color(0x66FFEB3B)
          : const Color(0xFFFFD740),
      currentTool == AnnotationTool.highlight ? 0.035 : 0.004,
    );
  }

  void _paintStroke(
    Canvas canvas,
    Size size,
    List<NormalizedPoint> points,
    Color color,
    double normalizedWidth,
  ) {
    if (points.length < 2) return;
    for (var index = 1; index < points.length; index += 1) {
      final from = points[index - 1];
      final to = points[index];
      final pressure = (from.pressure + to.pressure) / 2;
      canvas.drawLine(
        Offset(from.x * size.width, from.y * size.height),
        Offset(to.x * size.width, to.y * size.height),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = (normalizedWidth * size.width * pressure).clamp(1, 24)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_AnnotationPainter oldDelegate) => true;
}

class _PreviewControls extends StatelessWidget {
  const _PreviewControls({
    required this.pageIndex,
    required this.pageCount,
    required this.onPrevious,
    required this.onNext,
    required this.onExit,
  });

  final int pageIndex;
  final int pageCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.78),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Exit performance preview',
              onPressed: onExit,
              color: Colors.white,
              icon: const Icon(Icons.close),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Previous page',
              onPressed: onPrevious,
              color: Colors.white,
              icon: const Icon(Icons.arrow_back),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Page ${pageIndex + 1} of $pageCount',
                style: const TextStyle(color: Colors.white),
              ),
            ),
            IconButton(
              tooltip: 'Next page',
              onPressed: onNext,
              color: Colors.white,
              icon: const Icon(Icons.arrow_forward),
            ),
            const Spacer(),
            const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }
}
