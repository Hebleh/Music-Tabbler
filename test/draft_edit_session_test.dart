import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/application/draft_edit_session.dart';
import 'package:music_tabbler/domain/visual_chart_models.dart';

void main() {
  test('undo history keeps bounded immutable draft snapshots', () {
    final history = DraftUndoHistory(maximumEntries: 2);
    history.record(_draft('one'));
    history.record(_draft('two'));
    history.record(_draft('three'));

    expect(history.length, 2);
    expect(history.undo()!.title, 'three');
    expect(history.undo()!.title, 'two');
    expect(history.canUndo, isFalse);
  });

  test('autosaver collapses rapid edits into the latest local write', () async {
    final saved = <String>[];
    final autosaver = DebouncedDraftAutosaver(
      delay: const Duration(milliseconds: 10),
      save: (draft) async => saved.add(draft.title),
    );

    autosaver.schedule(_draft('one'));
    autosaver.schedule(_draft('two'));
    autosaver.schedule(_draft('three'));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await autosaver.dispose();

    expect(saved, ['three']);
  });
}

VisualChartDraft _draft(String title) {
  final now = DateTime.utc(2026, 7, 21);
  return VisualChartDraft(
    id: 'chart',
    title: title,
    artist: '',
    createdAt: now,
    updatedAt: now,
  );
}
