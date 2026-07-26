import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/application/retab_service.dart';
import 'package:music_tabbler/domain/music_models.dart';

void main() {
  const service = RetabService();

  List<int> pitches(SongChart chart) => [
    for (final measure in chart.measures)
      for (final note in measure.notes)
        note.midiPitch(chart.tuning, capo: chart.capo),
  ];

  test('same-pitch re-tab to four strings preserves pitch and rhythm', () {
    final source = SongChart.foundationExample();
    final result = service.retab(
      source: source,
      targetTuning: BassTuning.eadg,
      derivedChartId: 'four-string',
    );

    expect(pitches(result.chart), pitches(source));
    expect(result.chart.tuning.strings, hasLength(4));
    expect(
      result.chart.measures
          .expand((measure) => measure.notes)
          .map((note) => (note.position, note.value)),
      source.measures
          .expand((measure) => measure.notes)
          .map((note) => (note.position, note.value)),
    );
    expect(
      result.chart.lyrics.map((item) => item.text),
      source.lyrics.map((item) => item.text),
    );
  });

  test('four-string source can adapt to BEADG without pitch changes', () {
    final base = SongChart.foundationExample();
    final source = service
        .retab(
          source: base,
          targetTuning: BassTuning.eadg,
          derivedChartId: 'valid-four-string',
        )
        .chart;
    final result = service.retab(
      source: source,
      targetTuning: BassTuning.beadg,
      derivedChartId: 'five-string',
    );
    expect(pitches(result.chart), pitches(source));
    expect(result.chart.tuning, BassTuning.beadg);
  });

  test('strategy output is deterministic', () {
    final source = SongChart.foundationExample();
    for (final strategy in RetabStrategy.values) {
      final first = service.retab(
        source: source,
        targetTuning: BassTuning.eadg,
        derivedChartId: 'first',
        strategy: strategy,
      );
      final second = service.retab(
        source: source,
        targetTuning: BassTuning.eadg,
        derivedChartId: 'second',
        strategy: strategy,
      );
      expect(
        first.chart.measures
            .expand((measure) => measure.notes)
            .map((note) => (note.stringIndex, note.fret)),
        second.chart.measures
            .expand((measure) => measure.notes)
            .map((note) => (note.stringIndex, note.fret)),
      );
      expect(first.explanation, isNotEmpty);
    }
  });
}
