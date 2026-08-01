import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/application/performance_deck.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';
import 'package:music_tabbler/features/performance/performance_preview_screen.dart';

void main() {
  late PerformanceDeck deck;
  late PerformanceDeckPage page;

  setUp(() {
    page = PerformanceDeckPage(
      id: 'page',
      index: 0,
      elements: [
        PerformanceDeckElement(
          kind: PerformanceElementKind.strip,
          entryIndex: 0,
          entryId: 'entry',
          chartVariantId: 'variant',
          sourceStripId: 'strip',
          sourceRowRect: const NormalizedRect.full(),
          width: 200,
          height: 100,
          imageBytes: Uint8List.fromList(_transparentPng),
        ),
      ],
    );
    deck = PerformanceDeck(
      setlistId: 'set',
      setlistName: 'Set',
      density: VisualExportDensity.stageReadable,
      pageWidth: 200,
      pageHeight: 100,
      margin: 0,
      gap: 0,
      pages: [page],
    );
  });

  testWidgets('stylus pressure is captured and touch palm input is ignored', (
    tester,
  ) async {
    List<NormalizedPoint>? captured;
    AnnotationTool? capturedTool;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: PerformanceDeckPageView(
            deck: deck,
            page: page,
            annotationTool: AnnotationTool.draw,
            onStrokeCompleted: (_, points, tool) {
              captured = points;
              capturedTool = tool;
            },
          ),
        ),
      ),
    );

    final image = find.byType(Image);
    final imageBox = tester.renderObject<RenderBox>(image);
    Offset point(double x, double y) => imageBox.localToGlobal(Offset(x, y));
    await tester.sendEventToBinding(
      PointerDownEvent(
        pointer: 1,
        position: point(20, 20),
        kind: PointerDeviceKind.stylus,
        pressure: 0.25,
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    await tester.sendEventToBinding(
      PointerDownEvent(
        pointer: 2,
        position: point(100, 80),
        kind: PointerDeviceKind.touch,
      ),
    );
    await tester.sendEventToBinding(
      PointerMoveEvent(
        pointer: 1,
        position: point(180, 80),
        delta: point(180, 80) - point(20, 20),
        kind: PointerDeviceKind.stylus,
        pressure: 0.75,
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    await tester.sendEventToBinding(
      PointerUpEvent(
        pointer: 1,
        position: point(180, 80),
        kind: PointerDeviceKind.stylus,
      ),
    );
    await tester.pump();

    expect(captured, hasLength(2));
    expect(captured!.first.pressure, 0.25);
    expect(captured!.last.pressure, 0.75);
    expect(captured!.last.x, closeTo(0.9, 0.01));
    expect(capturedTool, AnnotationTool.draw);
  });

  testWidgets('performance page expands to the available stage viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: PerformanceDeckPageView(deck: deck, page: page),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(PerformanceDeckPageView)),
      const Size(1160, 860),
    );
    final image = find.byType(Image);
    final imageBox = tester.renderObject<RenderBox>(image);
    final paintedTopLeft = imageBox.localToGlobal(Offset.zero);
    final paintedBottomRight = imageBox.localToGlobal(const Offset(200, 100));
    expect(
      paintedBottomRight - paintedTopLeft,
      const Offset(1160, 580),
      reason: 'The 2:1 stage page should scale up to the viewport width.',
    );
  });

  testWidgets('inverted stylus uses the eraser without changing tools', (
    tester,
  ) async {
    List<NormalizedPoint>? erased;
    var eraseCallbacks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: PerformanceDeckPageView(
            deck: deck,
            page: page,
            annotationTool: AnnotationTool.draw,
            onEraseAt: (_, points) {
              eraseCallbacks += 1;
              erased = points;
            },
          ),
        ),
      ),
    );

    final image = find.byType(Image);
    final imageBox = tester.renderObject<RenderBox>(image);
    Offset point(double x, double y) => imageBox.localToGlobal(Offset(x, y));
    await tester.sendEventToBinding(
      PointerDownEvent(
        pointer: 3,
        position: point(100, 50),
        kind: PointerDeviceKind.invertedStylus,
      ),
    );
    await tester.sendEventToBinding(
      PointerMoveEvent(
        pointer: 3,
        position: point(120, 55),
        delta: point(120, 55) - point(100, 50),
        kind: PointerDeviceKind.invertedStylus,
      ),
    );
    await tester.sendEventToBinding(
      PointerUpEvent(
        pointer: 3,
        position: point(120, 55),
        kind: PointerDeviceKind.invertedStylus,
      ),
    );
    await tester.pump();

    expect(erased, isNotNull);
    expect(eraseCallbacks, 1);
    expect(erased, hasLength(2));
    expect(erased!.first.x, closeTo(0.5, 0.01));
    expect(erased!.first.y, closeTo(0.5, 0.01));
  });
}

const _transparentPng = <int>[
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  6,
  0,
  0,
  0,
  31,
  21,
  196,
  137,
  0,
  0,
  0,
  13,
  73,
  68,
  65,
  84,
  8,
  215,
  99,
  248,
  207,
  192,
  240,
  31,
  0,
  5,
  0,
  1,
  255,
  137,
  153,
  61,
  29,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
];
