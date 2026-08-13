import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';
import 'package:music_tabbler/domain/visual_tab_transform_models.dart';
import 'package:music_tabbler/features/import/visual_analysis_canvas.dart';

void main() {
  testWidgets(
    'manual note overlays distinguish detected resting and active states',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const detected = VisualTabToken(
        id: 'detected',
        text: '5',
        rect: NormalizedRect(0.18, 0.45, 0.205, 0.55),
        kind: VisualTabTokenKind.fret,
        stringIndex: 1,
      );
      const manualOne = VisualTabToken(
        id: 'manual-one',
        text: '12',
        rect: NormalizedRect(0.42, 0.45, 0.465, 0.55),
        kind: VisualTabTokenKind.fret,
        stringIndex: 1,
        origin: VisualTabTokenOrigin.manual,
      );
      const manualTwo = VisualTabToken(
        id: 'manual-two',
        text: '(7)',
        rect: NormalizedRect(0.66, 0.44, 0.72, 0.56),
        kind: VisualTabTokenKind.fret,
        stringIndex: 1,
        origin: VisualTabTokenOrigin.manual,
      );
      VisualTabAnalysis analysis(List<VisualTabToken> tokens) =>
          VisualTabAnalysis(
            stripId: 'strip',
            sourceType: VisualTabSourceType.rasterOcr,
            systems: [
              VisualTabSystem(
                id: 'system',
                rect: const NormalizedRect(0.04, 0.2, 0.96, 0.8),
                stringLines: const [0.3, 0.4, 0.5, 0.6],
                tokens: tokens,
              ),
            ],
          );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: RepaintBoundary(
              key: const ValueKey('manual-note-golden'),
              child: Column(
                children: [
                  _LabelledCanvas(
                    label: 'Detected selected - no manual gradient',
                    analysis: analysis([detected]),
                    selected: const {'detected'},
                  ),
                  _LabelledCanvas(
                    label: 'Two resting manual notes - independent gradients',
                    analysis: analysis([detected, manualOne, manualTwo]),
                    selected: const {},
                  ),
                  _LabelledCanvas(
                    label: 'Selected manual note - stronger local gradient',
                    analysis: analysis([detected, manualOne, manualTwo]),
                    selected: const {'manual-two'},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      for (var index = 0; index < 8; index += 1) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      await expectLater(
        find.byKey(const ValueKey('manual-note-golden')),
        matchesGoldenFile('goldens/windows/manual_note_gradients.png'),
      );
    },
  );
}

class _LabelledCanvas extends StatelessWidget {
  const _LabelledCanvas({
    required this.label,
    required this.analysis,
    required this.selected,
  });

  final String label;
  final VisualTabAnalysis analysis;
  final Set<String> selected;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 5, 12, 2),
            child: Text(label),
          ),
          Expanded(
            child: ColoredBox(
              color: Colors.white,
              child: VisualAnalysisOverlay(
                analysis: analysis,
                selectedTokenIds: selected,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
