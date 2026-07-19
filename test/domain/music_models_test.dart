import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/domain/music_models.dart';

void main() {
  group('semantic bass model', () {
    test('derives pitch from the selected BEADG string and fret', () {
      const note = TabNote(
        id: 'note',
        beat: 0,
        stringIndex: 4,
        fret: 5,
        value: NoteValue.quarter,
      );

      expect(note.midiPitch(BassTuning.beadg), 28);
    });

    test('replaces a note without mutating the original chart', () {
      final original = SongChart.foundationExample();
      final selected = original.noteById('n1')!;
      final updated = original.replaceNote(selected.copyWith(fret: 7));

      expect(original.noteById('n1')!.fret, 3);
      expect(updated.noteById('n1')!.fret, 7);
      expect(updated.measures.length, original.measures.length);
    });

    test('backing-vocal status is editable independently of lyric text', () {
      final original = SongChart.foundationExample();
      final lyric = original.lyrics.first;
      final updated = original.replaceLyric(
        lyric.copyWith(isBackingVocal: true),
      );

      expect(original.lyrics.first.isBackingVocal, isFalse);
      expect(updated.lyrics.first.isBackingVocal, isTrue);
      expect(updated.lyrics.first.text, original.lyrics.first.text);
    });
  });
}
