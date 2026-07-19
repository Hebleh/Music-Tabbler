enum NoteValue {
  whole('Semibreve', 4),
  half('Minim', 2),
  quarter('Crotchet', 1),
  eighth('Quaver', 0.5),
  sixteenth('Semiquaver', 0.25);

  const NoteValue(this.label, this.quarterNotes);

  final String label;
  final double quarterNotes;
}

class StringTuning {
  const StringTuning({required this.name, required this.midiPitch});

  final String name;
  final int midiPitch;
}

class BassTuning {
  const BassTuning({required this.name, required this.strings});

  final String name;

  /// Display order is highest string to lowest string, matching tablature.
  final List<StringTuning> strings;

  static const beadg = BassTuning(
    name: '5-string BEADG',
    strings: [
      StringTuning(name: 'G', midiPitch: 43),
      StringTuning(name: 'D', midiPitch: 38),
      StringTuning(name: 'A', midiPitch: 33),
      StringTuning(name: 'E', midiPitch: 28),
      StringTuning(name: 'B', midiPitch: 23),
    ],
  );
}

class TabNote {
  const TabNote({
    required this.id,
    required this.beat,
    required this.stringIndex,
    required this.fret,
    required this.value,
  });

  final String id;
  final double beat;
  final int stringIndex;
  final int fret;
  final NoteValue value;

  int midiPitch(BassTuning tuning) =>
      tuning.strings[stringIndex].midiPitch + fret;

  TabNote copyWith({
    double? beat,
    int? stringIndex,
    int? fret,
    NoteValue? value,
  }) {
    return TabNote(
      id: id,
      beat: beat ?? this.beat,
      stringIndex: stringIndex ?? this.stringIndex,
      fret: fret ?? this.fret,
      value: value ?? this.value,
    );
  }
}

class ChartMeasure {
  const ChartMeasure({
    required this.number,
    required this.notes,
    this.beats = 4,
  });

  final int number;
  final double beats;
  final List<TabNote> notes;

  ChartMeasure replaceNote(TabNote replacement) {
    return ChartMeasure(
      number: number,
      beats: beats,
      notes: [
        for (final note in notes)
          if (note.id == replacement.id) replacement else note,
      ],
    );
  }
}

class LyricSyllable {
  const LyricSyllable({
    required this.id,
    required this.measureIndex,
    required this.beat,
    required this.text,
    this.isBackingVocal = false,
  });

  final String id;
  final int measureIndex;
  final double beat;
  final String text;
  final bool isBackingVocal;

  LyricSyllable copyWith({String? text, bool? isBackingVocal}) {
    return LyricSyllable(
      id: id,
      measureIndex: measureIndex,
      beat: beat,
      text: text ?? this.text,
      isBackingVocal: isBackingVocal ?? this.isBackingVocal,
    );
  }
}

class SongChart {
  const SongChart({
    required this.title,
    required this.artist,
    required this.tuning,
    required this.measures,
    required this.lyrics,
  });

  final String title;
  final String artist;
  final BassTuning tuning;
  final List<ChartMeasure> measures;
  final List<LyricSyllable> lyrics;

  TabNote? noteById(String id) {
    for (final measure in measures) {
      for (final note in measure.notes) {
        if (note.id == id) return note;
      }
    }
    return null;
  }

  SongChart replaceNote(TabNote replacement) {
    return SongChart(
      title: title,
      artist: artist,
      tuning: tuning,
      measures: [
        for (final measure in measures) measure.replaceNote(replacement),
      ],
      lyrics: lyrics,
    );
  }

  SongChart replaceLyric(LyricSyllable replacement) {
    return SongChart(
      title: title,
      artist: artist,
      tuning: tuning,
      measures: measures,
      lyrics: [
        for (final lyric in lyrics)
          if (lyric.id == replacement.id) replacement else lyric,
      ],
    );
  }

  static SongChart foundationExample() {
    return const SongChart(
      title: 'Foundation Groove',
      artist: 'Music Tabbler',
      tuning: BassTuning.beadg,
      measures: [
        ChartMeasure(
          number: 1,
          notes: [
            TabNote(
              id: 'n1',
              beat: 0,
              stringIndex: 3,
              fret: 3,
              value: NoteValue.quarter,
            ),
            TabNote(
              id: 'n2',
              beat: 1,
              stringIndex: 3,
              fret: 3,
              value: NoteValue.eighth,
            ),
            TabNote(
              id: 'n3',
              beat: 2,
              stringIndex: 2,
              fret: 1,
              value: NoteValue.quarter,
            ),
            TabNote(
              id: 'n4',
              beat: 3,
              stringIndex: 2,
              fret: 3,
              value: NoteValue.eighth,
            ),
          ],
        ),
        ChartMeasure(
          number: 2,
          notes: [
            TabNote(
              id: 'n5',
              beat: 0,
              stringIndex: 1,
              fret: 3,
              value: NoteValue.quarter,
            ),
            TabNote(
              id: 'n6',
              beat: 1,
              stringIndex: 2,
              fret: 5,
              value: NoteValue.quarter,
            ),
            TabNote(
              id: 'n7',
              beat: 2,
              stringIndex: 3,
              fret: 5,
              value: NoteValue.eighth,
            ),
            TabNote(
              id: 'n8',
              beat: 3,
              stringIndex: 4,
              fret: 5,
              value: NoteValue.quarter,
            ),
          ],
        ),
      ],
      lyrics: [
        LyricSyllable(id: 'l1', measureIndex: 0, beat: 0, text: 'main'),
        LyricSyllable(id: 'l2', measureIndex: 0, beat: 2, text: 'vo-cal'),
        LyricSyllable(
          id: 'l3',
          measureIndex: 1,
          beat: 0,
          text: 'BACK',
          isBackingVocal: true,
        ),
        LyricSyllable(
          id: 'l4',
          measureIndex: 1,
          beat: 2,
          text: 'ING',
          isBackingVocal: true,
        ),
      ],
    );
  }
}
