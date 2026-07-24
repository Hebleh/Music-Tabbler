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
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: PerformanceDeckPageView(
            deck: deck,
            page: page,
            annotationTool: AnnotationTool.draw,
            onStrokeCompleted: (_, points) => captured = points,
          ),
        ),
      ),
    );

    final origin = tester.getTopLeft(find.byType(Image));
    await tester.sendEventToBinding(
      PointerDownEvent(
        pointer: 1,
        position: origin + const Offset(20, 20),
        kind: PointerDeviceKind.stylus,
        pressure: 0.25,
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    await tester.sendEventToBinding(
      PointerDownEvent(
        pointer: 2,
        position: origin + const Offset(100, 80),
        kind: PointerDeviceKind.touch,
      ),
    );
    await tester.sendEventToBinding(
      PointerMoveEvent(
        pointer: 1,
        position: origin + const Offset(180, 80),
        delta: const Offset(160, 60),
        kind: PointerDeviceKind.stylus,
        pressure: 0.75,
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    await tester.sendEventToBinding(
      PointerUpEvent(
        pointer: 1,
        position: origin + const Offset(180, 80),
        kind: PointerDeviceKind.stylus,
      ),
    );
    await tester.pump();

    expect(captured, hasLength(2));
    expect(captured!.first.pressure, 0.25);
    expect(captured!.last.pressure, 0.75);
    expect(captured!.last.x, closeTo(0.9, 0.01));
  });

  testWidgets('inverted stylus uses the eraser without changing tools', (
    tester,
  ) async {
    NormalizedPoint? erased;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: PerformanceDeckPageView(
            deck: deck,
            page: page,
            annotationTool: AnnotationTool.draw,
            onEraseAt: (_, point) => erased = point,
          ),
        ),
      ),
    );

    final origin = tester.getTopLeft(find.byType(Image));
    await tester.sendEventToBinding(
      PointerDownEvent(
        pointer: 3,
        position: origin + const Offset(100, 50),
        kind: PointerDeviceKind.invertedStylus,
      ),
    );
    await tester.sendEventToBinding(
      PointerUpEvent(
        pointer: 3,
        position: origin + const Offset(100, 50),
        kind: PointerDeviceKind.invertedStylus,
      ),
    );
    await tester.pump();

    expect(erased, isNotNull);
    expect(erased!.x, closeTo(0.5, 0.01));
    expect(erased!.y, closeTo(0.5, 0.01));
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
