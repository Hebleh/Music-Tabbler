import 'dart:convert';

enum NoteValue {
  whole('Semibreve', 4),
  half('Minim', 2),
  quarter('Crotchet', 1),
  eighth('Quaver', 0.5),
  sixteenth('Semiquaver', 0.25);

  const NoteValue(this.label, this.quarterNotes);

  final String label;
  final double quarterNotes;

  Map<String, Object> toJson() => {'name': name};
}

class StringTuning {
  const StringTuning({required this.name, required this.midiPitch});

  final String name;
  final int midiPitch;

  Map<String, Object> toJson() => {'name': name, 'midiPitch': midiPitch};

  factory StringTuning.fromJson(Map<String, Object?> json) => StringTuning(
    name: json['name']! as String,
    midiPitch: json['midiPitch']! as int,
  );
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

  static const eadg = BassTuning(
    name: '4-string EADG',
    strings: [
      StringTuning(name: 'G', midiPitch: 43),
      StringTuning(name: 'D', midiPitch: 38),
      StringTuning(name: 'A', midiPitch: 33),
      StringTuning(name: 'E', midiPitch: 28),
    ],
  );

  Map<String, Object> toJson() => {
    'name': name,
    'strings': [for (final string in strings) string.toJson()],
  };

  factory BassTuning.fromJson(Map<String, Object?> json) => BassTuning(
    name: json['name']! as String,
    strings: List.unmodifiable(
      (json['strings']! as List).map(
        (value) =>
            StringTuning.fromJson((value as Map).cast<String, Object?>()),
      ),
    ),
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

  Map<String, Object> toJson() => {
    'id': id,
    'beat': beat,
    'stringIndex': stringIndex,
    'fret': fret,
    'value': value.name,
  };

  factory TabNote.fromJson(Map<String, Object?> json) => TabNote(
    id: json['id']! as String,
    beat: (json['beat']! as num).toDouble(),
    stringIndex: json['stringIndex']! as int,
    fret: json['fret']! as int,
    value: NoteValue.values.byName(json['value']! as String),
  );
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

  Map<String, Object> toJson() => {
    'number': number,
    'beats': beats,
    'notes': [for (final note in notes) note.toJson()],
  };

  factory ChartMeasure.fromJson(Map<String, Object?> json) => ChartMeasure(
    number: json['number']! as int,
    beats: (json['beats']! as num).toDouble(),
    notes: List.unmodifiable(
      (json['notes']! as List).map(
        (value) => TabNote.fromJson((value as Map).cast<String, Object?>()),
      ),
    ),
  );
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

  Map<String, Object> toJson() => {
    'id': id,
    'measureIndex': measureIndex,
    'beat': beat,
    'text': text,
    'isBackingVocal': isBackingVocal,
  };

  factory LyricSyllable.fromJson(Map<String, Object?> json) => LyricSyllable(
    id: json['id']! as String,
    measureIndex: json['measureIndex']! as int,
    beat: (json['beat']! as num).toDouble(),
    text: json['text']! as String,
    isBackingVocal: json['isBackingVocal'] as bool? ?? false,
  );
}

class SongChart {
  const SongChart({
    this.id = 'semantic-foundation',
    required this.title,
    required this.artist,
    required this.tuning,
    required this.measures,
    required this.lyrics,
  });

  static const schemaVersion = 1;

  final String id;
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
      id: id,
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
      id: id,
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

  SongChart copyWith({
    String? id,
    String? title,
    String? artist,
    BassTuning? tuning,
    List<ChartMeasure>? measures,
    List<LyricSyllable>? lyrics,
  }) {
    return SongChart(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      tuning: tuning ?? this.tuning,
      measures: measures ?? this.measures,
      lyrics: lyrics ?? this.lyrics,
    );
  }

  Map<String, Object> toJson() => {
    'schemaVersion': schemaVersion,
    'id': id,
    'title': title,
    'artist': artist,
    'tuning': tuning.toJson(),
    'measures': [for (final measure in measures) measure.toJson()],
    'lyrics': [for (final lyric in lyrics) lyric.toJson()],
  };

  String encode() => jsonEncode(toJson());

  factory SongChart.fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'] as int? ?? 1;
    if (version != schemaVersion) {
      throw FormatException('Unsupported semantic chart schema $version.');
    }
    return SongChart(
      id: json['id']! as String,
      title: json['title']! as String,
      artist: json['artist']! as String,
      tuning: BassTuning.fromJson(
        (json['tuning']! as Map).cast<String, Object?>(),
      ),
      measures: List.unmodifiable(
        (json['measures']! as List).map(
          (value) =>
              ChartMeasure.fromJson((value as Map).cast<String, Object?>()),
        ),
      ),
      lyrics: List.unmodifiable(
        (json['lyrics']! as List).map(
          (value) =>
              LyricSyllable.fromJson((value as Map).cast<String, Object?>()),
        ),
      ),
    );
  }

  factory SongChart.decode(String source) =>
      SongChart.fromJson((jsonDecode(source) as Map).cast<String, Object?>());

  static SongChart foundationExample() {
    return const SongChart(
      id: 'semantic-foundation',
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
