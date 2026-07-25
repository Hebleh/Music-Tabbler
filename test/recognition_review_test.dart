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

  test('schema v3 charts migrate with gig-ready false', () {
    final json = SongChart.foundationExample().toJson()
      ..['schemaVersion'] = 3
      ..remove('gigReady');
    expect(SongChart.fromJson(json).gigReady, isFalse);
  });
}
