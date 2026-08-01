import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';
import 'package:music_tabbler/features/import/resizable_rect_overlay.dart';

void main() {
  testWidgets('fast resize tracks total pointer travel without losing deltas', (
    tester,
  ) async {
    const canvasKey = ValueKey('canvas');
    var rect = const NormalizedRect(0.2, 0.2, 0.6, 0.6);

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            key: canvasKey,
            width: 400,
            height: 300,
            child: StatefulBuilder(
              builder: (context, setState) => ResizableRectOverlay(
                rect: rect,
                canvasSize: const Size(400, 300),
                onChanged: (value) => setState(() => rect = value),
              ),
            ),
          ),
        ),
      ),
    );

    final origin = tester.getTopLeft(find.byKey(canvasKey));
    final gesture = await tester.startGesture(origin + const Offset(240, 120));
    await gesture.moveBy(const Offset(40, 0));
    await gesture.moveBy(const Offset(40, 0));
    await gesture.moveBy(const Offset(40, 0));
    await gesture.up();
    await tester.pump();

    expect(rect.right, closeTo(0.9, 0.005));
  });

  for (final testCase
      in <
        ({String handle, Offset delta, bool Function(NormalizedRect) changed})
      >[
        (
          handle: 'top',
          delta: const Offset(0, 30),
          changed: (rect) => rect.top > 0,
        ),
        (
          handle: 'bottom',
          delta: const Offset(0, -30),
          changed: (rect) => rect.bottom < 1,
        ),
        (
          handle: 'left',
          delta: const Offset(30, 0),
          changed: (rect) => rect.left > 0,
        ),
        (
          handle: 'right',
          delta: const Offset(-30, 0),
          changed: (rect) => rect.right < 1,
        ),
        (
          handle: 'topLeft',
          delta: const Offset(30, 30),
          changed: (rect) => rect.left > 0 && rect.top > 0,
        ),
        (
          handle: 'topRight',
          delta: const Offset(-30, 30),
          changed: (rect) => rect.right < 1 && rect.top > 0,
        ),
        (
          handle: 'bottomLeft',
          delta: const Offset(30, -30),
          changed: (rect) => rect.left > 0 && rect.bottom < 1,
        ),
        (
          handle: 'bottomRight',
          delta: const Offset(-30, -30),
          changed: (rect) => rect.right < 1 && rect.bottom < 1,
        ),
      ]) {
    testWidgets('${testCase.handle} handle remains hittable at canvas edge', (
      tester,
    ) async {
      var rect = const NormalizedRect.full();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 400,
              height: 300,
              child: StatefulBuilder(
                builder: (context, setState) => ResizableRectOverlay(
                  rect: rect,
                  canvasSize: const Size(400, 300),
                  onChanged: (value) => setState(() => rect = value),
                ),
              ),
            ),
          ),
        ),
      );

      final finder = find.byKey(ValueKey('resize-handle-${testCase.handle}'));
      expect(finder, findsOneWidget);
      await tester.drag(finder, testCase.delta, touchSlopY: 0, touchSlopX: 0);
      await tester.pump();
      expect(testCase.changed(rect), isTrue);
    });
  }
}
