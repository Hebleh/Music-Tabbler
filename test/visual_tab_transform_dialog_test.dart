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

  testWidgets(
    'shows high strings first and applies Drop-C# to seven-string Drop-A',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1100);
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
      expect(find.text('1. G'), findsWidgets);
      expect(find.text('4. E'), findsWidgets);
      for (final id in ['source-tuning', 'target-tuning']) {
        expect(find.byKey(ValueKey('$id-add-high-string')), findsOneWidget);
        expect(find.byKey(ValueKey('$id-add-low-string')), findsOneWidget);
      }

      await tester.tap(find.text('Custom / current values'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Drop-C# 6-string'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Apply transform'));
      await tester.tap(find.text('Apply transform'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.sourceLabels, ['C#', 'G#', 'C#', 'F#', 'A#', 'D#']);
      expect(result!.sourceOpenMidis, [37, 44, 49, 54, 58, 63]);
      expect(result!.targetLabels, ['A', 'E', 'A', 'D', 'G', 'B', 'E']);
      expect(result!.targetOpenMidis, [33, 40, 45, 50, 55, 59, 64]);
      expect(result!.routes.map((route) => route.targetString), [
        0,
        1,
        2,
        3,
        4,
        5,
      ]);
      expect(result!.unusedTargetStrings, [6]);
    },
  );

  testWidgets('standard guitar preset sets six source and target strings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1100);
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
    await tester.tap(find.textContaining('Standard guitar EADGBE'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Apply transform'));
    await tester.tap(find.text('Apply transform'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.sourceLabels, ['E', 'A', 'D', 'G', 'B', 'E']);
    expect(result!.targetLabels, result!.sourceLabels);
    expect(result!.sourceOpenMidis, [40, 45, 50, 55, 59, 64]);
    expect(result!.unusedTargetStrings, isEmpty);
  });

  testWidgets('adding above G defaults to B and then E', (tester) async {
    tester.view.physicalSize = const Size(1200, 1100);
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
    for (final id in ['source-tuning', 'target-tuning']) {
      await tester.tap(find.byKey(ValueKey('$id-add-high-string')));
      await tester.pumpAndSettle();
      expect(find.text('Add string above B'), findsWidgets);
      await tester.tap(find.byKey(ValueKey('$id-add-high-string')));
      await tester.pumpAndSettle();
    }
    expect(find.text('Add string above E'), findsNWidgets(2));

    await tester.ensureVisible(find.text('Apply transform'));
    await tester.tap(find.text('Apply transform'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.sourceLabels, ['E', 'A', 'D', 'G', 'B', 'E']);
    expect(result!.targetLabels, result!.sourceLabels);
    expect(result!.sourceOpenMidis, [28, 33, 38, 43, 47, 52]);
  });
}
