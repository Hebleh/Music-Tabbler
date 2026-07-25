import '../domain/music_models.dart';

int unresolvedProposalCount(SongChart chart) {
  var count = 0;
  for (final measure in chart.measures) {
    if (measure.verification == VerificationState.proposed) count += 1;
    count += measure.notes
        .where((note) => note.verification == VerificationState.proposed)
        .length;
    count += measure.rests
        .where((rest) => rest.verification == VerificationState.proposed)
        .length;
  }
  count += chart.lyrics
      .where((lyric) => lyric.verification == VerificationState.proposed)
      .length;
  return count;
}

SongChart verifyAllProposals(SongChart chart) {
  return chart.copyWith(
    gigReady: false,
    measures: [
      for (final measure in chart.measures)
        measure.copyWith(
          verification: VerificationState.verified,
          notes: [
            for (final note in measure.notes)
              note.copyWith(verification: VerificationState.verified),
          ],
          rests: [
            for (final rest in measure.rests)
              RestEvent(
                id: rest.id,
                position: rest.position,
                value: rest.value,
                voice: rest.voice,
                dots: rest.dots,
                tuplet: rest.tuplet,
                verification: VerificationState.verified,
                confidence: rest.confidence,
                sourceMapping: rest.sourceMapping,
              ),
          ],
        ),
    ],
    lyrics: [
      for (final lyric in chart.lyrics)
        lyric.copyWith(verification: VerificationState.verified),
    ],
  );
}

SongChart markChartGigReady(SongChart chart) {
  final unresolved = unresolvedProposalCount(chart);
  if (unresolved != 0) {
    throw StateError(
      '$unresolved recognition proposal(s) still need verification.',
    );
  }
  final errors = chart.validationErrors();
  if (errors.isNotEmpty) {
    throw StateError('The chart is not valid: ${errors.join(' ')}');
  }
  return chart.copyWith(gigReady: true);
}

SongChart rejectProposedNote(SongChart chart, String noteId) {
  final note = chart.noteById(noteId);
  if (note == null) throw StateError('The proposed note no longer exists.');
  if (note.verification != VerificationState.proposed) {
    throw StateError('Verified notes cannot be rejected as proposals.');
  }
  return chart.removeNote(noteId).copyWith(gigReady: false);
}

/// Keeps user-verified note/lyric corrections when recognition is rerun.
SongChart mergeRecognitionRerun(SongChart existing, SongChart rerun) {
  final verifiedNotes = {
    for (final measure in existing.measures)
      for (final note in measure.notes)
        if (note.verification == VerificationState.verified) note.id: note,
  };
  final verifiedLyrics = {
    for (final lyric in existing.lyrics)
      if (lyric.verification == VerificationState.verified) lyric.id: lyric,
  };
  return rerun.copyWith(
    id: existing.id,
    gigReady: false,
    measures: [
      for (final measure in rerun.measures)
        measure.copyWith(
          notes: [
            for (final note in measure.notes) verifiedNotes[note.id] ?? note,
          ],
        ),
    ],
    lyrics: [
      for (final lyric in rerun.lyrics) verifiedLyrics[lyric.id] ?? lyric,
    ],
  );
}
