import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/application/semantic_edit_session.dart';
import 'package:music_tabbler/domain/music_models.dart';

void main() {
  test('semantic undo history keeps immutable chart snapshots', () {
    final history = SemanticUndoHistory(maximumEntries: 2);
    final base = SongChart.foundationExample();
    history
      ..record(base)
      ..record(base.copyWith(title: 'Two'))
      ..record(base.copyWith(title: 'Three'));

    expect(history.undo()!.title, 'Three');
    expect(history.undo()!.title, 'Two');
    expect(history.canUndo, isFalse);
  });

  test(
    'semantic autosaver collapses rapid edits into the latest chart',
    () async {
      final saved = <String>[];
      final autosaver = DebouncedSemanticAutosaver(
        delay: const Duration(milliseconds: 10),
        save: (chart) async => saved.add(chart.title),
      );
      final base = SongChart.foundationExample();

      autosaver.schedule(base.copyWith(title: 'One'));
      autosaver.schedule(base.copyWith(title: 'Two'));
      autosaver.schedule(base.copyWith(title: 'Three'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await autosaver.dispose();

      expect(saved, ['Three']);
    },
  );

  test('note rest and measure commands preserve valid related indices', () {
    final base = SongChart.foundationExample().copyWith(
      sections: const [
        SongSection(id: 'verse', name: 'Verse', measureIndex: 1),
      ],
    );
    final note = TabNote.exact(
      id: 'new-note',
      position: BeatFraction(1, 2),
      stringIndex: 4,
      fret: 2,
      value: NoteValue.eighth,
    );
    final rest = RestEvent(
      id: 'new-rest',
      position: BeatFraction(3),
      value: NoteValue.quarter,
    );

    final edited = base
        .addNote(0, note)
        .addRest(0, rest)
        .addMeasure(ChartMeasure(number: 3, notes: const []));
    final removed = edited.removeMeasure(0);

    expect(edited.noteById('new-note'), isNotNull);
    expect(edited.measures.first.rests.single.id, 'new-rest');
    expect(edited.measures, hasLength(3));
    expect(removed.measures, hasLength(2));
    expect(removed.sections.single.measureIndex, 0);
    expect(
      removed.lyrics.where((lyric) => lyric.measureIndex == 0),
      isNotEmpty,
    );
  });
}
