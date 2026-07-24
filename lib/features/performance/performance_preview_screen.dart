import 'package:flutter/material.dart';
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

class PerformanceDeckPageView extends StatelessWidget {
  const PerformanceDeckPageView({
    super.key,
    required this.deck,
    required this.page,
  });

  final PerformanceDeck deck;
  final PerformanceDeckPage page;

  @override
  Widget build(BuildContext context) {
    final contentWidth = deck.pageWidth - deck.margin * 2;
    final contentHeight = deck.pageHeight - deck.margin * 2;
    return AspectRatio(
      aspectRatio: deck.pageWidth / deck.pageHeight,
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
                    _PerformanceElementView(element: page.elements[index]),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PerformanceElementView extends StatelessWidget {
  const _PerformanceElementView({required this.element});

  final PerformanceDeckElement element;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: element.width,
      height: element.height,
      child: switch (element.kind) {
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
        PerformanceElementKind.strip => Image.memory(
          element.imageBytes!,
          fit: BoxFit.fill,
          gaplessPlayback: true,
        ),
      },
    );
  }
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
