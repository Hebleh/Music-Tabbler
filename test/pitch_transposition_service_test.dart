import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/application/pitch_transposition_service.dart';
import 'package:music_tabbler/domain/music_models.dart';

void main() {
  const service = PitchTranspositionService();

  List<int> pitches(SongChart chart) => [
    for (final measure in chart.measures)
      for (final note in measure.notes)
        note.midiPitch(chart.tuning, capo: chart.capo),
  ];

  test(
    '+1 changes every sounding pitch while preserving rhythm and lyrics',
    () {
      final source = SongChart.foundationExample();
      final result = service.transpose(
        source: source,
        semitones: 1,
        derivedChartId: 'plus-one',
      );

      expect(pitches(result.chart), pitches(source).map((value) => value + 1));
      expect(
        result.chart.measures
            .expand((measure) => measure.notes)
            .map((note) => (note.position, note.value)),
        source.measures
            .expand((measure) => measure.notes)
            .map((note) => (note.position, note.value)),
      );
      expect(
        result.chart.lyrics.map((lyric) => lyric.text),
        source.lyrics.map((lyric) => lyric.text),
      );
      expect(result.chart.derivedFromChartId, source.id);
      expect(result.chart.transformationLabel, 'Transpose +1');
      expect(result.chart.gigReady, isFalse);
    },
  );

  test('same-string shift is preferred when it remains playable', () {
    final source = SongChart.foundationExample();
    final result = service.transpose(
      source: source,
      semitones: 1,
      derivedChartId: 'plus-one',
    );
    expect(
      result.chart.measures.first.notes.first.stringIndex,
      source.measures.first.notes.first.stringIndex,
    );
    expect(
      result.chart.measures.first.notes.first.fret,
      source.measures.first.notes.first.fret + 1,
    );
  });

  test('unverified recognition cannot be transformed', () {
    final source = SongChart.foundationExample();
    final proposed = source.replaceNote(
      source.measures.first.notes.first.copyWith(
        verification: VerificationState.proposed,
      ),
    );
    expect(
      () => service.transpose(
        source: proposed,
        semitones: 1,
        derivedChartId: 'unsafe',
      ),
      throwsStateError,
    );
  });

  test('schema v4 charts migrate without variant lineage', () {
    final json = SongChart.foundationExample().toJson()
      ..['schemaVersion'] = 4
      ..remove('derivedFromChartId')
      ..remove('transformationLabel');
    final restored = SongChart.fromJson(json);
    expect(restored.derivedFromChartId, isNull);
    expect(restored.transformationLabel, isNull);
  });
}
