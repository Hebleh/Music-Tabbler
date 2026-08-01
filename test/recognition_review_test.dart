import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/application/recognition_review.dart';
import 'package:music_tabbler/domain/music_models.dart';

void main() {
  SongChart proposal() {
    final base = SongChart.foundationExample();
    return base.copyWith(
      measures: [
        base.measures.first.copyWith(
          verification: VerificationState.proposed,
          notes: [
            base.measures.first.notes.first.copyWith(
              verification: VerificationState.proposed,
              confidence: 0.5,
            ),
          ],
        ),
      ],
      lyrics: const [],
    );
  }

  test('gig-ready requires explicit verification and valid content', () {
    final proposed = proposal();
    expect(unresolvedProposalCount(proposed), 2);
    expect(() => markChartGigReady(proposed), throwsStateError);

    final verified = verifyAllProposals(proposed);
    expect(unresolvedProposalCount(verified), 0);
    expect(markChartGigReady(verified).gigReady, isTrue);
  });

  test('reject only removes proposed notes', () {
    final proposed = proposal();
    final noteId = proposed.measures.single.notes.single.id;
    expect(rejectProposedNote(proposed, noteId).measures.single.notes, isEmpty);
    final verified = verifyAllProposals(proposed);
    expect(() => rejectProposedNote(verified, noteId), throwsStateError);
  });

  test('verify selected accepts only one proposed note', () {
    final proposed = proposal();
    final noteId = proposed.measures.single.notes.single.id;
    final accepted = verifyProposedNote(proposed, noteId);

    expect(accepted.noteById(noteId)!.verification, VerificationState.verified);
    expect(accepted.measures.single.verification, VerificationState.proposed);
    expect(unresolvedProposalCount(accepted), 1);
    expect(() => verifyProposedNote(accepted, noteId), throwsStateError);
  });

  test('rerun preserves verified user corrections by stable proposal ID', () {
    final original = proposal();
    final correctedNote = original.measures.single.notes.single.copyWith(
      fret: 9,
      verification: VerificationState.verified,
    );
    final corrected = original.replaceNote(correctedNote);
    final rerunNote = original.measures.single.notes.single.copyWith(fret: 2);
    final rerun = original.replaceNote(rerunNote);

    final merged = mergeRecognitionRerun(corrected, rerun);
    expect(merged.measures.single.notes.single.fret, 9);
    expect(
      merged.measures.single.notes.single.verification,
      VerificationState.verified,
    );
    expect(merged.gigReady, isFalse);
  });

  test(
    'legacy proposal geometry is repaired without changing verified notes',
    () {
      final chart = SongChart(
        id: 'legacy-recognition',
        title: 'Legacy',
        artist: '',
        tuning: BassTuning.eadg,
        lyrics: const [],
        measures: [
          ChartMeasure.exact(
            number: 1,
            length: BeatFraction(4),
            notes: [
              for (var index = 0; index < 4; index += 1)
                TabNote.exact(
                  id: 'measure-$index',
                  position: BeatFraction(index, 4),
                  stringIndex: 0,
                  fret: 31 + index,
                  value: NoteValue.quarter,
                  verification: VerificationState.proposed,
                  sourceMapping: SourceMapping(
                    sourceId: 'row',
                    left: 0.1 + index * 0.15,
                    top: 0.2,
                    right: 0.13 + index * 0.15,
                    bottom: 0.24,
                  ),
                ),
              TabNote.exact(
                id: 'real',
                position: BeatFraction.zero,
                stringIndex: 2,
                fret: 7,
                value: NoteValue.quarter,
                verification: VerificationState.proposed,
                sourceMapping: const SourceMapping(
                  sourceId: 'row',
                  left: 0.75,
                  top: 0.55,
                  right: 0.78,
                  bottom: 0.59,
                ),
              ),
              TabNote.exact(
                id: 'verified',
                position: BeatFraction.one,
                stringIndex: 1,
                fret: 12,
                value: NoteValue.quarter,
                verification: VerificationState.verified,
                sourceMapping: const SourceMapping(
                  sourceId: 'row',
                  left: 0.9,
                  top: 0.3,
                  right: 0.93,
                  bottom: 0.34,
                ),
              ),
            ],
          ),
        ],
      );

      final normalized = normalizeRecognitionProposals(chart);
      final notes = normalized.measures.single.notes;
      expect(notes.map((note) => note.id), ['real', 'verified']);
      expect(notes.first.position.value, closeTo(3.06, 0.01));
      expect(notes.last.position, BeatFraction.one);
    },
  );

  test('proposal positions are normalized inside their source measure', () {
    final chart = SongChart(
      id: 'split-recognition',
      title: 'Split',
      artist: '',
      tuning: BassTuning.eadg,
      lyrics: const [],
      measures: [
        ChartMeasure.exact(
          number: 1,
          length: BeatFraction(4),
          verification: VerificationState.proposed,
          sourceMapping: const SourceMapping(
            sourceId: 'page.png',
            left: 0.40,
            top: 0.20,
            right: 0.60,
            bottom: 0.30,
          ),
          notes: [
            TabNote.exact(
              id: 'inside-measure',
              position: BeatFraction.zero,
              stringIndex: 0,
              fret: 7,
              value: NoteValue.quarter,
              verification: VerificationState.proposed,
              sourceMapping: const SourceMapping(
                sourceId: 'page.png',
                left: 0.49,
                top: 0.23,
                right: 0.51,
                bottom: 0.27,
              ),
            ),
          ],
        ),
      ],
    );

    final normalized = normalizeRecognitionProposals(chart);
    expect(
      normalized.measures.single.notes.single.position.value,
      closeTo(2, 0.001),
    );
  });

  test('schema v3 charts migrate with gig-ready false', () {
    final json = SongChart.foundationExample().toJson()
      ..['schemaVersion'] = 3
      ..remove('gigReady');
    expect(SongChart.fromJson(json).gigReady, isFalse);
  });

  test('legacy empty recognition rows cannot silently become gig-ready', () {
    final chart = SongChart(
      id: 'empty-recognition',
      title: 'Empty proposal',
      artist: '',
      tuning: BassTuning.eadg,
      lyrics: const [],
      measures: [
        ChartMeasure.exact(
          number: 1,
          length: BeatFraction(4),
          notes: const [],
          verification: VerificationState.verified,
          confidence: 0,
          sourceMapping: const SourceMapping(
            sourceId: 'row.png',
            left: 0,
            top: 0.1,
            right: 1,
            bottom: 0.9,
          ),
        ),
      ],
    );

    final normalized = normalizeRecognitionProposals(chart);
    expect(normalized.measures.single.verification, VerificationState.proposed);
    expect(unresolvedProposalCount(normalized), 1);
    expect(() => markChartGigReady(normalized), throwsStateError);
  });

  test(
    'incomplete recognition source cannot be bulk-approved as gig-ready',
    () {
      final chart = SongChart.foundationExample().copyWith(
        recognitionSourceComplete: false,
        measures: [
          for (final measure in SongChart.foundationExample().measures)
            measure.copyWith(
              verification: VerificationState.verified,
              notes: [
                for (final note in measure.notes)
                  note.copyWith(verification: VerificationState.verified),
              ],
            ),
        ],
      );

      expect(chart.recognitionSourceComplete, isFalse);
      expect(() => markChartGigReady(chart), throwsStateError);
      final restored = SongChart.fromJson(chart.toJson());
      expect(restored.recognitionSourceComplete, isFalse);
    },
  );
}
