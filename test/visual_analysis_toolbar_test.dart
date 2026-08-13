import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/domain/visual_tab_transform_models.dart';
import 'package:music_tabbler/features/import/visual_analysis_toolbar.dart';

void main() {
  testWidgets('Add note is a persistent toggle and exposes review history', (
    tester,
  ) async {
    var addingNote = false;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: VisualAnalysisToolbar(
              analyses: const [
                VisualTabAnalysis(
                  stripId: 'strip',
                  sourceType: VisualTabSourceType.rasterOcr,
                ),
              ],
              currentIndex: 0,
              analysis: const VisualTabAnalysis(
                stripId: 'strip',
                sourceType: VisualTabSourceType.rasterOcr,
              ),
              rerunningSource: false,
              addingNote: addingNote,
              canUndo: true,
              canRedo: true,
              stripCount: 1,
              selectedTokenCount: 1,
              onRowSelected: (_) {},
              onRerunCurrent: () {},
              onRerunAll: () {},
              onAddingNoteChanged: (value) =>
                  setState(() => addingNote = value),
              onUndo: () {},
              onRedo: () {},
              onEdit: () {},
              onMerge: () {},
              onSplit: () {},
              onDelete: () {},
            ),
          ),
        ),
      ),
    );

    final addNote = find.byKey(const ValueKey('add-manual-note'));
    expect(addNote, findsOneWidget);
    expect(find.text('Draw missing token'), findsNothing);
    expect(find.text('Remove selected'), findsOneWidget);
    expect(find.byTooltip('Undo review change'), findsOneWidget);
    expect(find.byTooltip('Redo review change'), findsOneWidget);

    await tester.tap(addNote);
    await tester.pump();
    expect(tester.widget<FilterChip>(addNote).selected, isTrue);
    await tester.tap(addNote);
    await tester.pump();
    expect(tester.widget<FilterChip>(addNote).selected, isFalse);
  });
}
