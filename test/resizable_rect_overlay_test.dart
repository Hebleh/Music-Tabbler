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
}
