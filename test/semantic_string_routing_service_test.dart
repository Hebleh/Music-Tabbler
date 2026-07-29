import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/application/semantic_string_routing_service.dart';
import 'package:music_tabbler/domain/music_models.dart';

void main() {
  test('Motion Sickness DADG to BEADG preserves pitch and adds unused E', () {
    const sourceTuning = BassTuning(
      name: 'DADG',
      strings: [
        StringTuning(name: 'G', midiPitch: 43),
        StringTuning(name: 'D', midiPitch: 38),
        StringTuning(name: 'A', midiPitch: 33),
        StringTuning(name: 'D', midiPitch: 26),
      ],
    );
    final source = _chart(
      tuning: sourceTuning,
      notes: [
        TabNote(
          id: 'low-d',
          stringIndex: 3,
          fret: 2,
          beat: 0,
          value: NoteValue.quarter,
        ),
      ],
    );

    final result = const SemanticStringRoutingService().transform(
      source: source,
      targetTuning: BassTuning.beadg,
      targetCapo: 0,
      globalPitchChange: 0,
      derivedChartId: 'motion-five',
      routeConstraints: {0: 0, 1: 1, 2: 2, 3: 4},
    );

    final note = result.chart.measures.single.notes.single;
    expect(note.stringIndex, 4);
    expect(note.fret, 5);
    expect(note.midiPitch(result.chart.tuning, capo: result.chart.capo), 28);
  });

  test('Rock With You keeps frets with pitch -2 and target capo 2', () {
    const sourceTuning = BassTuning(
      name: 'D# G# C# F#',
      strings: [
        StringTuning(name: 'F#', midiPitch: 42),
        StringTuning(name: 'C#', midiPitch: 37),
        StringTuning(name: 'G#', midiPitch: 32),
        StringTuning(name: 'D#', midiPitch: 27),
      ],
    );
    final source = _chart(
      tuning: sourceTuning,
      notes: [
        TabNote(
          id: 'note',
          stringIndex: 0,
          fret: 7,
          beat: 0,
          value: NoteValue.quarter,
        ),
      ],
    );

    final result = const SemanticStringRoutingService().transform(
      source: source,
      targetTuning: BassTuning.beadg,
      targetCapo: 2,
      globalPitchChange: -2,
      derivedChartId: 'rock-five',
      routeConstraints: {0: 1, 1: 2, 2: 3, 3: 4},
    );

    final note = result.chart.measures.single.notes.single;
    expect(note.stringIndex, 1);
    expect(note.fret, 7);
    expect(note.midiPitch(result.chart.tuning, capo: result.chart.capo), 47);
  });

  test('selected-string override changes only notes on that source string', () {
    final source = _chart(
      tuning: BassTuning.eadg,
      notes: [
        TabNote(
          id: 'high',
          stringIndex: 0,
          fret: 2,
          beat: 0,
          value: NoteValue.quarter,
        ),
        TabNote(
          id: 'low',
          stringIndex: 3,
          fret: 2,
          beat: 1,
          value: NoteValue.quarter,
        ),
      ],
    );

    final result = const SemanticStringRoutingService().transform(
      source: source,
      targetTuning: BassTuning.eadg,
      targetCapo: 0,
      globalPitchChange: 0,
      selectedStringPitchChanges: {3: 3},
      derivedChartId: 'selected',
    );

    final notes = result.chart.measures.single.notes;
    expect(notes[0].midiPitch(result.chart.tuning), 45);
    expect(notes[1].midiPitch(result.chart.tuning), 33);
    expect(result.pitchChangedNotes, 1);
  });
}

SongChart _chart({required BassTuning tuning, required List<TabNote> notes}) {
  return SongChart(
    id: 'source',
    title: 'Fixture',
    artist: '',
    tuning: tuning,
    measures: [ChartMeasure(number: 1, notes: notes)],
    lyrics: const [],
  );
}
