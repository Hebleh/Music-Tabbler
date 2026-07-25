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
      expect(migrated.encode(), contains('"schemaVersion":3'));
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

    test(
      'custom instruments, techniques, aligned lyrics, and proposals round-trip',
      () {
        final chart = SongChart(
          id: 'proposal',
          title: 'Proposal',
          artist: 'Band',
          instrumentName: 'Extended bass',
          capo: 1,
          tuning: const BassTuning(
            name: 'Custom 6',
            strings: [
              StringTuning(name: 'C', midiPitch: 48),
              StringTuning(name: 'G', midiPitch: 43),
              StringTuning(name: 'D', midiPitch: 38),
              StringTuning(name: 'A', midiPitch: 33),
              StringTuning(name: 'E', midiPitch: 28),
              StringTuning(name: 'B', midiPitch: 23),
            ],
          ),
          measures: [
            ChartMeasure.exact(
              number: 1,
              length: BeatFraction(4),
              verification: VerificationState.proposed,
              confidence: 0.82,
              sourceMapping: const SourceMapping(
                sourceId: 'row-1',
                left: 0,
                top: 0,
                right: 1,
                bottom: 0.5,
              ),
              notes: [
                TabNote.exact(
                  id: 'n',
                  position: BeatFraction.zero,
                  stringIndex: 5,
                  fret: 5,
                  value: NoteValue.quarter,
                  techniques: const [
                    TechniqueMark(TechniqueKind.slide),
                    TechniqueMark(TechniqueKind.bend, value: 1),
                  ],
                  verification: VerificationState.proposed,
                  confidence: 0.71,
                ),
              ],
            ),
          ],
          lyrics: [
            LyricSyllable.exact(
              id: 'lyric',
              measureIndex: 0,
              position: BeatFraction.zero,
              text: 'hey',
              alignedNoteId: 'n',
              verification: VerificationState.proposed,
              confidence: 0.66,
            ),
          ],
        );

        final restored = SongChart.decode(chart.encode());

        expect(restored.instrumentName, 'Extended bass');
        expect(restored.tuning.strings, hasLength(6));
        expect(restored.measures.single.notes.single.techniques, hasLength(2));
        expect(
          restored.measures.single.notes.single.verification,
          VerificationState.proposed,
        );
        expect(restored.lyrics.single.alignedNoteId, 'n');
        expect(
          restored.measures.single.notes.single.midiPitch(
            restored.tuning,
            capo: restored.capo,
          ),
          29,
        );
        expect(restored.validationErrors(), isEmpty);
      },
    );

    test('schema v2 charts default new instrument and verification fields', () {
      final legacy = SongChart.foundationExample().toJson()
        ..['schemaVersion'] = 2
        ..remove('instrumentName')
        ..remove('capo');
      for (final rawMeasure
          in (legacy['measures']! as List).cast<Map<String, Object>>()) {
        rawMeasure
          ..remove('verification')
          ..remove('confidence')
          ..remove('sourceMapping');
        for (final rawNote
            in (rawMeasure['notes']! as List).cast<Map<String, Object>>()) {
          rawNote
            ..remove('techniques')
            ..remove('verification')
            ..remove('confidence')
            ..remove('sourceMapping');
        }
      }
      for (final rawLyric
          in (legacy['lyrics']! as List).cast<Map<String, Object>>()) {
        rawLyric
          ..remove('alignedNoteId')
          ..remove('verification')
          ..remove('confidence')
          ..remove('sourceMapping');
      }

      final restored = SongChart.decode(jsonEncode(legacy));

      expect(restored.instrumentName, 'Bass guitar');
      expect(restored.capo, 0);
      expect(
        restored.measures.first.notes.first.verification,
        VerificationState.verified,
      );
      expect(restored.measures.first.notes.first.techniques, isEmpty);
    });

    test('proposal metadata remains explicitly unverified and validated', () {
      final invalid = SongChart(
        title: 'Invalid proposal',
        artist: '',
        tuning: BassTuning.beadg,
        measures: [
          ChartMeasure(
            number: 1,
            notes: [
              TabNote(
                id: 'bad',
                beat: 0,
                stringIndex: 9,
                fret: 50,
                value: NoteValue.quarter,
                verification: VerificationState.proposed,
                confidence: 1.2,
                sourceMapping: const SourceMapping(
                  sourceId: '',
                  left: 0.8,
                  top: 0,
                  right: 0.2,
                  bottom: 1,
                ),
              ),
            ],
          ),
        ],
        lyrics: [
          LyricSyllable(
            id: 'bad-lyric',
            measureIndex: 0,
            beat: 0,
            text: 'word',
            alignedNoteId: 'missing',
            verification: VerificationState.proposed,
          ),
        ],
      );

      expect(invalid.validationErrors(), isNotEmpty);
      expect(
        invalid.measures.single.notes.single.verification,
        VerificationState.proposed,
      );
    });
  });
}
