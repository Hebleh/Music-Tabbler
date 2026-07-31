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

/// Repairs proposal geometry created by older recognition builds.
///
/// Verified user edits are never changed. Proposed notes with source geometry
/// are re-positioned from that geometry, and obvious consecutive measure-label
/// runs are removed from the in-memory review chart.
SongChart normalizeRecognitionProposals(SongChart chart) {
  return chart.copyWith(
    measures: [
      for (final measure in chart.measures)
        _normalizeRecognitionMeasure(measure),
    ],
  );
}

ChartMeasure _normalizeRecognitionMeasure(ChartMeasure measure) {
  final measureMapping = measure.sourceMapping;
  final proposed =
      measure.notes
          .where(
            (note) =>
                note.verification == VerificationState.proposed &&
                note.sourceMapping != null,
          )
          .toList()
        ..sort(
          (a, b) => a.sourceMapping!.left.compareTo(b.sourceMapping!.left),
        );
  final rejected = <String>{};
  for (var start = 0; start < proposed.length; start += 1) {
    final first = proposed[start];
    // Do not guess that ordinary consecutive frets are labels. The legacy
    // charts being repaired admitted printed system measure numbers in the
    // 20-36 range.
    if (first.fret < 20) continue;
    final run = <TabNote>[first];
    for (var index = start + 1; index < proposed.length; index += 1) {
      final previous = run.last;
      final next = proposed[index];
      if (next.fret != previous.fret + 1 ||
          (_sourceCenterY(next) - _sourceCenterY(previous)).abs() > 0.025) {
        break;
      }
      run.add(next);
    }
    if (run.length >= 3) rejected.addAll(run.map((note) => note.id));
  }
  final emptyUnverifiedProposal =
      measure.notes.isEmpty &&
      measure.rests.isEmpty &&
      measure.sourceMapping != null &&
      (measure.confidence ?? 0) == 0;
  return measure.copyWith(
    verification: emptyUnverifiedProposal
        ? VerificationState.proposed
        : measure.verification,
    notes: [
      for (final note in measure.notes)
        if (!rejected.contains(note.id))
          note.verification == VerificationState.proposed &&
                  note.sourceMapping != null
              ? note.copyWith(
                  position: BeatFraction(
                    (_relativeSourceCenterX(
                              note.sourceMapping!,
                              measureMapping,
                            ).clamp(0.0, 0.9999) *
                            measure.length.value *
                            1000)
                        .round(),
                    1000,
                  ),
                )
              : note,
    ],
  );
}

double _relativeSourceCenterX(SourceMapping note, SourceMapping? measure) {
  final center = (note.left + note.right) / 2;
  if (measure == null ||
      measure.sourceId != note.sourceId ||
      measure.right - measure.left <= 0.000001) {
    return center;
  }
  return (center - measure.left) / (measure.right - measure.left);
}

double _sourceCenterY(TabNote note) =>
    (note.sourceMapping!.top + note.sourceMapping!.bottom) / 2;

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

SongChart verifyProposedNote(SongChart chart, String noteId) {
  final note = chart.noteById(noteId);
  if (note == null) throw StateError('The proposed note no longer exists.');
  if (note.verification != VerificationState.proposed) {
    throw StateError('Only proposed notes can be verified here.');
  }
  return chart
      .replaceNote(note.copyWith(verification: VerificationState.verified))
      .copyWith(gigReady: false);
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
