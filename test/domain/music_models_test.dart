import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/domain/music_models.dart';
import 'dart:convert';

void main() {
  group('semantic bass model', () {
    test('derives pitch from the selected BEADG string and fret', () {
      final note = TabNote(
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

    test('semantic chart JSON round-trips tuning notes and lyrics', () {
      final original = SongChart.foundationExample();
      final restored = SongChart.decode(original.encode());

      expect(restored.id, original.id);
      expect(restored.tuning.strings.map((string) => string.midiPitch), [
        43,
        38,
        33,
        28,
        23,
      ]);
      expect(restored.measures.first.notes.first.fret, 3);
      expect(restored.lyrics.last.isBackingVocal, isTrue);
    });

    test('beat fractions normalize and keep dotted tuplets exact', () {
      expect(BeatFraction(6, 8), BeatFraction(3, 4));
      final note = TabNote.exact(
        id: 'triplet',
        position: BeatFraction(1, 3),
        stringIndex: 0,
        fret: 3,
        value: NoteValue.eighth,
        dots: 1,
        tuplet: const TupletRatio(actual: 3, normal: 2),
      );

      expect(note.position, BeatFraction(1, 3));
      expect(note.duration, BeatFraction(1, 2));
    });

    test('schema v1 decimal beats migrate into schema v2 fractions', () {
      final legacy = SongChart.foundationExample().toJson()
        ..['schemaVersion'] = 1;
      final measures = legacy['measures']! as List;
      for (final rawMeasure in measures.cast<Map<String, Object>>()) {
        rawMeasure['beats'] = BeatFraction.fromJson(
          (rawMeasure.remove('length')! as Map).cast<String, Object?>(),
        ).value;
        rawMeasure.remove('rests');
        rawMeasure.remove('timeSignature');
        rawMeasure.remove('keySignature');
        rawMeasure.remove('tempoBpm');
        for (final rawNote
            in (rawMeasure['notes']! as List).cast<Map<String, Object>>()) {
          rawNote['beat'] = BeatFraction.fromJson(
            (rawNote.remove('position')! as Map).cast<String, Object?>(),
          ).value;
          rawNote
            ..remove('voice')
            ..remove('dots')
            ..remove('tieStart')
            ..remove('tieEnd')
            ..remove('tuplet');
        }
      }
      for (final rawLyric
          in (legacy['lyrics']! as List).cast<Map<String, Object>>()) {
        rawLyric['beat'] = BeatFraction.fromJson(
          (rawLyric.remove('position')! as Map).cast<String, Object?>(),
        ).value;
      }
      legacy
        ..remove('sections')
        ..remove('repeats');

      final migrated = SongChart.decode(jsonEncode(legacy));

      expect(migrated.measures.first.notes[1].position, BeatFraction.one);
      expect(migrated.measures.first.length, BeatFraction(4));
      expect(migrated.sections, isEmpty);
      expect(migrated.encode(), contains('"schemaVersion":2'));
    });

    test('measure and repeat diagnostics reject invalid structures', () {
      final chart = SongChart(
        title: 'Invalid',
        artist: '',
        tuning: BassTuning.beadg,
        measures: [
          ChartMeasure.exact(
            number: 1,
            length: BeatFraction(3),
            timeSignature: const TimeSignature(4, 4),
            notes: [
              TabNote.exact(
                id: 'too-long',
                position: BeatFraction(3),
                stringIndex: 0,
                fret: 1,
                value: NoteValue.half,
              ),
            ],
          ),
        ],
        lyrics: const [],
        sections: const [
          SongSection(id: 'bad-section', name: 'Outro', measureIndex: 4),
        ],
        repeats: const [
          RepeatRegion(
            id: 'bad-repeat',
            startMeasureIndex: 1,
            endMeasureIndex: 0,
          ),
        ],
      );

      expect(
        chart.validationErrors(),
        containsAll([
          'Measure 1 duration does not match its time signature.',
          'Measure 1 voice 1 exceeds the measure duration.',
          'Section Outro points outside the song.',
          'Repeat bad-repeat has invalid boundaries.',
        ]),
      );
    });
  });
}
