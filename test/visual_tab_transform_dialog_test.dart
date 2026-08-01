import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/domain/visual_tab_transform_models.dart';
import 'package:music_tabbler/features/import/visual_tab_transform_dialog.dart';

void main() {
  testWidgets('four-to-five preset is explicit in editable target controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    VisualTabTransformConfiguration? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showVisualTabTransformDialog(
                context: context,
                sourceStringCount: 4,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom / current values'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Drop-D 4-string'));
    await tester.pumpAndSettle();

    for (var index = 0; index < 5; index += 1) {
      expect(find.byKey(ValueKey('target-string-enabled-$index')), findsOne);
    }
    expect(find.textContaining('Added target string - unused'), findsOne);

    await tester.ensureVisible(find.text('Apply transform'));
    await tester.tap(find.text('Apply transform'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.targetLabels, ['B', 'E', 'A', 'D', 'G']);
    expect(result!.unusedTargetString, 1);
    expect(result!.routes.map((route) => route.targetString), [0, 2, 3, 4]);
  });
}
